-- Auto Dialog Picker for Cyberpunk 2077 (Cyber Engine Tweaks mod)
--
-- Plays conversations for you, like the Witcher 3 "Automatic dialog picker":
--   Include optional  : hears every unread optional line first, then takes the
--                       story (yellow) line when it is the only one.
--   Skip optional     : goes straight to the story line when it is the only one.
-- When there are several story lines, money/illegal lines or nothing sensible
-- to pick, the menu is left to you (or, if you choose, the first plain story
-- line is taken).
--
-- The game has no script function that selects a dialogue line, so this mod
-- decides what to pick and the small AutoHotkey helper next to this file
-- presses the keys (scroll + F). They talk through cmd.txt in this folder.

local Logic = require("logic")

local MOD_NAME = "Auto Dialog Picker"
local VERSION = "1.0.0"

local SETTINGS_FILE = "settings.json"
local CMD_FILE = "cmd.txt"
local HELPER_FILE = "helper_alive.txt"

local TICK = 0.1             -- seconds between checks
local STEP_TIMEOUT = 0.4     -- wait this long for a scroll to register
local SELECTED_TIMEOUT = 4.0 -- after pressing select, wait for the menu to change
local PICKED_MEMORY = 600    -- seconds an auto-picked optional line counts as heard
local HELPER_STALE = 5       -- seconds without a helper heartbeat = helper not running

local MODE_NAMES = { "Include optional dialogue", "Skip optional dialogue" }
local STORY_NAMES = { "Let me choose", "Pick the first plain story line" }

local settings = {
    enabled = true,
    mode = Logic.MODE_INCLUDE_OPTIONAL,
    storyRule = Logic.STORY_LET_ME_CHOOSE,
    delay = 0.8,
    conversationsOnly = true,
    showNotice = true,
    debug = false,
}

local S = {
    ready = false,
    broken = nil,          -- error text if the game API did not behave as expected
    clock = 0,
    acc = 0,
    overlayOpen = false,
    phase = "idle",        -- idle | waiting | navigating | selected
    sig = nil,             -- signature of the menu being handled
    handledSig = nil,      -- menu we already acted on (or decided to leave alone)
    target = nil,          -- 0-based line to select
    targetText = nil,
    targetKey = nil,
    reason = nil,
    startSel = nil,
    phaseStart = 0,
    steps = 0,
    maxSteps = 0,
    lastStepAt = -1,
    lastStepSel = nil,
    seq = 0,
    picked = {},           -- key -> clock time when auto-picked
    helperAlive = false,
    helperCheckAt = -100,
    toastText = nil,
    toastUntil = 0,
}

local CT = {}        -- gameinteractionsChoiceType enums
local PART_ICON = nil
local PART_TAG = nil

------------------------------------------------------------------------------
-- helpers
------------------------------------------------------------------------------

local function log(msg)
    spdlog.info(msg)
    if settings.debug then print("[AutoDialogPicker] " .. msg) end
end

local function toast(text, seconds)
    S.toastText = text
    S.toastUntil = S.clock + (seconds or 2.5)
end

local function loadSettings()
    local f = io.open(SETTINGS_FILE, "r")
    if not f then return end
    local raw = f:read("*a")
    f:close()
    local ok, data = pcall(json.decode, raw)
    if ok and type(data) == "table" then
        for k, v in pairs(data) do
            if settings[k] ~= nil and type(v) == type(settings[k]) then
                settings[k] = v
            end
        end
    end
    if settings.mode ~= 1 and settings.mode ~= 2 then settings.mode = 1 end
    if settings.storyRule ~= 1 and settings.storyRule ~= 2 then settings.storyRule = 1 end
    if settings.delay < 0.2 then settings.delay = 0.2 end
    if settings.delay > 5 then settings.delay = 5 end
end

local function saveSettings()
    local f = io.open(SETTINGS_FILE, "w")
    if not f then return end
    f:write(json.encode(settings))
    f:close()
end

local function sendCommand(action)
    S.seq = S.seq + 1
    local f = io.open(CMD_FILE, "w")
    if not f then
        log("could not write " .. CMD_FILE)
        return
    end
    f:write(string.format("%d|%s|%d", S.seq, action, os.time()))
    f:close()
end

local function checkHelper()
    if S.clock - S.helperCheckAt < 2 then return end
    S.helperCheckAt = S.clock
    local alive = false
    local f = io.open(HELPER_FILE, "r")
    if f then
        local stamp = tonumber((f:read("*l") or ""):match("%d+"))
        f:close()
        if stamp and math.abs(os.time() - stamp) <= HELPER_STALE then alive = true end
    end
    if alive ~= S.helperAlive then
        log(alive and "helper is running" or "helper is not running")
    end
    S.helperAlive = alive
end

local function resetPhase()
    S.phase = "idle"
    S.sig = nil
    S.target = nil
    S.targetText = nil
    S.targetKey = nil
end

local function cancel(why)
    log("cancelled: " .. why)
    S.handledSig = S.sig
    resetPhase()
end

------------------------------------------------------------------------------
-- reading the game
------------------------------------------------------------------------------

local function nameToString(cname)
    if cname == nil then return "" end
    local ok, s = pcall(function() return cname.value end)
    if ok and type(s) == "string" then return s end
    ok, s = pcall(NameToString, cname)
    if ok and type(s) == "string" then return s end
    return tostring(cname)
end

local function isType(choiceType, enum)
    return ChoiceTypeWrapper.IsType(choiceType, enum) == true
end

-- Turns a game ListChoiceData into the plain table logic.lua expects.
local function toChoice(c, index)
    local t = c.type
    local choice = {
        index = index,
        text = c.localizedName or "",
        questImportant = isType(t, CT.QuestImportant),
        alreadyRead = isType(t, CT.AlreadyRead),
        inactive = isType(t, CT.Inactive),
        checkFailed = isType(t, CT.CheckFailed),
        checkSuccess = isType(t, CT.CheckSuccess),
        pay = isType(t, CT.Pay),
        illegal = isType(t, CT.Illegal),
        blueline = isType(t, CT.Blueline),
        glowline = isType(t, CT.Glowline),
        timed = isType(t, CT.TimedDialog),
        hasIcon = false,
        hasTag = false,
        dedicatedInput = false,
    }

    local caption = c.captionParts
    local parts = caption and caption.parts or {}
    for _, part in ipairs(parts) do
        local ok, kind = pcall(function() return EnumInt(part:GetType()) end)
        if ok then
            if kind == PART_ICON then choice.hasIcon = true end
            if kind == PART_TAG then choice.hasTag = true end
        end
    end
    if string.sub(choice.text, 1, 1) == "[" then choice.hasTag = true end

    local input = nameToString(c.inputActionName)
    choice.dedicatedInput = input ~= "" and input ~= "None"

    return choice
end

local function flagString(c)
    local f = {}
    if c.questImportant then f[#f + 1] = "Q" end
    if c.alreadyRead then f[#f + 1] = "R" end
    if c.inactive then f[#f + 1] = "I" end
    if c.checkFailed then f[#f + 1] = "F" end
    if c.checkSuccess then f[#f + 1] = "S" end
    if c.pay then f[#f + 1] = "$" end
    if c.illegal then f[#f + 1] = "!" end
    if c.blueline then f[#f + 1] = "B" end
    if c.glowline then f[#f + 1] = "G" end
    if c.timed then f[#f + 1] = "T" end
    if c.hasIcon then f[#f + 1] = "icon" end
    if c.dedicatedInput then f[#f + 1] = "key" end
    return table.concat(f, ",")
end

-- Returns hubs, activeHubId, selectedIndex (or nil when nothing can be read).
local function readHubs()
    local defs = GetAllBlackboardDefs()
    local bb = Game.GetBlackboardSystem():Get(defs.UIInteractions)
    if not bb then return nil end
    local data = FromVariant(bb:GetVariant(defs.UIInteractions.DialogChoiceHubs))
    local hubs = (data and data.choiceHubs) or {}
    return hubs, bb:GetInt(defs.UIInteractions.ActiveChoiceHubID), bb:GetInt(defs.UIInteractions.SelectedIndex)
end

local function isInMenu()
    local defs = GetAllBlackboardDefs()
    local bb = Game.GetBlackboardSystem():Get(defs.UI_System)
    return bb ~= nil and bb:GetBool(defs.UI_System.IsInMenu)
end

-- True while V is actually in a conversation, so the mod does not start
-- conversations by itself when you merely look at an NPC or a vendor.
local function isInConversation(player)
    local ok, tier = pcall(PlayerPuppet.GetSceneTier, player)
    if ok and type(tier) == "number" and tier >= 2 then return true end
    local ok2, inDialogue = pcall(function()
        return Game.GetSceneSystem():GetScriptInterface():IsEntityInDialogue(player:GetEntityID())
    end)
    return ok2 and inDialogue == true
end

------------------------------------------------------------------------------
-- the picker
------------------------------------------------------------------------------

local function pickedKey(hub, choice)
    return (hub.title or "") .. "\31" .. choice.text
end

local function prunePicked()
    for k, t in pairs(S.picked) do
        if S.clock - t > PICKED_MEMORY then S.picked[k] = nil end
    end
end

local function tick()
    local player = Game.GetPlayer()
    if not player or S.overlayOpen or isInMenu() then
        if S.phase ~= "idle" and S.phase ~= "selected" then resetPhase() end
        return
    end

    local hubs, activeId, sel = readHubs()
    if hubs == nil then return end

    if #hubs == 0 then
        -- menu closed: the same menu may be handled again next time it opens
        if S.phase ~= "idle" then resetPhase() end
        S.handledSig = nil
        return
    end

    -- Several menus at once (two NPCs, phone + person...): leave it to you.
    if #hubs ~= 1 then
        if S.phase ~= "idle" then resetPhase() end
        return
    end

    local hub = hubs[1]
    local choices, sigParts = {}, { tostring(hub.id), hub.title or "" }
    for i, c in ipairs(hub.choices or {}) do
        local choice = toChoice(c, i)
        choices[#choices + 1] = choice
        sigParts[#sigParts + 1] = choice.text .. ":" .. flagString(choice)
    end
    local sig = table.concat(sigParts, "\30")

    if S.phase ~= "idle" and sig ~= S.sig then
        -- the menu changed (the pick went through, or the scene moved on)
        resetPhase()
    end

    -- The menu is shown but not focused (you are not looking at it).
    if hub.id ~= activeId then
        if S.phase ~= "idle" and S.phase ~= "selected" then resetPhase() end
        if settings.debug and S.noteSig ~= sig then
            S.noteSig = sig
            log("menu not focused (menu " .. tostring(hub.id) .. ", focused " .. tostring(activeId) .. ")")
        end
        return
    end

    if S.phase == "idle" then
        if sig == S.handledSig then return end
        if settings.conversationsOnly and not isInConversation(player) then
            if settings.debug and S.noteSig ~= sig then
                S.noteSig = sig
                log("not in a conversation yet, waiting (turn off 'Only inside conversations' if this is wrong)")
            end
            return
        end

        prunePicked()
        local index, reason = Logic.decide(choices, {
            mode = settings.mode,
            storyRule = settings.storyRule,
            pickedBefore = function(c) return S.picked[pickedKey(hub, c)] ~= nil end,
        })

        if settings.debug then
            log("menu '" .. (hub.title or "") .. "', selected " .. tostring(sel))
            for _, c in ipairs(choices) do
                log(string.format("  %d. %s [%s]", c.index, c.text, flagString(c)))
            end
        end

        if not index then
            log("left to you (" .. reason .. ")")
            S.handledSig = sig
            return
        end

        local choice = choices[index]
        S.phase = "waiting"
        S.sig = sig
        S.target = index - 1
        S.targetText = choice.text
        S.targetKey = pickedKey(hub, choice)
        S.reason = reason
        S.startSel = sel
        S.phaseStart = S.clock
        S.steps = 0
        S.maxSteps = #choices * 2 + 2
        S.lastStepAt = -1
        S.lastStepSel = nil
        log("will pick '" .. choice.text .. "' (" .. reason .. ")")
        return
    end

    if S.phase == "waiting" then
        -- the highlight can settle right after a menu opens; that is not you
        if S.clock - S.phaseStart < 0.25 then
            S.startSel = sel
            return
        end
        if sel ~= S.startSel then
            cancel("you scrolled")
            return
        end
        if S.clock - S.phaseStart >= settings.delay then
            S.phase = "navigating"
            S.phaseStart = S.clock
        end
        return
    end

    if S.phase == "navigating" then
        if sel == S.target then
            sendCommand("SELECT")
            S.picked[S.targetKey] = S.clock
            S.handledSig = S.sig
            S.phase = "selected"
            S.phaseStart = S.clock
            log("selected '" .. S.targetText .. "'")
            return
        end

        -- You scrolled away from the line the mod is heading for: hands off.
        if S.lastStepSel ~= nil and sel ~= S.lastStepSel then
            local before = math.abs(S.lastStepSel - S.target)
            local now = math.abs(sel - S.target)
            if now > before then
                cancel("you took over")
                return
            end
        end

        local moved = S.lastStepSel ~= nil and sel ~= S.lastStepSel
        if S.lastStepAt < 0 or moved or (S.clock - S.lastStepAt) > STEP_TIMEOUT then
            if S.steps >= S.maxSteps then
                cancel("could not reach the line (is the helper running?)")
                return
            end
            sendCommand(sel < S.target and "DOWN" or "UP")
            S.steps = S.steps + 1
            S.lastStepAt = S.clock
            S.lastStepSel = sel
        end
        return
    end

    if S.phase == "selected" then
        if S.clock - S.phaseStart > SELECTED_TIMEOUT then
            -- nothing changed; leave this menu to you rather than pressing again
            resetPhase()
        end
    end
end

------------------------------------------------------------------------------
-- drawing
------------------------------------------------------------------------------

local function drawNotice(text)
    local w, _ = GetDisplayResolution()
    ImGui.SetNextWindowPos(w * 0.5, 40, ImGuiCond.Always, 0.5, 0.0)
    ImGui.SetNextWindowBgAlpha(0.55)
    local flags = bit32.bor(
        ImGuiWindowFlags.NoDecoration,
        ImGuiWindowFlags.NoInputs,
        ImGuiWindowFlags.AlwaysAutoResize,
        ImGuiWindowFlags.NoSavedSettings,
        ImGuiWindowFlags.NoFocusOnAppearing,
        ImGuiWindowFlags.NoNav
    )
    if ImGui.Begin("##AutoDialogPickerNotice", flags) then
        ImGui.Text(text)
    end
    ImGui.End()
end

local function drawSettings()
    ImGui.SetNextWindowSize(430, 0, ImGuiCond.FirstUseEver)
    if ImGui.Begin(MOD_NAME .. " " .. VERSION) then
        local changed = false
        local v, c

        v, c = ImGui.Checkbox("Enabled", settings.enabled)
        if c then settings.enabled = v; changed = true end

        local idx
        idx, c = ImGui.Combo("Mode", settings.mode - 1, MODE_NAMES, #MODE_NAMES)
        if c then settings.mode = idx + 1; changed = true end

        idx, c = ImGui.Combo("Several story lines", settings.storyRule - 1, STORY_NAMES, #STORY_NAMES)
        if c then settings.storyRule = idx + 1; changed = true end

        v, c = ImGui.SliderFloat("Delay (seconds)", settings.delay, 0.2, 5.0, "%.1f")
        if c then settings.delay = v; changed = true end

        v, c = ImGui.Checkbox("Only inside conversations", settings.conversationsOnly)
        if c then settings.conversationsOnly = v; changed = true end

        v, c = ImGui.Checkbox("Show on-screen notice", settings.showNotice)
        if c then settings.showNotice = v; changed = true end

        v, c = ImGui.Checkbox("Debug log (CET console)", settings.debug)
        if c then settings.debug = v; changed = true end

        if changed then saveSettings() end

        ImGui.Separator()
        if S.broken then
            ImGui.TextColored(1, 0.4, 0.4, 1, "Stopped: " .. S.broken)
        end
        if S.helperAlive then
            ImGui.TextColored(0.4, 1, 0.5, 1, "Helper: running")
        else
            ImGui.TextColored(1, 0.7, 0.3, 1, "Helper: not running")
            ImGui.TextWrapped("Double-click AutoDialogPicker-Helper.ahk in this mod's folder (needs AutoHotkey v2).")
        end
        ImGui.Separator()
        ImGui.TextWrapped("Scroll during the delay to pick a line yourself. Hotkeys can be set under Bindings: toggle on/off, switch mode, choose this one myself.")
    end
    ImGui.End()
end

------------------------------------------------------------------------------
-- CET events
------------------------------------------------------------------------------

registerForEvent("onInit", function()
    loadSettings()
    S.seq = os.time() * 10

    local ok, err = pcall(function()
        for _, name in ipairs({ "QuestImportant", "AlreadyRead", "Inactive", "CheckSuccess", "CheckFailed",
                                "TimedDialog", "Blueline", "Pay", "Illegal", "Glowline" }) do
            CT[name] = Enum.new("gameinteractionsChoiceType", name)
        end
        PART_ICON = EnumInt(Enum.new("gamedataChoiceCaptionPartType", "Icon"))
        PART_TAG = EnumInt(Enum.new("gamedataChoiceCaptionPartType", "Tag"))
    end)
    if not ok then
        S.broken = "could not read game enums: " .. tostring(err)
        spdlog.error(S.broken)
        return
    end

    sendCommand("NONE")
    S.ready = true
    log(MOD_NAME .. " " .. VERSION .. " loaded")
end)

registerForEvent("onOverlayOpen", function() S.overlayOpen = true end)
registerForEvent("onOverlayClose", function() S.overlayOpen = false end)

registerForEvent("onUpdate", function(delta)
    S.clock = S.clock + delta
    if not S.ready or S.broken then return end
    checkHelper()
    if not settings.enabled then
        if S.phase ~= "idle" then resetPhase() end
        return
    end
    S.acc = S.acc + delta
    if S.acc < TICK then return end
    S.acc = 0
    local ok, err = pcall(tick)
    if not ok then
        S.broken = tostring(err)
        spdlog.error("stopped after an error: " .. S.broken)
        resetPhase()
    end
end)

registerForEvent("onDraw", function()
    if S.overlayOpen then
        drawSettings()
        return
    end
    if not settings.showNotice then return end
    if (S.phase == "waiting" or S.phase == "navigating") and S.targetText then
        local text = "Auto: " .. S.targetText
        if not S.helperAlive then
            text = text .. "   (helper not running)"
        elseif S.phase == "waiting" then
            text = text .. "   (scroll to choose yourself)"
        end
        drawNotice(text)
    elseif S.toastText and S.clock < S.toastUntil then
        drawNotice(S.toastText)
    end
end)

registerHotkey("adp_toggle", "Turn auto-pick on/off", function()
    settings.enabled = not settings.enabled
    saveSettings()
    resetPhase()
    toast(MOD_NAME .. ": " .. (settings.enabled and "ON" or "OFF"))
end)

registerHotkey("adp_mode", "Switch mode (include/skip optional)", function()
    settings.mode = settings.mode == Logic.MODE_INCLUDE_OPTIONAL and Logic.MODE_SKIP_OPTIONAL
        or Logic.MODE_INCLUDE_OPTIONAL
    saveSettings()
    S.handledSig = nil
    resetPhase()
    toast(MOD_NAME .. ": " .. MODE_NAMES[settings.mode])
end)

registerHotkey("adp_takeover", "Choose this one myself", function()
    if S.phase == "waiting" or S.phase == "navigating" then
        cancel("hotkey")
        toast("Your choice")
    end
end)

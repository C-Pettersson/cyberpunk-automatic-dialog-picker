-- End-to-end simulation: runs init.lua against a fake CET + fake game, and
-- plays the role of the AutoHotkey helper by reading cmd.txt.
-- usage: luajit sim.lua <mod dir>   (run with the current directory = a temp copy of the mod)

local MOD = arg[1] or "."
package.path = MOD .. "/?.lua;" .. package.path

------------------------------------------------------------------ fake CET
local events, hotkeys = {}, {}
function registerForEvent(name, fn) events[name] = fn end
function registerHotkey(id, label, fn) hotkeys[id] = fn end
spdlog = {
    info = function(m) LOG[#LOG + 1] = m end,
    error = function(m) LOG[#LOG + 1] = "ERROR " .. m end,
}
LOG = {}
bit32 = require("bit")

-- tiny flat JSON (enough for settings.json)
json = {
    encode = function(t)
        local parts = {}
        for k, v in pairs(t) do parts[#parts + 1] = string.format("%q:%s", k, tostring(v)) end
        return "{" .. table.concat(parts, ",") .. "}"
    end,
    decode = function(s)
        local t = {}
        for k, v in s:gmatch('"([%w_]+)":([^,}]+)') do
            if v == "true" then t[k] = true elseif v == "false" then t[k] = false else t[k] = tonumber(v) end
        end
        return t
    end,
}

local ENUMS = {
    gameinteractionsChoiceType = { "QuestImportant", "AlreadyRead", "Inactive", "CheckSuccess", "CheckFailed",
        "InnerDialog", "PossessedDialog", "TimedDialog", "Blueline", "Pay", "Selected", "Illegal", "Glowline" },
    gamedataChoiceCaptionPartType = { "Blueline", "Icon", "QuickhackCost", "Tag", "Text", "Count", "Invalid" },
}
Enum = { new = function(typ, name)
    for i, n in ipairs(ENUMS[typ]) do if n == name then return { typ = typ, name = name, value = i - 1 } end end
    error("no enum " .. typ .. "." .. name)
end }
function EnumInt(e) return e.value end
ChoiceTypeWrapper = { IsType = function(t, e) return t[e.name] == true end }

ImGuiCond = { Always = 1, FirstUseEver = 4 }
ImGuiWindowFlags = { NoDecoration = 1, NoInputs = 2, AlwaysAutoResize = 4, NoSavedSettings = 8, NoFocusOnAppearing = 16, NoNav = 32 }
ImGui = setmetatable({}, { __index = function(_, k)
    if k == "Begin" then return function() return true end end
    if k == "Checkbox" then return function(_, v) return v, false end end
    if k == "Combo" then return function(_, v) return v, false end end
    if k == "SliderFloat" then return function(_, v) return v, false end end
    return function() end
end })
NOTICES = {}
local realText = nil
ImGui.Text = function(t) NOTICES[#NOTICES + 1] = t end
function GetDisplayResolution() return 1920, 1080 end

------------------------------------------------------------------ fake game
G = { hubs = {}, active = -1, sel = 0, tier = 3, inDialogue = true, inMenu = false, picks = {} }
local DEFS = {
    UIInteractions = { DialogChoiceHubs = "hubs", ActiveChoiceHubID = "active", SelectedIndex = "sel" },
    UI_System = { IsInMenu = "menu" },
}
function GetAllBlackboardDefs() return DEFS end
local bb = {
    GetVariant = function(_, k) return { choiceHubs = G.hubs } end,
    GetInt = function(_, k) if k == "active" then return G.active end return G.sel end,
    GetBool = function(_, k) return G.inMenu end,
}
local player = { GetEntityID = function() return 1 end }
Game = {
    GetBlackboardSystem = function() return { Get = function() return bb end } end,
    GetPlayer = function() return player end,
    GetSceneSystem = function() return { GetScriptInterface = function()
        return { IsEntityInDialogue = function() return G.inDialogue end } end } end,
}
PlayerPuppet = { GetSceneTier = function() return G.tier end }
function FromVariant(v) return v end

local function mkChoice(spec)
    local t = {}
    for _, f in ipairs({ "QuestImportant", "AlreadyRead", "Inactive", "CheckSuccess", "CheckFailed",
                         "TimedDialog", "Blueline", "Pay", "Illegal", "Glowline" }) do
        t[f] = spec[f] or false
    end
    local parts = {}
    if spec.icon then parts[#parts + 1] = { GetType = function() return Enum.new("gamedataChoiceCaptionPartType", "Icon") end } end
    return { localizedName = spec.text, type = t, captionParts = { parts = parts }, inputActionName = { value = spec.input or "" } }
end

-- a conversation: list of {text, QuestImportant...}; read lines get AlreadyRead.
local Conv = {}
function Conv.new(id, title, lines, onPick)
    return { id = id, title = title, lines = lines, onPick = onPick }
end
function Conv.show(c)
    local choices = {}
    for i, l in ipairs(c.lines) do choices[i] = mkChoice(l) end
    G.hubs = { { id = c.id, title = c.title, choices = choices } }
    G.active = c.id
    G.sel = 0
end
function Conv.hide() G.hubs = {}; G.active = -1 end

------------------------------------------------------------------ fake helper
local lastSeq = nil
local function helper()
    local f = io.open("cmd.txt", "r")
    if not f then return end
    local s = f:read("*a"); f:close()
    local seq, action, stamp = s:match("^(%d+)|(%u+)|(%d+)$")
    if not seq or seq == lastSeq then return end
    lastSeq = seq
    if action == "UP" then G.sel = math.max(0, G.sel - 1)
    elseif action == "DOWN" then
        local n = (#G.hubs > 0) and #G.hubs[1].choices or 1
        G.sel = math.min(n - 1, G.sel + 1)
    elseif action == "SELECT" and #G.hubs > 0 then
        local line = G.hubs[1].choices[G.sel + 1]
        G.picks[#G.picks + 1] = line.localizedName
        if G.onSelect then G.onSelect(G.sel + 1) end
    end
end

local function writeAlive()
    local f = io.open("helper_alive.txt", "w"); f:write(tostring(os.time())); f:close()
end

------------------------------------------------------------------ driver
local function step(seconds, withHelper)
    local frames = math.floor(seconds / 0.016 + 0.5)
    for _ = 1, frames do
        events.onUpdate(0.016)
        NOTICES = {}
        events.onDraw()
        if withHelper ~= false then helper() end
    end
end

dofile(MOD .. "/init.lua")
writeAlive()
events.onInit()
lastSeq = io.open("cmd.txt"):read("*a"):match("^(%d+)")

local failures, count = 0, 0
local function check(name, got, want)
    count = count + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
    end
end
local function picks() return table.concat(G.picks, " > ") end

-- a conversation that hides the menu while a line plays, then shows it again
local function runConversation(lines)
    local conv = Conv.new(7, "Rogue", lines)
    G.picks = {}
    G.onSelect = function(i)
        local l = conv.lines[i]
        if l.QuestImportant then
            conv.done = true
        else
            l.AlreadyRead = true
        end
        Conv.hide()
    end
    Conv.show(conv)
    for _ = 1, 10 do
        step(3)
        if conv.done or #G.hubs > 0 then
            if conv.done then break end
        else
            step(0.5)          -- the line plays
            Conv.show(conv)    -- menu comes back
        end
    end
    Conv.hide()
    step(0.5)
    return conv
end

local function lines()
    return {
        { text = "Who are you?" },
        { text = "Nice bar." },
        { text = "[Trade]", icon = true },
        { text = "Let's talk business.", QuestImportant = true },
    }
end

-- 1) include optional: hears both optional lines, then the story line
runConversation(lines())
check("include order", picks(), "Who are you? > Nice bar. > Let's talk business.")

-- 2) skip optional: story line straight away
hotkeys.adp_mode()
runConversation(lines())
check("skip order", picks(), "Let's talk business.")

-- 3) several story lines: left to you
G.picks = {}
Conv.show(Conv.new(8, "Panam", { { text = "Help her", QuestImportant = true }, { text = "Leave", QuestImportant = true } }))
step(3)
check("several story -> nothing picked", picks(), "")
Conv.hide(); step(0.3)

-- 4) cancel by scrolling during the delay
G.picks = {}
Conv.show(Conv.new(9, "Judy", { { text = "Hi" }, { text = "Let's go", QuestImportant = true } }))
step(0.4, false)
G.sel = 1                     -- you scroll
step(3)
check("scroll cancels", picks(), "")
Conv.hide(); step(0.3)

-- 5) takeover hotkey
G.picks = {}
Conv.show(Conv.new(10, "Kerry", { { text = "Hi" }, { text = "Play", QuestImportant = true } }))
step(0.4)
hotkeys.adp_takeover()
step(3)
check("hotkey cancels", picks(), "")
Conv.hide(); step(0.3)

-- 6) not in a conversation: a vendor prompt in the street is left alone
G.picks = {}; G.tier = 0; G.inDialogue = false
Conv.show(Conv.new(11, "Vendor", { { text = "Talk", QuestImportant = true } }))
step(3)
check("street prompt ignored", picks(), "")
Conv.hide(); step(0.3)
G.tier = 3; G.inDialogue = true

-- 7) menu shown but not focused
G.picks = {}
Conv.show(Conv.new(12, "Takemura", { { text = "Fine", QuestImportant = true } }))
G.active = -1
step(3)
check("unfocused menu ignored", picks(), "")
G.active = 12
step(3)
check("focused later -> picked", picks(), "Fine")
Conv.hide(); step(0.3)

-- 8) helper not running: nothing is pressed and the mod gives up quietly
G.picks = {}
Conv.show(Conv.new(13, "Viktor", { { text = "Hey" }, { text = "Ok", QuestImportant = true } }))
-- skip mode is active: target is line 2, needs a scroll the helper never sends
step(6, false)
check("no helper -> nothing picked", picks(), "")
check("no helper -> stopped scrolling", G.sel, 0)
Conv.hide(); step(0.3)

-- 9) turning the mod off
hotkeys.adp_toggle()
G.picks = {}
Conv.show(Conv.new(14, "Misty", { { text = "Bye", QuestImportant = true } }))
step(3)
check("off -> nothing", picks(), "")
Conv.hide(); step(0.3)
hotkeys.adp_toggle()

-- 10) a game menu (map, inventory) pauses the mod
G.picks = {}; G.inMenu = true
Conv.show(Conv.new(15, "Jackie", { { text = "Let's go", QuestImportant = true } }))
step(3)
check("in menu -> nothing", picks(), "")
G.inMenu = false
step(3)
check("menu closed -> picked", picks(), "Let's go")
Conv.hide(); step(0.3)

-- 11) the notice is shown while waiting
Conv.show(Conv.new(16, "Claire", { { text = "Race", QuestImportant = true } }))
step(0.3, false)
check("notice text", NOTICES[1], "Auto: Race   (scroll to choose yourself)")
Conv.hide(); step(0.3)

local errors = 0
for _, l in ipairs(LOG) do if l:find("^ERROR") then errors = errors + 1; print(l) end end
check("no errors logged", errors, 0)

print(string.format("%d checks, %d failures", count, failures))
if failures > 0 then
    print("--- log ---")
    for _, l in ipairs(LOG) do print(l) end
end
os.exit(failures == 0 and 0 or 1)

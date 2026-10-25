-- Auto Dialog Picker - decision rules
--
-- Pure Lua, no game calls, so the rules can be tested outside the game.
-- A choice is a plain table:
--   index            1-based position in the hub (top line = 1)
--   text             the line as shown on screen
--   questImportant   yellow line (moves the story on)
--   alreadyRead      line you have picked before (dimmed)
--   inactive         greyed out, cannot be picked
--   checkFailed      failed attribute check, cannot be picked
--   checkSuccess     passed attribute check ([Body 6] etc.)
--   pay              costs eddies
--   illegal          marked as illegal
--   blueline         lifepath / special blue line
--   glowline         highlighted special line
--   timed            timed choice (a timer runs while the menu is up)
--   hasIcon          has an action icon (trade, sit, take...)
--   hasTag           bracketed action such as [Smile] or [Draw weapon]
--   dedicatedInput   uses a different button than the normal select key
--   lifepath         lifepath record of a lifepath line ("LifePaths.Corporate"), or nil
--   skillCheck       build record of a skill-check line ("PlayerBuilds.Netrunner"), or nil

local Logic = {}

Logic.MODE_INCLUDE_OPTIONAL = 1
Logic.MODE_SKIP_OPTIONAL = 2
Logic.MODE_CUSTOM = 3

Logic.STORY_LET_ME_CHOOSE = 1
Logic.STORY_PICK_FIRST = 2

-- Answers to the custom rules: each is its position in that rule's options.
Logic.OPTIONAL_HEAR = 1
Logic.OPTIONAL_SKIP = 2
Logic.ONE_PICK = 1
Logic.ONE_ASK = 2
Logic.ACTION_WHEN_ALONE = 1
Logic.ACTION_PICK = 2
Logic.ACTION_ASK = 3
Logic.SPECIAL_SAME = 1
Logic.SPECIAL_PICK = 2
Logic.SPECIAL_ASK = 3
Logic.TIMED_ASK = 1
Logic.TIMED_NORMAL = 2

-- The custom rules, in the order the settings window shows them.
Logic.RULES = {
    { key = "optional", label = "Unread optional line",
      options = { "Hear it", "Skip it" } },
    { key = "optionalLifepath", label = "Optional lifepath line (blue, not yellow)",
      options = { "Hear it", "Skip it" } },
    { key = "oneSpoken", label = "One story line",
      options = { "Pick it", "Let me choose" } },
    { key = "oneAction", label = "One story line that is an action ([Take chip], [Open])",
      options = { "Pick it when nothing else is left", "Pick it right away", "Let me choose" } },
    { key = "storyRule", label = "Several story lines",
      options = { "Let me choose", "Pick the first plain story line" } },
    { key = "severalLifepath", label = "Several story lines, one is a lifepath line",
      options = { "Same as several story lines", "Pick the lifepath line", "Let me choose" } },
    { key = "severalSkill", label = "Several story lines, one is a passed skill check",
      options = { "Same as several story lines", "Pick the skill check", "Let me choose" } },
    { key = "timed", label = "Timed choice",
      options = { "Let me choose", "Handle like any other menu" } },
}

-- The rules behind the two simple modes.
function Logic.preset(mode, storyRule)
    return {
        optional = mode == Logic.MODE_SKIP_OPTIONAL and Logic.OPTIONAL_SKIP or Logic.OPTIONAL_HEAR,
        optionalLifepath = Logic.OPTIONAL_SKIP,
        oneSpoken = Logic.ONE_PICK,
        oneAction = Logic.ACTION_WHEN_ALONE,
        storyRule = storyRule or Logic.STORY_LET_ME_CHOOSE,
        severalLifepath = Logic.SPECIAL_SAME,
        severalSkill = Logic.SPECIAL_SAME,
        timed = Logic.TIMED_ASK,
    }
end

local function canPress(c)
    return not (c.inactive or c.checkFailed or c.dedicatedInput)
end

-- A plain story line: yellow, no lifepath/skill/money flavour.
local function isPlainStory(c)
    return c.questImportant
        and not (c.blueline or c.glowline or c.checkSuccess or c.pay or c.illegal)
end

-- Something V does rather than says: [Sit], [Draw weapon], [Shoot Royce] ...,
-- or a line with an icon that may open a shop.
local function isAction(c)
    return c.hasIcon or c.hasTag
end

local function isSkillCheck(c)
    return c.skillCheck ~= nil or c.checkSuccess
end

-- An optional line worth hearing: not yellow, not read yet, not an action,
-- and of a kind the rules say to hear.
local function isUnreadOptional(c, pickedBefore, rules)
    if c.questImportant or c.alreadyRead then return false end
    if c.hasIcon or c.hasTag then return false end
    if pickedBefore and pickedBefore(c) then return false end
    if c.lifepath then return rules.optionalLifepath == Logic.OPTIONAL_HEAR end
    if c.blueline or c.glowline or c.checkSuccess then return false end
    return rules.optional == Logic.OPTIONAL_HEAR
end

-- Several story lines, one of them special (lifepath or skill check).
-- Returns (index, reason) when the rule decides, nothing when it is "same as
-- several story lines".
local function decideSpecial(story, rule, matches, what)
    if rule == Logic.SPECIAL_SAME then return end
    for _, c in ipairs(story) do
        if matches(c) and not isAction(c) then
            if rule == Logic.SPECIAL_PICK then return c.index, what end
            return nil, "several story lines, one is a " .. what
        end
    end
end

-- Returns (index, reason). index is nil when the menu should be left to the player.
-- opts.mode       MODE_INCLUDE_OPTIONAL, MODE_SKIP_OPTIONAL or MODE_CUSTOM
-- opts.storyRule  STORY_LET_ME_CHOOSE or STORY_PICK_FIRST (simple modes)
-- opts.rules      a table like Logic.preset() returns (custom mode)
-- opts.pickedBefore(choice) -> true if the mod already auto-picked this line recently
function Logic.decide(choices, opts)
    opts = opts or {}
    local mode = opts.mode or Logic.MODE_INCLUDE_OPTIONAL
    local rules = (mode == Logic.MODE_CUSTOM and opts.rules) or Logic.preset(mode, opts.storyRule)

    if not choices or #choices == 0 then
        return nil, "no choices"
    end

    -- Money and illegal actions are real decisions: always leave them to you.
    -- So are timed choices, unless you say otherwise: answering late, or not
    -- at all, is a choice too.
    for _, c in ipairs(choices) do
        if canPress(c) and (c.pay or c.illegal) then
            return nil, "a line costs money or is illegal"
        end
        if canPress(c) and c.timed and rules.timed ~= Logic.TIMED_NORMAL then
            return nil, "timed choice"
        end
    end

    local optional, story = {}, {}
    local unheard = 0   -- lines you could press that you have not picked before
    for _, c in ipairs(choices) do
        if canPress(c) then
            if c.questImportant then
                story[#story + 1] = c
            elseif isUnreadOptional(c, opts.pickedBefore, rules) then
                optional[#optional + 1] = c
            end
            if c.questImportant or not (c.alreadyRead or (opts.pickedBefore and opts.pickedBefore(c))) then
                unheard = unheard + 1
            end
        end
    end

    if #optional > 0 then
        return optional[1].index, optional[1].lifepath and "optional lifepath line" or "optional line"
    end

    if #story == 1 then
        local c = story[1]
        if isAction(c) then
            -- An action ([Draw weapon], the mirror's [Stop looking]) is by
            -- default only taken when nothing else is on offer; next to other
            -- lines it may be the choice that matters.
            if rules.oneAction == Logic.ACTION_ASK then
                return nil, "story line is an action"
            end
            if rules.oneAction == Logic.ACTION_WHEN_ALONE and unheard > 1 then
                return nil, "story line is an action and there are other lines"
            end
            return c.index, "only story line"
        end
        if rules.oneSpoken == Logic.ONE_ASK then
            return nil, "one story line, set to let you choose"
        end
        return c.index, "only story line"
    end

    if #story > 1 then
        -- A lifepath line outranks a skill check.
        local index, reason = decideSpecial(story, rules.severalLifepath,
            function(c) return c.lifepath ~= nil end, "lifepath line")
        if index or reason then return index, reason end
        index, reason = decideSpecial(story, rules.severalSkill, isSkillCheck, "skill check")
        if index or reason then return index, reason end

        if rules.storyRule == Logic.STORY_PICK_FIRST then
            -- Only spoken lines: an action may open a shop (the bartender's
            -- "Whatcha got?") or be the decision itself ([Shoot Royce] ...).
            for _, c in ipairs(story) do
                if isPlainStory(c) and not isAction(c) then
                    return c.index, "first plain story line"
                end
            end
            return nil, "several story lines, none plain"
        end
        return nil, "several story lines"
    end

    return nil, "nothing to pick"
end

return Logic

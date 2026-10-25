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

local Logic = {}

Logic.MODE_INCLUDE_OPTIONAL = 1
Logic.MODE_SKIP_OPTIONAL = 2

Logic.STORY_LET_ME_CHOOSE = 1
Logic.STORY_PICK_FIRST = 2

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

-- An optional line worth hearing: not yellow, not read yet, and not an action.
local function isUnreadOptional(c, pickedBefore)
    if c.questImportant or c.alreadyRead then return false end
    if c.blueline or c.glowline or c.checkSuccess or c.hasIcon or c.hasTag then return false end
    if pickedBefore and pickedBefore(c) then return false end
    return true
end

-- Returns (index, reason). index is nil when the menu should be left to the player.
-- opts.mode       MODE_INCLUDE_OPTIONAL or MODE_SKIP_OPTIONAL
-- opts.storyRule  STORY_LET_ME_CHOOSE or STORY_PICK_FIRST
-- opts.pickedBefore(choice) -> true if the mod already auto-picked this line recently
function Logic.decide(choices, opts)
    opts = opts or {}
    local mode = opts.mode or Logic.MODE_INCLUDE_OPTIONAL
    local storyRule = opts.storyRule or Logic.STORY_LET_ME_CHOOSE

    if not choices or #choices == 0 then
        return nil, "no choices"
    end

    -- Money and illegal actions are real decisions: always leave them to you.
    -- So are timed choices: answering late, or not at all, is a choice too.
    for _, c in ipairs(choices) do
        if canPress(c) and (c.pay or c.illegal) then
            return nil, "a line costs money or is illegal"
        end
        if canPress(c) and c.timed then
            return nil, "timed choice"
        end
    end

    local optional, story = {}, {}
    local unheard = 0   -- lines you could press that you have not picked before
    for _, c in ipairs(choices) do
        if canPress(c) then
            if c.questImportant then
                story[#story + 1] = c
            elseif isUnreadOptional(c, opts.pickedBefore) then
                optional[#optional + 1] = c
            end
            if c.questImportant or not (c.alreadyRead or (opts.pickedBefore and opts.pickedBefore(c))) then
                unheard = unheard + 1
            end
        end
    end

    if mode == Logic.MODE_INCLUDE_OPTIONAL and #optional > 0 then
        return optional[1].index, "optional line"
    end

    if #story == 1 then
        -- An action ([Draw weapon], the mirror's [Stop looking]) is only taken
        -- when nothing else is on offer; next to other lines it may be the
        -- choice that matters.
        if isAction(story[1]) and unheard > 1 then
            return nil, "story line is an action and there are other lines"
        end
        return story[1].index, "only story line"
    end

    if #story > 1 then
        if storyRule == Logic.STORY_PICK_FIRST then
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

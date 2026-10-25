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
--   hasIcon          has an action icon (trade, sit, take...)
--   hasTag           bracketed action such as [Smile] or [Stop looking]
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

-- An action with no spoken words, such as [Stop looking] or [Sit].
local function isActionOnly(c)
    return (c.text or ""):match("^%s*%[[^%]]*%]%s*$") ~= nil
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
    for _, c in ipairs(choices) do
        if canPress(c) and (c.pay or c.illegal) then
            return nil, "a line costs money or is illegal"
        end
    end

    local optional, story = {}, {}
    local otherActions = false
    for _, c in ipairs(choices) do
        if canPress(c) then
            if c.questImportant then
                story[#story + 1] = c
            elseif isUnreadOptional(c, opts.pickedBefore) then
                optional[#optional + 1] = c
            elseif c.hasIcon or c.hasTag then
                otherActions = true
            end
        end
    end

    if mode == Logic.MODE_INCLUDE_OPTIONAL and #optional > 0 then
        return optional[1].index, "optional line"
    end

    if #story == 1 then
        -- The mirror: [Stop looking] next to [Smile], [Pout]... is a way out of
        -- something you are playing with, not the story moving on.
        if isActionOnly(story[1]) and otherActions then
            return nil, "story line is an action next to other actions"
        end
        return story[1].index, "only story line"
    end

    if #story > 1 then
        if storyRule == Logic.STORY_PICK_FIRST then
            -- Prefer a spoken line over one with an icon, which may open a
            -- shop (the bartender's "Whatcha got?") or move V ([Stand]).
            local withIcon
            for _, c in ipairs(story) do
                if isPlainStory(c) then
                    if not c.hasIcon then
                        return c.index, "first plain story line"
                    end
                    withIcon = withIcon or c
                end
            end
            if withIcon then
                return withIcon.index, "first plain story line"
            end
            return nil, "several story lines, none plain"
        end
        return nil, "several story lines"
    end

    return nil, "nothing to pick"
end

return Logic

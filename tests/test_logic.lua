-- Unit tests for logic.lua (run with LuaJIT from the mod folder on package.path)
local Logic = require("logic")

local failures, count = 0, 0
local function check(name, got, want)
    count = count + 1
    if got ~= want then
        failures = failures + 1
        print(string.format("FAIL %s: got %s, want %s", name, tostring(got), tostring(want)))
    end
end

local function hub(list)
    local out = {}
    for i, c in ipairs(list) do
        c.index = i
        c.text = c.text or ("line " .. i)
        out[i] = c
    end
    return out
end

local INC = { mode = Logic.MODE_INCLUDE_OPTIONAL }
local SKIP = { mode = Logic.MODE_SKIP_OPTIONAL }
local SKIP_FIRST = { mode = Logic.MODE_SKIP_OPTIONAL, storyRule = Logic.STORY_PICK_FIRST }

-- typical conversation: two unread optional lines and one story line
local h = hub({ { text = "Who are you?" }, { text = "What is this place?" }, { questImportant = true } })
check("include picks first unread optional", Logic.decide(h, INC), 1)
check("skip goes to the story line", Logic.decide(h, SKIP), 3)

-- optional lines read: include falls through to the story line
h = hub({ { alreadyRead = true }, { alreadyRead = true }, { questImportant = true } })
check("include all read -> story", Logic.decide(h, INC), 3)

-- second optional unread
h = hub({ { alreadyRead = true }, {}, { questImportant = true } })
check("include picks the unread one", Logic.decide(h, INC), 2)

-- pickedBefore guards against lines the game never marks as read
local picked = { ["line 1"] = true }
local opts = { mode = Logic.MODE_INCLUDE_OPTIONAL, pickedBefore = function(c) return picked[c.text] end }
h = hub({ {}, { questImportant = true } })
check("include skips line already auto-picked", Logic.decide(h, opts), 2)

-- two story lines: menu by default, first plain one when asked
h = hub({ { questImportant = true, blueline = true, text = "[Corpo] ..." }, { questImportant = true }, { questImportant = true } })
check("several story -> menu", Logic.decide(h, SKIP), nil)
check("several story -> first plain", Logic.decide(h, SKIP_FIRST), 2)
check("several story, include, no optional -> menu", Logic.decide(h, INC), nil)

-- several story + optional, include mode still hears optional first (like TW3)
h = hub({ {}, { questImportant = true }, { questImportant = true } })
check("include optional before a decision", Logic.decide(h, INC), 1)

-- one plain line among lifepath/check story lines: pick first takes the plain one
h = hub({ { questImportant = true, checkSuccess = true }, { questImportant = true, blueline = true }, { questImportant = true } })
check("pick first skips to the only plain story", Logic.decide(h, SKIP_FIRST), 3)

-- only checks/lifepath among story lines: pick first leaves the menu to the player
h = hub({ { questImportant = true, checkSuccess = true }, { questImportant = true, blueline = true } })
check("pick first with no plain story -> menu", Logic.decide(h, SKIP_FIRST), nil)
check("pick first with no plain story -> reason", select(2, Logic.decide(h, SKIP_FIRST)), "several story lines, none plain")

-- money and illegal lines always leave the menu to the player
h = hub({ { questImportant = true, pay = true }, {} })
check("pay -> menu", Logic.decide(h, INC), nil)
h = hub({ { questImportant = true }, { illegal = true } })
check("illegal -> menu", Logic.decide(h, SKIP), nil)
-- ...unless that line cannot be picked anyway
h = hub({ { questImportant = true }, { pay = true, inactive = true } })
check("inactive pay ignored", Logic.decide(h, SKIP), 1)

-- unusable lines are never targets
h = hub({ { questImportant = true, inactive = true }, { questImportant = true, checkFailed = true }, { questImportant = true } })
check("skips inactive and failed checks", Logic.decide(h, SKIP), 3)
h = hub({ { questImportant = true, dedicatedInput = true } })
check("dedicated input -> menu", Logic.decide(h, SKIP), nil)

-- action lines (icons), lifepath lines, glow lines and checks are not "optional chatter"
h = hub({ { hasIcon = true, text = "[Trade]" }, { blueline = true }, { glowline = true }, { checkSuccess = true } })
check("no chatter -> menu (include)", Logic.decide(h, INC), nil)
check("no chatter -> menu (skip)", Logic.decide(h, SKIP), nil)

-- yellow line with an icon (e.g. [Sit]) is fine when it is the only way on
h = hub({ { questImportant = true, hasIcon = true } })
check("single story with icon", Logic.decide(h, SKIP), 1)

-- read yellow line stays a story line
h = hub({ { questImportant = true, alreadyRead = true } })
check("read story line still taken", Logic.decide(h, INC), 1)

-- only optional read lines and no story -> menu
h = hub({ { alreadyRead = true }, { alreadyRead = true } })
check("only read optional -> menu", Logic.decide(h, INC), nil)

-- skip mode never takes optional chatter
h = hub({ {}, {} })
check("skip ignores optional", Logic.decide(h, SKIP), nil)
check("include takes optional", Logic.decide(h, INC), 1)

-- empty hub
check("empty", Logic.decide({}, INC), nil)

print(string.format("%d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)

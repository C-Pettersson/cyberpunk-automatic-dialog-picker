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

-- pick first prefers a line without an icon (the bartender's shop line)
h = hub({ { questImportant = true, hasIcon = true, text = "Whatcha got?" }, { questImportant = true, text = "I'm good, thanks." },
          { questImportant = true, blueline = true } })
check("pick first skips shop icon", Logic.decide(h, SKIP_FIRST), 2)
-- ...and never takes an action, even when every story line is one
h = hub({ { questImportant = true, hasIcon = true, hasTag = true, text = "[Stand] Something I gotta take care of first." },
          { questImportant = true, hasIcon = true, hasTag = true, text = "[Stand] Let's go." } })
check("pick first, all actions -> menu", Logic.decide(h, SKIP_FIRST), nil)
h = hub({ { questImportant = true, hasTag = true, text = "[Shoot Royce] I've had enough." }, { questImportant = true, text = "Easy now." } })
check("pick first skips [Shoot Royce]", Logic.decide(h, SKIP_FIRST), 2)

-- an action story line next to anything else you could press is left to you
h = hub({ { questImportant = true, hasTag = true, text = "[Draw weapon]" }, { text = "Relax, Royce." } })
check("[Draw weapon] beside a line -> menu (skip)", Logic.decide(h, SKIP), nil)
h = hub({ { questImportant = true, hasTag = true, text = "[Shoot Royce] I've had enough." },
          { hasTag = true, text = "[Lower weapon]" } })
check("[Shoot Royce] beside an action -> menu (include)", Logic.decide(h, INC), nil)
check("[Shoot Royce] beside an action -> menu (skip)", Logic.decide(h, SKIP), nil)
-- ...but taken when it is the only thing on offer
h = hub({ { questImportant = true, hasIcon = true, hasTag = true, text = "[Get in]" } })
check("lone [Get in]", Logic.decide(h, SKIP), 1)

-- timed choices are always left to you, even a lone spoken line
h = hub({ { questImportant = true, timed = true, text = "Talk to me." } })
check("timed -> menu", Logic.decide(h, SKIP), nil)
check("timed -> reason", select(2, Logic.decide(h, SKIP)), "timed choice")
h = hub({ { questImportant = true, hasTag = true, timed = true, text = "[Draw weapon]" } })
check("lone timed [Draw weapon] -> menu", Logic.decide(h, INC), nil)

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

-- bracketed actions without an icon (the emotes at a mirror) are not chatter either
h = hub({ { hasTag = true, text = "[Smile]" }, { hasTag = true, text = "[Pout]" } })
check("tag actions -> menu (include)", Logic.decide(h, INC), nil)
h = hub({ { hasTag = true, text = "[Smile]" }, { text = "Hey." } })
check("tag action skipped for chatter", Logic.decide(h, INC), 2)

-- the mirror: a yellow [Stop looking] next to emotes is left to you in both modes
local function mirror()
    return hub({ { questImportant = true, hasIcon = true, hasTag = true, text = "[Stop looking]" },
                 { hasTag = true, text = "[Smile]" }, { hasTag = true, text = "[Scowl]" },
                 { hasTag = true, alreadyRead = true, text = "[Pout]" } })
end
check("mirror -> menu (include)", Logic.decide(mirror(), INC), nil)
check("mirror -> menu (skip)", Logic.decide(mirror(), SKIP), nil)
-- ...but a spoken story line next to an action is still taken
h = hub({ { questImportant = true, text = "Let's talk business." }, { hasIcon = true, hasTag = true, text = "[Trade]" } })
check("story beside [Trade]", Logic.decide(h, SKIP), 1)
-- ...and so is an action story line next to plain chatter you have already heard
h = hub({ { questImportant = true, hasIcon = true, hasTag = true, text = "[Stand]" }, { alreadyRead = true, text = "Hey." } })
check("[Stand] beside read chatter", Logic.decide(h, INC), 1)

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

------------------------------------------------------------------ custom mode
-- rules start from "Include optional dialogue"; overrides change single rules
local function custom(overrides)
    local rules = Logic.preset(Logic.MODE_INCLUDE_OPTIONAL)
    for k, v in pairs(overrides or {}) do rules[k] = v end
    return { mode = Logic.MODE_CUSTOM, rules = rules }
end

-- untouched custom rules behave like include; custom without rules too
h = hub({ { text = "Who are you?" }, { questImportant = true } })
check("custom default = include", Logic.decide(h, custom()), 1)
check("custom without rules = include", Logic.decide(h, { mode = Logic.MODE_CUSTOM }), 1)
-- the presets are the rules the simple modes always had
check("skip preset skips optional", Logic.preset(Logic.MODE_SKIP_OPTIONAL).optional, Logic.OPTIONAL_SKIP)
check("preset keeps several-story setting", Logic.preset(Logic.MODE_SKIP_OPTIONAL, Logic.STORY_PICK_FIRST).storyRule,
    Logic.STORY_PICK_FIRST)

-- 1) unread optional line
check("custom skip optional", Logic.decide(h, custom({ optional = Logic.OPTIONAL_SKIP })), 2)

-- 2) optional lifepath line (blue, not yellow)
h = hub({ { blueline = true, lifepath = "LifePaths.Corporate", text = "I know how corps work." },
          { questImportant = true } })
check("optional lifepath skipped by default", Logic.decide(h, INC), 2)
check("optional lifepath heard", Logic.decide(h, custom({ optionalLifepath = Logic.OPTIONAL_HEAR })), 1)
check("optional lifepath -> reason", select(2, Logic.decide(h, custom({ optionalLifepath = Logic.OPTIONAL_HEAR }))),
    "optional lifepath line")
check("only lifepath optional heard", Logic.decide(h, custom({ optional = Logic.OPTIONAL_SKIP,
    optionalLifepath = Logic.OPTIONAL_HEAR })), 1)
h[1].alreadyRead = true
check("read lifepath line not heard again", Logic.decide(h, custom({ optionalLifepath = Logic.OPTIONAL_HEAR })), 2)
-- a blue line we could not identify stays out
h = hub({ { blueline = true }, { questImportant = true } })
check("unknown blue line not heard", Logic.decide(h, custom({ optionalLifepath = Logic.OPTIONAL_HEAR })), 2)

-- 3) one story line, spoken
h = hub({ { questImportant = true, text = "Let's talk business." } })
check("one story -> ask", Logic.decide(h, custom({ oneSpoken = Logic.ONE_ASK })), nil)
check("one story -> ask reason", select(2, Logic.decide(h, custom({ oneSpoken = Logic.ONE_ASK }))),
    "one story line, set to let you choose")

-- 4) one story line that is an action (Jackie's chip, skip optional)
local function jackie()
    return hub({ { questImportant = true, hasIcon = true, hasTag = true, text = "[Take chip] Here goes nothin'." },
                 { text = "Why's it gotta be me?" }, { text = "Surveillance cover the whole hotel?" } })
end
check("[Take chip] when alone -> menu", Logic.decide(jackie(), custom({ optional = Logic.OPTIONAL_SKIP })), nil)
check("[Take chip] right away", Logic.decide(jackie(), custom({ optional = Logic.OPTIONAL_SKIP,
    oneAction = Logic.ACTION_PICK })), 1)
h = hub({ { questImportant = true, hasIcon = true, hasTag = true, text = "[Get in]" } })
check("lone action -> ask", Logic.decide(h, custom({ oneAction = Logic.ACTION_ASK })), nil)
check("lone action when alone", Logic.decide(h, custom()), 1)

-- 5) several plain story lines
h = hub({ { questImportant = true }, { questImportant = true } })
check("custom several -> menu", Logic.decide(h, custom()), nil)
check("custom several -> first", Logic.decide(h, custom({ storyRule = Logic.STORY_PICK_FIRST })), 1)

-- 6) several story lines, one a lifepath line (Hellman, Corpo)
local function hellman()
    return hub({ { questImportant = true, text = "Did the same with the Valentinos, didn't you?" },
                 { questImportant = true, blueline = true, lifepath = "LifePaths.Corporate",
                   text = "You can kick the rat outta the corp, but..." } })
end
check("lifepath same, let me choose", Logic.decide(hellman(), custom()), nil)
check("lifepath same, pick first plain", Logic.decide(hellman(), custom({ storyRule = Logic.STORY_PICK_FIRST })), 1)
check("lifepath picked", Logic.decide(hellman(), custom({ severalLifepath = Logic.SPECIAL_PICK })), 2)
check("lifepath picked -> reason", select(2, Logic.decide(hellman(), custom({ severalLifepath = Logic.SPECIAL_PICK }))),
    "lifepath line")
check("lifepath ask beats pick first", Logic.decide(hellman(), custom({ severalLifepath = Logic.SPECIAL_ASK,
    storyRule = Logic.STORY_PICK_FIRST })), nil)
check("lifepath ask -> reason", select(2, Logic.decide(hellman(), custom({ severalLifepath = Logic.SPECIAL_ASK }))),
    "several story lines, one is a lifepath line")

-- 7) several story lines, one a passed skill check (Netrunner 5)
local function netrunner()
    return hub({ { questImportant = true, text = "What now?" },
                 { questImportant = true, blueline = true, skillCheck = "PlayerBuilds.Netrunner",
                   text = "Lemme neutralize him." } })
end
check("skill same, pick first plain", Logic.decide(netrunner(), custom({ storyRule = Logic.STORY_PICK_FIRST })), 1)
check("skill picked", Logic.decide(netrunner(), custom({ severalSkill = Logic.SPECIAL_PICK })), 2)
check("skill ask beats pick first", Logic.decide(netrunner(), custom({ severalSkill = Logic.SPECIAL_ASK,
    storyRule = Logic.STORY_PICK_FIRST })), nil)
h = hub({ { questImportant = true }, { questImportant = true, checkSuccess = true, text = "[Body 6] ..." } })
check("old-style check counts as skill check", Logic.decide(h, custom({ severalSkill = Logic.SPECIAL_PICK })), 2)

-- a lifepath line outranks a skill check
local function both()
    return hub({ { questImportant = true },
                 { questImportant = true, blueline = true, skillCheck = "PlayerBuilds.Netrunner" },
                 { questImportant = true, blueline = true, lifepath = "LifePaths.Corporate" } })
end
check("both picked -> lifepath", Logic.decide(both(), custom({ severalLifepath = Logic.SPECIAL_PICK,
    severalSkill = Logic.SPECIAL_PICK })), 3)
check("lifepath ask, skill pick -> menu", Logic.decide(both(), custom({ severalLifepath = Logic.SPECIAL_ASK,
    severalSkill = Logic.SPECIAL_PICK })), nil)
check("lifepath same, skill pick -> skill", Logic.decide(both(), custom({ severalSkill = Logic.SPECIAL_PICK })), 2)
-- a special line that is also an action is never picked this way
h = hub({ { questImportant = true, text = "Easy." },
          { questImportant = true, hasTag = true, lifepath = "LifePaths.StreetKid", text = "[Shoot] ..." } })
check("lifepath action not picked", Logic.decide(h, custom({ severalLifepath = Logic.SPECIAL_PICK })), nil)

-- 8) timed choice
h = hub({ { questImportant = true, timed = true, text = "Talk to me." } })
check("timed asks by default", Logic.decide(h, custom()), nil)
check("timed handled normally", Logic.decide(h, custom({ timed = Logic.TIMED_NORMAL })), 1)

-- money and illegal lines stay yours whatever the rules say
h = hub({ { questImportant = true, pay = true }, { questImportant = true, blueline = true, lifepath = "LifePaths.Nomad" } })
check("custom pay -> menu", Logic.decide(h, custom({ severalLifepath = Logic.SPECIAL_PICK })), nil)

-- every rule has a preset answer within its options
for _, rule in ipairs(Logic.RULES) do
    local v = Logic.preset(Logic.MODE_INCLUDE_OPTIONAL)[rule.key]
    check("preset answers " .. rule.key, v ~= nil and v <= #rule.options, true)
end

print(string.format("%d checks, %d failures", count, failures))
os.exit(failures == 0 and 0 or 1)

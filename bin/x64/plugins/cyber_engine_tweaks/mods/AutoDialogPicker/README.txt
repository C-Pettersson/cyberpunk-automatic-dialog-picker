AUTO DIALOG PICKER for Cyberpunk 2077                                  v1.0.0
==============================================================================

Plays conversations for you, so they run like cutscenes. Based on the idea of
the Witcher 3 mod "Automatic dialog picker" by Aelto.

When a dialogue menu appears, the mod waits a moment and then picks a line:

  Mode "Include optional dialogue" (default)
    1. Every unread optional line first, top to bottom.
    2. Then the yellow story line, when there is only one.

  Mode "Skip optional dialogue"
    Goes straight to the yellow story line, when there is only one.

The menu is left to you when:
  - there are several yellow story lines (a real decision), unless you set
    "Several story lines" to "Pick the first plain story line" and one of
    them is plain (not a lifepath, skill-check or action line)
  - a line costs money or is marked illegal
  - only already-read lines, actions ([Trade], [Sit]...) or special lines are left
  - the story line is an action such as [Draw weapon] and there is anything
    else you could press, like [Stop looking] at a mirror next to [Smile]
  - the choice is timed
  - several menus are on screen at once, or the menu is not focused
  - you are not in a conversation (a vendor or NPC prompt in the street)

Scroll during the short delay, or press your "Choose this one myself" hotkey,
and the mod keeps its hands off that menu.


WHY THERE ARE TWO PARTS
------------------------------------------------------------------------------
The game has no script function that selects a dialogue line; only the
keyboard/mouse can. So:

  init.lua / logic.lua           The Cyber Engine Tweaks mod. Reads the menu,
                                 decides what to pick.
  AutoDialogPicker-Helper.ahk    A small AutoHotkey script that presses the
                                 keys the mod asks for (scroll, F). It only
                                 presses keys while the Cyberpunk window is
                                 active, and only when the mod asks.


REQUIREMENTS
------------------------------------------------------------------------------
  - Cyber Engine Tweaks (CET), up to date for your game version
    https://www.nexusmods.com/cyberpunk2077/mods/107
  - AutoHotkey v2 (free)   https://www.autohotkey.com


INSTALL
------------------------------------------------------------------------------
1. Extract the zip into your Cyberpunk 2077 folder (the one that contains
   "bin" and "archive"). You should end up with:
     Cyberpunk 2077\bin\x64\plugins\cyber_engine_tweaks\mods\AutoDialogPicker\init.lua
2. Install AutoHotkey v2.
3. Double-click AutoDialogPicker-Helper.ahk in that same folder. A green "H"
   icon appears in the system tray. Start it each time you play (before or
   after the game). It closes itself 30 seconds after the game closes.
   Tip: make a desktop shortcut to it.


SETTINGS
------------------------------------------------------------------------------
Open the CET overlay in game (default key: ~). The "Auto Dialog Picker" window
has: on/off, mode, what to do with several story lines, delay before picking,
"only inside conversations", on-screen notice, debug log. It also shows
whether the helper is running. Settings are saved in settings.json.

Hotkeys (set them in the CET overlay under Bindings):
  - Turn auto-pick on/off
  - Switch mode (include/skip optional)
  - Choose this one myself (cancel the pending pick)

Keys the helper presses are in helper-keys.ini: scroll up/down = mouse wheel,
select = F. If you rebound dialogue keys in the game, change them there.


GOOD TO KNOW
------------------------------------------------------------------------------
  - Achievements: not affected. Cyberpunk does not disable achievements for
    mods. Choice-based achievements still depend on the lines that get picked.
  - The Cyberpunk window must be focused for the helper to press keys.
  - If you run the game as administrator, run the helper as administrator too.
  - Lines the mod already picked are remembered for 10 minutes, so a line the
    game never marks as read cannot loop forever.
  - Timed choices are handled like any other menu.


TROUBLESHOOTING
------------------------------------------------------------------------------
  Nothing happens
    - CET overlay window says "Helper: not running" -> start the .ahk file.
    - The overlay shows "Stopped: ..." -> the game changed something the mod
      reads. Note the message.
    - Turn on "Debug log" and watch the CET console: it prints each menu with
      its flags and why the mod picked or skipped it. The same goes to
      AutoDialogPicker.log in this folder.
    - Some conversations may not count as "inside a conversation"; try turning
      "Only inside conversations" off (the mod may then also talk to NPCs you
      only look at).

  The highlight does not move / wrong line chosen
    - Check that the mouse wheel moves the dialogue highlight in your game.
      If not, set Up/Down in helper-keys.ini to your dialogue scroll keys.


UNINSTALL
------------------------------------------------------------------------------
Delete the AutoDialogPicker folder.


LICENSE
------------------------------------------------------------------------------
PolyForm Noncommercial 1.0.0 (see LICENSE.md). You may use, share and modify
this mod for any non-commercial purpose; selling it or using it to make money
is not allowed. Keep the license and the "Required Notice" line when sharing.

Source, issues and releases:
https://github.com/C-Pettersson/cyberpunk-automatic-dialog-picker

Idea and rules inspired by "Automatic dialog picker" for The Witcher 3 by Aelto.
Not affiliated with CD PROJEKT RED. Use at your own risk; keep a manual save
before big story moments if you care about a particular outcome.

# Changelog

## 1.0.0

First release.

- Picks dialogue lines for you so conversations play out like cutscenes.
- Three modes: **Include optional dialogue** (hears every unread optional line, then takes the story line), **Skip optional dialogue** (goes straight to the story line) and **Custom**.
- **Custom** mode: choose what happens in each situation (optional lines, optional lifepath lines, one story line, one action story line, several story lines, several with a lifepath line or a passed skill check, timed choices). *Customize these rules* starts from the mode you are in. Lifepath and skill-check lines are recognised from the game's own data (for example `LifePaths.Corporate`, `PlayerBuilds.Netrunner`).
- Leaves the menu to you for real decisions: several story lines, money or illegal lines, timed choices, unfocused or multiple menus, and prompts outside conversations.
- An action story line such as [Draw weapon] or [Shoot Royce] is only picked when nothing else in the menu could be pressed (lines you have already heard don't count), so mirrors don't close on their own.
- Optional setting to take the first plain story line when there are several. It never takes an action or a line with an icon, so a bartender's "Whatcha got?" doesn't open the shop.
- Cancel a pending pick by scrolling or with a hotkey; hotkeys to toggle the mod and cycle through the modes.
- Settings window in the Cyber Engine Tweaks overlay, with helper status and a debug log. The debug log lists every menu with its flags, each line's caption parts (lifepath, skill check, icon), the speaker, the tracked quest, and why a line was or wasn't picked or a pick was dropped.
- AutoHotkey v2 helper that presses the keys (mouse wheel and F by default, configurable).

Requires Cyber Engine Tweaks and AutoHotkey v2. Not yet tested on every game version; turn on the debug log and open an issue if something doesn't work.

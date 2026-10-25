# Changelog

## Unreleased

- Mirrors no longer close on their own: when the only story line is an action such as [Stop looking] and the menu offers other actions ([Smile], [Pout]...), the menu is left to you.
- Bracketed actions without an icon are no longer picked as optional dialogue.
- *Pick the first plain story line* now prefers a spoken line over one with an icon, so a bartender's "Whatcha got?" no longer opens the shop.
- The debug log says why a pick was dropped before it was made (menu closed, changed or lost focus, or a game menu opened).

## 1.0.0

First release.

- Picks dialogue lines for you so conversations play out like cutscenes.
- Two modes: **Include optional dialogue** (hears every unread optional line, then takes the story line) and **Skip optional dialogue** (goes straight to the story line).
- Leaves the menu to you for real decisions: several story lines, money or illegal lines, actions, unfocused or multiple menus, and prompts outside conversations.
- Optional setting to take the first plain story line when there are several.
- Cancel a pending pick by scrolling or with a hotkey; hotkeys to toggle the mod and switch mode.
- Settings window in the Cyber Engine Tweaks overlay, with helper status and a debug log.
- AutoHotkey v2 helper that presses the keys (mouse wheel and F by default, configurable).

Requires Cyber Engine Tweaks and AutoHotkey v2. Not yet tested on every game version; turn on the debug log and open an issue if something doesn't work.

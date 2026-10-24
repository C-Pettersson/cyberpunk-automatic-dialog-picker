#Requires AutoHotkey v2.0
#SingleInstance Force
Persistent

; Auto Dialog Picker - key helper for Cyberpunk 2077
;
; The in-game mod (init.lua) decides which dialogue line to take and writes a
; short command to cmd.txt in this folder: scroll up, scroll down or select.
; This script presses that key, and only while the Cyberpunk window is active.
; It presses nothing on its own. Keys can be changed in helper-keys.ini.

ModDir := A_ScriptDir
CmdFile := ModDir "\cmd.txt"
AliveFile := ModDir "\helper_alive.txt"
IniFile := ModDir "\helper-keys.ini"

UpKey := IniRead(IniFile, "Keys", "Up", "WheelUp")
DownKey := IniRead(IniFile, "Keys", "Down", "WheelDown")
SelectKey := IniRead(IniFile, "Keys", "Select", "f")
HoldMs := Integer(IniRead(IniFile, "Keys", "HoldMs", "60"))
GameExe := IniRead(IniFile, "Game", "Exe", "Cyberpunk2077.exe")
ExitWithGame := IniRead(IniFile, "Game", "ExitWithGame", "1") = "1"

LastSeq := ReadCommand().seq   ; ignore anything written before the helper started
SawGame := false
GoneSince := 0

A_IconTip := "Auto Dialog Picker helper"
TrayTip("Waiting for Cyberpunk 2077. Keys: " UpKey " / " DownKey " / " SelectKey, "Auto Dialog Picker helper")

OnExit(Cleanup)
Heartbeat()
SetTimer(Poll, 40)
SetTimer(Heartbeat, 1000)

UnixNow() {
    return DateDiff(A_NowUTC, "19700101000000", "Seconds")
}

ReadCommand() {
    result := {seq: "", action: "", age: 999}
    try {
        text := FileRead(CmdFile)
    } catch {
        return result
    }
    parts := StrSplit(Trim(text, " `t`r`n"), "|")
    if (parts.Length < 3)
        return result
    result.seq := parts[1]
    result.action := parts[2]
    result.age := IsInteger(parts[3]) ? UnixNow() - Integer(parts[3]) : 0
    return result
}

Press(key) {
    if (SubStr(key, 1, 5) = "Wheel") {
        SendInput("{" key "}")
        return
    }
    SendInput("{" key " down}")
    Sleep(HoldMs)
    SendInput("{" key " up}")
}

Poll() {
    global LastSeq
    cmd := ReadCommand()
    if (cmd.seq = "" || cmd.seq = LastSeq)
        return
    if !WinActive("ahk_exe " GameExe)
        return
    LastSeq := cmd.seq
    if (cmd.age > 3)          ; too old, the game has moved on
        return
    switch cmd.action {
        case "UP": Press(UpKey)
        case "DOWN": Press(DownKey)
        case "SELECT": Press(SelectKey)
    }
}

Heartbeat() {
    global SawGame, GoneSince
    try {
        f := FileOpen(AliveFile, "w")
        f.Write(UnixNow())
        f.Close()
    }
    if !ExitWithGame
        return
    if ProcessExist(GameExe) {
        SawGame := true
        GoneSince := 0
    } else if SawGame {
        if (GoneSince = 0)
            GoneSince := A_TickCount
        else if (A_TickCount - GoneSince > 30000)
            ExitApp()
    }
}

Cleanup(*) {
    try {
        f := FileOpen(AliveFile, "w")
        f.Write("0")
        f.Close()
    }
}

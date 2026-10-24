' dsh-patch-launch.vbs
' Launcher for dsh-patch.ps1 that never creates a visible console window.
'
' Why this exists:
'   A scheduled task running "powershell.exe -WindowStyle Hidden" still makes
'   conhost create a console window first; PowerShell hides it only afterwards,
'   so the user sees a brief flash every time the task fires.
'   WScript.Shell.Run with window style 0 asks the OS for a hidden window from
'   the start, so no flash occurs.
'
' Self-locating: dsh-patch.ps1 is resolved next to this script, so the whole
' tools folder can be moved/copied without editing this file.
'
' Used by scheduled task: \DshExplorerFixAutoRepair
' Keep this file pure ASCII.

Option Explicit

Dim fso, shell, base, cmd, rc

Set fso = CreateObject("Scripting.FileSystemObject")
Set shell = CreateObject("WScript.Shell")
base = fso.GetParentFolderName(WScript.ScriptFullName)

cmd = "powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass " & _
      "-File """ & base & "\dsh-patch.ps1"""

' 0 = hidden window, True = wait for completion
rc = shell.Run(cmd, 0, True)

WScript.Quit rc

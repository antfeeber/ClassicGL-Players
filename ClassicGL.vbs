Option Explicit
Dim shell, fs, root, ps, q
Set shell = CreateObject("WScript.Shell")
Set fs = CreateObject("Scripting.FileSystemObject")
root = fs.GetParentFolderName(WScript.ScriptFullName)
shell.CurrentDirectory = root
q = Chr(34)
ps = shell.ExpandEnvironmentStrings("%SystemRoot%") & "\System32\WindowsPowerShell\v1.0\powershell.exe"
shell.Run q & ps & q & " -NoProfile -NonInteractive -ExecutionPolicy Bypass -File " & q & root & "\Updater.ps1" & q, 0, True

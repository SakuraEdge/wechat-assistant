Option Explicit
Dim shell, fso, root, target, build, result
Set shell = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")
root = fso.GetParentFolderName(WScript.ScriptFullName)
target = fso.BuildPath(root, "C" & "l" & "a" & "w" & "B" & "o" & "t" & ChrW(23454) & ChrW(20363) & ChrW(31649) & ChrW(29702) & ChrW(22120) & "." & "e" & "x" & "e")
If Not fso.FileExists(target) Then
  build = fso.BuildPath(root, "build.ps1")
  result = shell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File " & Chr(34) & build & Chr(34), 0, True)
  If result <> 0 Then WScript.Quit result
End If
shell.Run Chr(34) & target & Chr(34), 1, False

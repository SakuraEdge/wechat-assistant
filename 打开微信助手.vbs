Set shell = CreateObject("WScript.Shell")
Set files = CreateObject("Scripting.FileSystemObject")
root = files.GetParentFolderName(WScript.ScriptFullName)
exeName = ChrW(&H5FAE) & ChrW(&H4FE1) & ChrW(&H52A9) & ChrW(&H624B) & ".exe"
If Not files.FileExists(root & "\" & exeName) Then
  result = shell.Run("powershell.exe -NoProfile -ExecutionPolicy Bypass -File """ & root & "\build.ps1""", 0, True)
  If result <> 0 Then WScript.Quit result
End If
shell.Run """" & root & "\" & exeName & """", 1, False

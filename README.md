# DriveSize
Windows Control Panel Applet Drive Size Chart (percent size + GB)

# Release 1.0.0
Beta version 1.0.0

# Register
Add the following registry key to register the applet:

[code]reg add "HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Control Panel\Cpls" /v Drive Size /t REG_SZ /d "C:\Windows\System32\DriveSize.cpl" /f
[/code]
Run Administrator privilages this command to register the applet.
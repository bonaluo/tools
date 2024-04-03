@echo off
winget settings --enable InstallerHashOverride
winget update -u -r -h --ignore-security-hash --accept-package-agreements --authentication-mode silentPreferred
pause

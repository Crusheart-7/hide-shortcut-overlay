@echo off
"%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "%~dp0Install.ps1"
set "result=%ERRORLEVEL%"
echo.
echo Exit code: %result%
pause
exit /b %result%

@echo off
chcp 65001 >nul
title ChatGPT Microsoft Store MSIX Updater

powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0Update-ChatGPT-Codex.ps1"
set "exit_code=%ERRORLEVEL%"

echo.
if not "%exit_code%"=="0" (
    echo Update failed. See the error message above.
) else (
    echo Finished.
)
pause
exit /b %exit_code%

@echo off
setlocal
cd /d "d:\Locode\antigravity_ide"
powershell -ExecutionPolicy Bypass -File ".\deploy_phone_clean.ps1"
exit /b %ERRORLEVEL%

@echo off
setlocal

set "SCRIPT_DIR=%~dp0"
set "PROJECT_DIR=%SCRIPT_DIR%"
if "%PROJECT_DIR:~-1%"=="\" set "PROJECT_DIR=%PROJECT_DIR:~0,-1%"
set "DEVICE_ID=39201FDJG0001G"
set "PS_SCRIPT=%PROJECT_DIR%\deploy_phone_clean.ps1"

if not exist "%PS_SCRIPT%" (
  echo ERROR: Missing "%PS_SCRIPT%"
  echo Run this script from the antigravity_ide folder.
  exit /b 1
)

cd /d "%PROJECT_DIR%" || (
  echo ERROR: Cannot access project directory "%PROJECT_DIR%".
  exit /b 1
)

echo ======================================
echo   LOCODE PHONE FRESH INSTALL
echo ======================================
echo Project: %PROJECT_DIR%
echo Device: %DEVICE_ID%
echo.

if /I "%~1"=="rebuild" (
  powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -DeviceId %DEVICE_ID%
) else (
  powershell -ExecutionPolicy Bypass -File "%PS_SCRIPT%" -DeviceId %DEVICE_ID%
)

if errorlevel 1 (
  echo.
  echo FAILED: deploy_phone_clean.ps1 returned an error.
  exit /b 1
)

echo.
echo SUCCESS: Locode installed and launched.
exit /b 0

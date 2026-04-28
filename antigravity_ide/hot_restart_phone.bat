@echo off
title Locode Phone Hot Restart
color 0A

set "DEVICE_ID=39201FDJG0001G"
set "FLUTTER_BIN=D:\Locode\flutter_sdk\bin\flutter.bat"

echo.
echo  ======================================
12: echo    LOCODE PHONE HOT RESTART
13: echo    (Fast Development Mode)
14: echo  ======================================
15: echo.

:: Ensure ADB is connected and port is reversed
echo [1/2] Configuring device bridge (%DEVICE_ID%)...
adb -s %DEVICE_ID% reverse tcp:8000 tcp:8000 >nul 2>&1
echo       Done.

echo.
echo [2/2] Launching Flutter Run...
echo.
echo  💡 TIPS:
echo     - Press 'r' to Hot Reload (updates code instantly)
echo     - Press 'R' to Hot Restart (resets app state)
echo     - Press 'q' to quit
echo.

"%FLUTTER_BIN%" run -d %DEVICE_ID%

echo.
echo [Locode IDE] Session ended.
pause

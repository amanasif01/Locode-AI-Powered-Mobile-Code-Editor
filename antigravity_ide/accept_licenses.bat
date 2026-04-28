@echo off
set "JAVA_HOME=D:\AS\jbr"
set "PATH=D:\AS\jbr\bin;%PATH%"
set "SDK_ROOT=C:\Users\Aman\AppData\Local\Android\Sdk"
set "SDKMANAGER=%SDK_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat"

echo   [LOCODE BUILDER] Setting environment variables...
echo   [LOCODE BUILDER] Preparing license response file...

:: Create a response file with 20 "y" inputs
(
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
echo y
) > %temp%\license_responses.txt

echo   [LOCODE BUILDER] Bulk-accepting all Android SDK and NDK licenses...
"%SDKMANAGER%" --licenses --sdk_root="%SDK_ROOT%" < %temp%\license_responses.txt

echo   [LOCODE BUILDER] Licenses check complete.

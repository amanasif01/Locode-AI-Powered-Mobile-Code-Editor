@echo off
set "JAVA_HOME=D:\AS\jbr"
set "PATH=D:\AS\jbr\bin;%PATH%"
set "SDK_ROOT=C:\Users\Aman\AppData\Local\Android\Sdk"
set "SDKMANAGER=%SDK_ROOT%\cmdline-tools\latest\bin\sdkmanager.bat"

echo   [LOCODE BUILDER] Setting environment variables...
echo   [LOCODE BUILDER] Installing CMake 3.31.0 (Required for fllama)...

(echo y) | "%SDKMANAGER%" --install "cmake;3.31.0" --sdk_root="%SDK_ROOT%"

echo   [LOCODE BUILDER] CMake installation check complete.

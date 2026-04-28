param(
    [string]$DeviceId = "39201FDJG0001G",
    [string]$ProjectDir = "d:\Locode\antigravity_ide",
    [string]$FlutterExe = "d:\Locode\flutter_sdk\bin\flutter.bat",
    [string]$AdbExe = "C:\Users\Aman\AppData\Local\Android\Sdk\platform-tools\adb.exe",
    [string]$PackageName = "com.example.antigravity_ide",
    [int]$DeviceTimeoutSeconds = 60
)

$ErrorActionPreference = "Stop"

function Fail([string]$Message) {
    Write-Host "ERROR: $Message" -ForegroundColor Red
    exit 1
}

function Info([string]$Message) {
    Write-Host $Message -ForegroundColor Cyan
}

function Wait-ForDeviceReady {
    param(
        [string]$TargetDevice,
        [int]$TimeoutSeconds
    )

    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ((Get-Date) -lt $deadline) {
        $devices = & $AdbExe devices
        if ($devices -match "$TargetDevice\s+device") {
            return
        }
        if ($devices -match "$TargetDevice\s+unauthorized") {
            Fail "Device is unauthorized. Unlock phone and accept 'Allow USB debugging'."
        }
        Start-Sleep -Seconds 2
    }
    Fail "Device $TargetDevice was not ready within $TimeoutSeconds seconds."
}

if (-not (Test-Path $ProjectDir)) { Fail "Project directory not found: $ProjectDir" }
if (-not (Test-Path $FlutterExe)) { Fail "Flutter executable not found: $FlutterExe" }
if (-not (Test-Path $AdbExe)) { Fail "ADB executable not found: $AdbExe" }

Push-Location $ProjectDir
try {
    Info "=== Locode clean deploy ==="
    Info "Project: $ProjectDir"
    Info "Device: $DeviceId"

    Info "[1/6] Restarting adb server..."
    & $AdbExe kill-server | Out-Null
    Start-Sleep -Seconds 1
    & $AdbExe start-server | Out-Null

    Info "[2/6] Waiting for device..."
    Wait-ForDeviceReady -TargetDevice $DeviceId -TimeoutSeconds $DeviceTimeoutSeconds

    Info "[3/6] Building debug APK..."
    & $FlutterExe build apk --debug
    if ($LASTEXITCODE -ne 0) {
        Fail "Flutter build failed with exit code $LASTEXITCODE."
    }

    $apkPath = Join-Path $ProjectDir "build\app\outputs\flutter-apk\app-debug.apk"
    if (-not (Test-Path $apkPath)) {
        Fail "APK not found after build: $apkPath"
    }

    Info "[4/6] Installing APK on device..."
    & $AdbExe -s $DeviceId install -r -t $apkPath
    if ($LASTEXITCODE -ne 0) {
        Fail "ADB install failed with exit code $LASTEXITCODE."
    }

    Info "[5/6] Configuring backend port reverse..."
    & $AdbExe -s $DeviceId reverse tcp:8000 tcp:8000 | Out-Null

    Info "[6/6] Launching app..."
    & $AdbExe -s $DeviceId shell monkey -p $PackageName -c android.intent.category.LAUNCHER 1 | Out-Null

    Write-Host "SUCCESS: App built, installed, and launched." -ForegroundColor Green
    exit 0
}
catch {
    Fail $_.Exception.Message
}
finally {
    Pop-Location
}

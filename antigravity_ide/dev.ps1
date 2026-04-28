param(
    [ValidateSet("run", "attach", "install", "analyze", "doctor", "devices", "emu", "runemu")]
    [string]$Action = "run",
    [string]$Device = "39201FDJG0001G",
    [string]$EmulatorName = "locode_api36_x86",
    [switch]$Release
)

$ErrorActionPreference = "Stop"
$PSNativeCommandUseErrorActionPreference = $false

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$flutter = "d:\Locode\flutter_sdk\bin\flutter.bat"
$emulator = "C:\Users\Aman\AppData\Local\Android\Sdk\emulator\emulator.exe"
$adb = "C:\Users\Aman\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$env:ANDROID_EMULATOR_HOME = "D:\Android"
$env:ANDROID_AVD_HOME = "D:\Android\avd"
$packageName = "com.example.antigravity_ide"

if (-not (Test-Path $flutter)) {
    throw "Flutter SDK not found at $flutter"
}

Push-Location $projectRoot
try {
    function Wait-ForOnlineDevice {
        param(
            [string]$TargetDevice,
            [int]$TimeoutSeconds = 45
        )
        if (-not (Test-Path $adb)) {
            throw "adb not found at $adb"
        }
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while ((Get-Date) -lt $deadline) {
            $stateRaw = cmd /c """$adb"" -s $TargetDevice get-state 2>nul"
            $state = if ($null -eq $stateRaw) { "" } else { $stateRaw.ToString().Trim() }
            if ($state -eq "device") {
                return
            }
            if ([string]::IsNullOrWhiteSpace($state)) {
                $state = (cmd /c """$adb"" devices").Trim()
                if ($state -match "$TargetDevice\s+unauthorized") {
                    throw "Device $TargetDevice is unauthorized. Unlock the phone and accept the USB debugging prompt, then run the script again."
                }
            }
            Start-Sleep -Seconds 2
        }
        throw "Timed out after $TimeoutSeconds seconds waiting for Android device $TargetDevice to become online."
    }

    switch ($Action) {
        "devices" {
            & $flutter devices
            break
        }
        "doctor" {
            & $flutter doctor -v
            break
        }
        "analyze" {
            & $flutter analyze lib\domain\compiler_service_mobile.dart assets\compile_engine.html
            break
        }
        "run" {
            $args = @("run", "-d", $Device, "--uninstall-first")
            if ($Release) {
                $args = @("run", "-d", $Device, "--release", "--uninstall-first")
            }
            Write-Host "Starting Flutter on device: $Device" -ForegroundColor Cyan
            if (Test-Path $adb) {
                & $adb -s $Device reverse tcp:8000 tcp:8000 | Out-Null
                Write-Host "ADB reverse set: device 127.0.0.1:8000 -> host 8000" -ForegroundColor DarkCyan
            }
            Write-Host "Hot reload: press r | Hot restart: press R | Quit: q" -ForegroundColor DarkCyan
            & $flutter @args
            break
        }
        "attach" {
            $args = @("attach", "-d", $Device)
            Write-Host "Attaching to running app on device: $Device" -ForegroundColor Cyan
            Write-Host "After attach: press r for hot reload | R for hot restart" -ForegroundColor DarkCyan
            & $flutter @args
            break
        }
        "install" {
            Write-Host "Preparing device $Device for app install..." -ForegroundColor Cyan
            Wait-ForOnlineDevice -TargetDevice $Device -TimeoutSeconds 45
            if (Test-Path $adb) {
                & $adb -s $Device reverse tcp:8000 tcp:8000 | Out-Null
                Write-Host "ADB reverse set: device 127.0.0.1:8000 -> host 8000" -ForegroundColor DarkCyan
            }

            $args = @("install", "-d", $Device)
            if ($Release) {
                $args = @("install", "-d", $Device, "--release")
            }
            Write-Host "Installing Flutter app on device: $Device" -ForegroundColor Cyan
            & $flutter @args
            if ($LASTEXITCODE -ne 0) {
                throw "flutter install failed with exit code $LASTEXITCODE"
            }

            Write-Host "Launching $packageName on device..." -ForegroundColor Cyan
            if (Test-Path $adb) {
                & $adb -s $Device shell monkey -p $packageName -c android.intent.category.LAUNCHER 1 | Out-Null
            }
            Write-Host "Install + launch complete." -ForegroundColor Green
            break
        }
        "emu" {
            if (-not (Test-Path $emulator)) {
                throw "Android emulator binary not found at $emulator"
            }
            Write-Host "Launching emulator $EmulatorName with AVD home on D: ..." -ForegroundColor Cyan
            & $emulator -avd $EmulatorName -gpu swiftshader_indirect -accel off -no-snapshot
            break
        }
        "runemu" {
            if (-not (Test-Path $emulator)) {
                throw "Android emulator binary not found at $emulator"
            }
            Write-Host "Starting emulator $EmulatorName (AVD on D:)..." -ForegroundColor Cyan
            Start-Process -FilePath $emulator -ArgumentList @("-avd", $EmulatorName, "-gpu", "swiftshader_indirect", "-accel", "off", "-no-snapshot")
            Start-Sleep -Seconds 8
            $args = @("run", "-d", "android", "--uninstall-first")
            if ($Release) {
                $args = @("run", "-d", "android", "--release", "--uninstall-first")
            }
            Write-Host "Hot reload: press r | Hot restart: press R | Quit: q" -ForegroundColor DarkCyan
            & $flutter @args
            break
        }
    }
}
catch {
    Write-Host ("ERROR: " + $_.Exception.Message) -ForegroundColor Red
    exit 1
}
finally {
    Pop-Location
}

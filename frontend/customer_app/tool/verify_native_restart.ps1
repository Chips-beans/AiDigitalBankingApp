param([string]$Device = 'emulator-5554')
$ErrorActionPreference = 'Stop'
$sdkDirectory = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\sdk' }
$adbPath = Join-Path $sdkDirectory 'platform-tools\adb.exe'
if (-not (Test-Path -LiteralPath $adbPath)) { throw 'Set ANDROID_SDK_ROOT to the Android SDK directory.' }
$deviceState = & $adbPath -s $Device get-state 2>&1
if ($LASTEXITCODE -ne 0 -or "$deviceState".Trim() -ne 'device') { throw "Android device $Device is not connected and ready." }
$bootCompleted = & $adbPath -s $Device shell getprop sys.boot_completed
if ($LASTEXITCODE -ne 0 -or "$bootCompleted".Trim() -ne '1') { throw 'Wait for Android to finish booting before native restart QA.' }
function Stop-QaApplication {
    & $adbPath -s $Device shell am force-stop com.bank.customer_app
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop the QA application process.' }
    $processNames = & $adbPath -s $Device shell ps -A -o NAME
    if ($LASTEXITCODE -ne 0) { throw 'Could not inspect the QA application process.' }
    if ($processNames | Where-Object { $_.Trim() -match '^com\.bank\.customer_app(:|$)' }) {
        throw 'The previous application process is still running.'
    }
}
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    Stop-QaApplication
    foreach ($phase in @('seed', 'restore', 'signedout')) {
        Write-Output "Checking native restart phase: $phase"
        # Flutter may uninstall integration apps by default, deleting Keystore/data.
        # Retain the installation so these phases test process death, not reinstall.
        & flutter test integration_test/session_restart_test.dart -d $Device "--dart-define=QA_RESTART_PHASE=$phase" --no-uninstall --reporter expanded
        if ($LASTEXITCODE -ne 0) { throw "Native restart QA failed in $phase" }
        Stop-QaApplication
    }
    Write-Output 'Native restart QA passed: persisted, restored/rotated, and remained signed out across three processes.'
} finally { Pop-Location }

param(
    [string]$Device = 'emulator-5556',
    [string]$Config = '.local/f3-qa.json',
    [ValidateSet('seed','uncertain','restore','signedout')]
    [string[]]$Phases = @('seed','uncertain','restore','signedout')
)
$ErrorActionPreference = 'Stop'
$sdkDirectory = if ($env:ANDROID_SDK_ROOT) { $env:ANDROID_SDK_ROOT } elseif ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { Join-Path $env:LOCALAPPDATA 'Android\sdk' }
$adbPath = Join-Path $sdkDirectory 'platform-tools\adb.exe'
function Stop-QaApplication {
    & $adbPath -s $Device shell am force-stop com.bank.customer_app
    if ($LASTEXITCODE -ne 0) { throw 'Could not stop the QA application.' }
    $names = & $adbPath -s $Device shell ps -A -o NAME
    if ($LASTEXITCODE -ne 0 -or ($names | Where-Object { $_.Trim() -match '^com\.bank\.customer_app(:|$)' })) {
        throw 'Could not verify termination of the previous application process.'
    }
}
Push-Location (Split-Path -Parent $PSScriptRoot)
try {
    if (-not (Test-Path -LiteralPath $Config)) { throw 'Create the ignored Gmail QA configuration first.' }
    $boot = & $adbPath -s $Device shell getprop sys.boot_completed
    if ($LASTEXITCODE -ne 0 -or "$boot".Trim() -ne '1') { throw 'Wait for the QA emulator to boot.' }
    foreach ($phase in $Phases) {
        Stop-QaApplication
        Write-Output "F3 Gmail QA phase: $phase"
        & flutter test integration_test/f3_gmail_test.dart -d $Device "--dart-define-from-file=$Config" "--dart-define=QA_F3_PHASE=$phase" --no-uninstall --reporter expanded
        if ($LASTEXITCODE -ne 0) { throw "F3 Gmail QA failed in $phase; existing test data was retained." }
        Stop-QaApplication
    }
    Write-Output 'Requested F3 Gmail/native restart phases passed.'
} finally { Pop-Location }

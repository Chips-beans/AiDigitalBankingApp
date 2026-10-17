[CmdletBinding()]
param()

# Dependency-free launcher regression checks; no real process/network is started.
# Run start-local-mail.ps1 once to populate its verified official archive first.
$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
$sourceArchive = Join-Path $backendRoot '.local\mailpit\1.31.5\mailpit-windows-amd64.zip'
$sourceExecutable = Join-Path $backendRoot '.local\mailpit\1.31.5\mailpit.exe'
if (-not (Test-Path -LiteralPath $sourceArchive) -or -not (Test-Path -LiteralPath $sourceExecutable)) {
    throw 'Run start-local-mail.ps1 first to populate the official Mailpit cache.'
}
$binaryHash = (Get-FileHash -LiteralPath $sourceExecutable -Algorithm SHA256).Hash
$testRoot = Join-Path $backendRoot ('.local\launcher-qa\' + [guid]::NewGuid().ToString('N'))
$passed = 0

function New-Sandbox([bool]$WithArchive = $true, [bool]$WithExecutable = $false) {
    $root = Join-Path $testRoot ([guid]::NewGuid().ToString('N'))
    $scripts = Join-Path $root 'scripts'
    $cache = Join-Path $root '.local\mailpit\1.31.5'
    New-Item -ItemType Directory -Path $scripts -Force | Out-Null
    New-Item -ItemType Directory -Path $cache -Force | Out-Null
    $launcher = Join-Path $scripts 'start-local-mail.ps1'
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'start-local-mail.ps1') -Destination $launcher
    if ($WithArchive) { Copy-Item -LiteralPath $sourceArchive -Destination $cache }
    if ($WithExecutable) { Copy-Item -LiteralPath $sourceExecutable -Destination $cache }
    return [pscustomobject]@{ Script=$launcher; Cache=$cache; Exe=(Join-Path $cache 'mailpit.exe'); Archive=(Join-Path $cache 'mailpit-windows-amd64.zip') }
}

function Assert-Fails([string]$Launcher, [string]$Pattern) {
    $message = $null
    try { & $Launcher | Out-Null } catch { $message = $_.Exception.Message }
    if (-not $message -or $message -notlike $Pattern) { throw "Expected failure '$Pattern'; received '$message'." }
}

function Check([string]$Name, [scriptblock]$Body) {
    & $Body
    $script:passed++
    Write-Output "PASS: $Name"
}

Check 'Corrupt executable is repaired from the verified archive before launch' {
    $case = New-Sandbox
    Set-Content -LiteralPath $case.Exe -Value 'Invalid cached executable'
    function Get-NetTCPConnection { @() }
    function Start-Process {
        if ((Get-FileHash -LiteralPath $case.Exe -Algorithm SHA256).Hash -ne $binaryHash) { throw 'Unverified executable reached launch.' }
        throw 'QA verified launch intercepted'
    }
    Assert-Fails $case.Script '*QA verified launch intercepted*'
}

Check 'Corrupt archive fails closed without launching' {
    $case = New-Sandbox
    Set-Content -LiteralPath $case.Archive -Value 'Corrupt archive'
    function Get-NetTCPConnection { @() }
    function Start-Process { throw 'Unexpected launch.' }
    Assert-Fails $case.Script '*Cached Mailpit archive checksum is invalid*'
}

Check 'Fresh download uses basic parsing and becomes a verified cache entry' {
    $case = New-Sandbox $false
    function Get-NetTCPConnection { @() }
    function Invoke-WebRequest {
        param($Uri, $OutFile, $TimeoutSec, [switch]$UseBasicParsing)
        if (-not $UseBasicParsing -or $TimeoutSec -le 0) { throw 'Unsafe or unbounded downloader.' }
        if ($OutFile -eq $case.Archive) { throw 'Download wrote directly to the final cache path.' }
        Copy-Item -LiteralPath $sourceArchive -Destination $OutFile
    }
    function Start-Process { throw 'QA verified launch intercepted' }
    Assert-Fails $case.Script '*QA verified launch intercepted*'
    if (-not (Test-Path -LiteralPath $case.Archive)) { throw 'Verified download was not cached.' }
}

Check 'Interrupted download leaves no poisoned archive or partial file' {
    $case = New-Sandbox $false
    function Get-NetTCPConnection { @() }
    function Invoke-WebRequest { param($Uri, $OutFile, $TimeoutSec, [switch]$UseBasicParsing); Set-Content -LiteralPath $OutFile -Value 'Partial'; throw 'QA interrupted download' }
    function Start-Process { throw 'Unexpected launch.' }
    Assert-Fails $case.Script '*QA interrupted download*'
    if ((Test-Path -LiteralPath $case.Archive) -or @(Get-ChildItem -LiteralPath $case.Cache -Filter '*.tmp').Count -gt 0) {
        throw 'Interrupted download left cached/partial data.'
    }
}

Check 'Invalid downloaded checksum never becomes the cache or executes' {
    $case = New-Sandbox $false
    function Get-NetTCPConnection { @() }
    function Invoke-WebRequest { param($Uri, $OutFile, $TimeoutSec, [switch]$UseBasicParsing); Set-Content -LiteralPath $OutFile -Value 'Invalid download' }
    function Start-Process { throw 'Unexpected launch.' }
    Assert-Fails $case.Script '*Downloaded Mailpit archive checksum does not match*'
    if (Test-Path -LiteralPath $case.Archive) { throw 'Invalid download was cached.' }
}

Check 'Conflicting listener is preserved and no duplicate starts' {
    $case = New-Sandbox
    function Get-NetTCPConnection { [pscustomobject]@{LocalPort=1025;LocalAddress='127.0.0.1';OwningProcess=12345} }
    function Start-Process { throw 'Unexpected launch.' }
    function Stop-Process { throw 'Attempted to stop another process.' }
    Assert-Fails $case.Script '*Port 1025 or 8025 is already occupied*'
}

Check 'Mailpit environment overrides are rejected without exposing their values' {
    $case = New-Sandbox
    $previous = [Environment]::GetEnvironmentVariable('MP_SMTP_RELAY_CONFIG', 'Process')
    try {
        [Environment]::SetEnvironmentVariable('MP_SMTP_RELAY_CONFIG', 'qa-do-not-inherit', 'Process')
        function Start-Process { throw 'Unexpected launch.' }
        Assert-Fails $case.Script '*Clear MP_*environment overrides*'
    } finally { [Environment]::SetEnvironmentVariable('MP_SMTP_RELAY_CONFIG', $previous, 'Process') }
}

Check 'Healthy verified inbox is reused' {
    $case = New-Sandbox $true $true
    function Get-NetTCPConnection { foreach ($port in @(1025,8025)) { [pscustomobject]@{LocalPort=$port;LocalAddress='127.0.0.1';OwningProcess=12345} } }
    function Get-Process { [pscustomobject]@{Id=12345;Path=$case.Exe} }
    function Invoke-RestMethod { [pscustomobject]@{Version='v1.31.5'} }
    function Start-Process { throw 'Unexpected launch.' }
    $output = & $case.Script
    if (($output -join ' ') -notlike '*already running*') { throw 'Healthy inbox was not reused.' }
}

Check 'Unhealthy existing inbox is rejected and preserved' {
    $case = New-Sandbox $true $true
    function Get-NetTCPConnection { foreach ($port in @(1025,8025)) { [pscustomobject]@{LocalPort=$port;LocalAddress='127.0.0.1';OwningProcess=12345} } }
    function Get-Process { [pscustomobject]@{Id=12345;Path=$case.Exe} }
    function Invoke-RestMethod { throw 'QA unhealthy inbox' }
    function Start-Process { throw 'Unexpected launch.' }
    function Stop-Process { throw 'Attempted to stop an existing inbox.' }
    Assert-Fails $case.Script '*Existing Mailpit is not healthy*'
}

Check 'Failed startup cleans up only its new child' {
    $case = New-Sandbox $true $true
    $child = [pscustomobject]@{Id=12345;HasExited=$false;Killed=$false}
    $child | Add-Member ScriptMethod Refresh { }
    $child | Add-Member ScriptMethod Kill { $this.Killed=$true; $this.HasExited=$true }
    $child | Add-Member ScriptMethod WaitForExit { param($Milliseconds); return $true }
    function Get-NetTCPConnection { @() }
    function Start-Process { $child }
    function Start-Sleep { }
    Assert-Fails $case.Script '*Mailpit did not become ready*'
    if (-not $child.Killed) { throw 'Failed startup left its child running.' }
}

Check 'UI alone cannot satisfy SMTP readiness' {
    $case = New-Sandbox $true $true
    $state = [pscustomobject]@{Started=$false}
    $child = [pscustomobject]@{Id=12345;HasExited=$false;Killed=$false}
    $child | Add-Member ScriptMethod Refresh { }
    $child | Add-Member ScriptMethod Kill { $this.Killed=$true; $this.HasExited=$true }
    $child | Add-Member ScriptMethod WaitForExit { param($Milliseconds); return $true }
    function Get-NetTCPConnection { if ($state.Started) { [pscustomobject]@{LocalPort=8025;LocalAddress='127.0.0.1';OwningProcess=12345} } }
    function Invoke-RestMethod { [pscustomobject]@{Version='v1.31.5'} }
    function Start-Process { $state.Started=$true; $child }
    function Start-Sleep { }
    Assert-Fails $case.Script '*Mailpit did not become ready*'
    if (-not $child.Killed) { throw 'UI-only child was left running.' }
}

Check 'Extraction output is checked before execution' {
    $case = New-Sandbox
    function Get-NetTCPConnection { @() }
    function Expand-Archive { Set-Content -LiteralPath $case.Exe -Value 'Invalid extraction' }
    function Start-Process { throw 'Unexpected launch.' }
    Assert-Fails $case.Script '*Extracted Mailpit executable checksum is invalid*'
}

Write-Output "Launcher QA: $passed checks passed. Isolated fixtures: $testRoot"

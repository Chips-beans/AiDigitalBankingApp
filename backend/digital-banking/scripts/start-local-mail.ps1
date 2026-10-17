[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$backendRoot = Split-Path -Parent $PSScriptRoot
$version = '1.31.5'
$expectedHash = '9637e21c02b33185fe69268ba05317152a5d8ac7877115e8a70e29b7e199e8dc'
$toolDirectory = Join-Path $backendRoot ".local\mailpit\$version"
$executable = Join-Path $toolDirectory 'mailpit.exe'

function Test-MailpitReady([int]$ProcessId) {
    $ports = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in @(1025, 8025) })
    if (@($ports.LocalPort | Sort-Object -Unique).Count -ne 2 -or
        @($ports | Where-Object { $_.LocalAddress -ne '127.0.0.1' -or $_.OwningProcess -ne $ProcessId }).Count -gt 0) {
        return $false
    }
    try {
        $info = Invoke-RestMethod -Uri 'http://127.0.0.1:8025/api/v1/info' -TimeoutSec 1
        return $info.Version -eq "v$version"
    } catch { return $false }
}

# Mailpit environment overrides can enable forwarding/relaying or change listeners.
# Fail closed rather than inheriting unrelated global Mailpit configuration.
$overrides = @([Environment]::GetEnvironmentVariables('Process').Keys |
    Where-Object { $_ -like 'MP_*' -and -not [string]::IsNullOrEmpty([Environment]::GetEnvironmentVariable($_, 'Process')) })
if ($overrides.Count -gt 0) {
    throw 'Clear MP_* environment overrides before using this local-only Mailpit launcher.'
}

$mutex = [System.Threading.Mutex]::new($false, 'Local\DigitalBankingFoundationMailpit')
$ownsLock = $false
try {
    try { $ownsLock = $mutex.WaitOne(0) }
    catch [System.Threading.AbandonedMutexException] { $ownsLock = $true }
    if (-not $ownsLock) { throw 'Another Mailpit launcher is running; retry after it finishes.' }

    # Never take over ports belonging to another service or differently configured inbox.
    $existing = $null
    $listeners = @(Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Where-Object { $_.LocalPort -in @(1025, 8025) })
    if ($listeners.Count -gt 0) {
        $owners = @($listeners.OwningProcess | Sort-Object -Unique)
        if ($owners.Count -eq 1 -and @($listeners.LocalPort | Sort-Object -Unique).Count -eq 2) {
            $candidate = Get-Process -Id $owners[0] -ErrorAction SilentlyContinue
            if ($candidate -and $candidate.Path -eq $executable -and
                @($listeners | Where-Object { $_.LocalAddress -ne '127.0.0.1' }).Count -eq 0) {
                $existing = $candidate
            }
        }
        if (-not $existing) {
            throw 'Port 1025 or 8025 is already occupied. Inspect its owner before starting Mailpit.'
        }
    }

    New-Item -ItemType Directory -Path $toolDirectory -Force | Out-Null
    $archive = Join-Path $toolDirectory 'mailpit-windows-amd64.zip'
    if (-not (Test-Path -LiteralPath $archive)) {
        $partial = Join-Path $toolDirectory ("download-" + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            Write-Output "Downloading Mailpit v$version from the official GitHub release..."
            Invoke-WebRequest -UseBasicParsing -TimeoutSec 60 -Uri "https://github.com/axllent/mailpit/releases/download/v$version/mailpit-windows-amd64.zip" -OutFile $partial
            if ((Get-FileHash -LiteralPath $partial -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
                throw 'Downloaded Mailpit archive checksum does not match the pinned release. It was not executed.'
            }
            Move-Item -LiteralPath $partial -Destination $archive -Force
        } finally {
            if (Test-Path -LiteralPath $partial) { Remove-Item -LiteralPath $partial -Force }
        }
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $expectedHash) {
        throw "Cached Mailpit archive checksum is invalid. Remove the corrupt file at $archive and retry."
    }

    # Also verify the executable actually being run, including on cached/reuse paths.
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [System.IO.Compression.ZipFile]::OpenRead($archive)
    try {
        $entry = $zip.GetEntry('mailpit.exe')
        if (-not $entry) { throw 'Verified archive does not contain mailpit.exe.' }
        $stream = $entry.Open()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { $binaryHash = [BitConverter]::ToString($sha.ComputeHash($stream)).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose(); $stream.Dispose() }
    } finally { $zip.Dispose() }

    $needsExtraction = -not (Test-Path -LiteralPath $executable)
    if (-not $needsExtraction) {
        $needsExtraction = (Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant() -ne $binaryHash
    }
    if ($needsExtraction) {
        if ($existing) { throw 'Running Mailpit binary differs from the verified archive; stop that inbox and retry.' }
        Expand-Archive -LiteralPath $archive -DestinationPath $toolDirectory -Force
    }
    if ((Get-FileHash -LiteralPath $executable -Algorithm SHA256).Hash.ToLowerInvariant() -ne $binaryHash) {
        throw 'Extracted Mailpit executable checksum is invalid. It was not executed.'
    }

    if ($existing) {
        if (-not (Test-MailpitReady $existing.Id)) { throw 'Existing Mailpit is not healthy; inspect its logs before restarting it.' }
        Write-Output "Local Mailpit is already running (PID $($existing.Id))."
        Write-Output 'Inbox: http://127.0.0.1:8025 | SMTP: 127.0.0.1:1025'
        return
    }

    # A temporary inbox is sufficient for development; messages disappear when stopped.
    $options = @{
        FilePath = $executable
        ArgumentList = @('--listen', '127.0.0.1:8025', '--smtp', '127.0.0.1:1025',
            '--allowed-hosts', '127.0.0.1,localhost', '--max', '100')
        WorkingDirectory = $toolDirectory
        WindowStyle = 'Hidden'
        PassThru = $true
        RedirectStandardOutput = (Join-Path $toolDirectory 'stdout.log')
        RedirectStandardError = (Join-Path $toolDirectory 'stderr.log')
    }
    $process = Start-Process @options
    $ready = $false
    try {
        for ($attempt = 0; $attempt -lt 30; $attempt++) {
            $process.Refresh()
            if ($process.HasExited) { throw "Mailpit exited. Inspect $toolDirectory\stderr.log" }
            if (Test-MailpitReady $process.Id) {
                $ready = $true
                Write-Output "Local Mailpit started (PID $($process.Id))."
                Write-Output 'Inbox: http://127.0.0.1:8025 | SMTP: 127.0.0.1:1025'
                Write-Output "Stop this inbox with: Stop-Process -Id $($process.Id)"
                return
            }
            Start-Sleep -Milliseconds 200
        }
        throw 'Mailpit did not become ready. Inspect its logs before retrying.'
    } finally {
        # Only clean up the child created by this invocation, never a pre-existing inbox.
        if (-not $ready -and -not $process.HasExited) {
            $process.Kill()
            $process.WaitForExit(5000) | Out-Null
        }
    }
} finally {
    if ($ownsLock) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}

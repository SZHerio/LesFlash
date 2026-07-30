[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Suite,

    [string]$Godot = $env:GODOT,

    [ValidateRange(10, 3600)]
    [int]$TimeoutSeconds = 600,

    [switch]$Windowed,

    [string[]]$UserArgs = @()
)

$ErrorActionPreference = "Stop"
$projectRoot = (Resolve-Path -LiteralPath (Join-Path $PSScriptRoot "..")).Path

function Read-SharedText {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return ""
    }
    $share = [IO.FileShare]::ReadWrite -bor [IO.FileShare]::Delete
    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, $share)
    try {
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $true)
        try {
            return $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

if ([string]::IsNullOrWhiteSpace($Godot)) {
    $Godot = "C:\Users\SZHerio\AppData\Local\Temp\godot-runner-bin-019f89fa\godot.windows.opt.tools.64.exe"
}
if (-not (Test-Path -LiteralPath $Godot -PathType Leaf)) {
    throw "Godot executable was not found: $Godot"
}

$relativeSuite = $Suite.Replace("\", "/")
if ($relativeSuite.StartsWith("res://", [StringComparison]::OrdinalIgnoreCase)) {
    $relativeSuite = $relativeSuite.Substring(6)
}
$suitePath = (Resolve-Path -LiteralPath (Join-Path $projectRoot $relativeSuite)).Path
$testsRoot = (Resolve-Path -LiteralPath (Join-Path $projectRoot "tests")).Path
if (-not $suitePath.StartsWith($testsRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Only suites inside tests/ may be launched: $Suite"
}
if ([IO.Path]::GetExtension($suitePath) -ne ".gd") {
    throw "A Godot test suite must be a .gd file: $Suite"
}
$resourceSuite = "res://" + $suitePath.Substring($projectRoot.Length + 1).Replace("\", "/")

# Every Codex agent shares the same Windows session, project import cache and
# user:// directory. Parallel Godot editor processes have repeatedly contended
# for those files, hung during shutdown and invoked Visual Studio's native JIT
# debugger. A named mutex survives independent shells and is released by Windows
# even if the owning PowerShell process dies.
$mutex = [Threading.Mutex]::new($false, "Local\BomzharaGodotTestRunner-v1")
$hasMutex = $false
$process = $null

try {
    try {
        $hasMutex = $mutex.WaitOne([TimeSpan]::FromMinutes(30))
    }
    catch [Threading.AbandonedMutexException] {
        # Windows grants an abandoned mutex to the next waiter. Treat it as
        # acquired so a killed runner cannot block every later test session.
        $hasMutex = $true
    }
    if (-not $hasMutex) {
        throw "Timed out waiting for the shared Godot test runner"
    }

    # The setting is inherited by the child process. If Godot itself faults,
    # Windows records the failure but does not open a native crash/JIT dialog in
    # the user's desktop session. This affects only this PowerShell process and
    # the Godot child; Visual Studio and system-wide JIT settings stay untouched.
    if (-not ("Bomzhara.NativeErrorMode" -as [type])) {
        Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace Bomzhara {
    public static class NativeErrorMode {
        [DllImport("kernel32.dll")]
        public static extern uint SetErrorMode(uint mode);
    }
}
"@
    }
    $semFailCriticalErrors = 0x0001
    $semNoGpFaultErrorBox = 0x0002
    [Bomzhara.NativeErrorMode]::SetErrorMode($semFailCriticalErrors -bor $semNoGpFaultErrorBox) | Out-Null

    $runRoot = Join-Path ([IO.Path]::GetTempPath()) "bomzhara-godot-runs"
    New-Item -ItemType Directory -Force -Path $runRoot | Out-Null
    $runId = "{0}-{1}" -f ([IO.Path]::GetFileNameWithoutExtension($suitePath)), ([Guid]::NewGuid().ToString("N"))
    $stdoutPath = Join-Path $runRoot ($runId + ".stdout.log")
    $stderrPath = Join-Path $runRoot ($runId + ".stderr.log")
    $engineLogPath = Join-Path $runRoot ($runId + ".godot.log")

    $arguments = @()
    if (-not $Windowed) {
        $arguments += "--headless"
    }
    $arguments += @(
        "--path", $projectRoot,
        "--log-file", $engineLogPath,
        "--script", $resourceSuite
    )
    if ($UserArgs.Count -gt 0) {
        $arguments += "--"
        $arguments += $UserArgs
    }

    # Windows PowerShell 5.1's Start-Process crashes before launch when the
    # inherited environment contains both `Path` and `PATH` (the Codex desktop
    # host does). ProcessStartInfo avoids that broken dictionary merge.
    $quotedArguments = $arguments | ForEach-Object {
        '"' + ([string]$_).Replace('"', '\"') + '"'
    }
    $processInfo = [Diagnostics.ProcessStartInfo]::new()
    $processInfo.FileName = $Godot
    $processInfo.Arguments = $quotedArguments -join " "
    $processInfo.WorkingDirectory = $projectRoot
    $processInfo.UseShellExecute = $false
    $processInfo.CreateNoWindow = -not $Windowed
    $processInfo.RedirectStandardOutput = $true
    $processInfo.RedirectStandardError = $true
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $processInfo
    if (-not $process.Start()) {
        throw "Godot process did not start"
    }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    $verdictAt = $null
    $killedAfterVerdict = $false
    $timedOut = $false
    $successPattern = "(?im)(PASSED|tests passed|:\s*PASS\s*$|WRITTEN)"

    while (-not $process.HasExited) {
        Start-Sleep -Milliseconds 200
        $process.Refresh()

        $outputSoFar = ""
        if (Test-Path -LiteralPath $engineLogPath) {
            $outputSoFar = Read-SharedText -Path $engineLogPath
        }
        if ($null -eq $verdictAt -and $outputSoFar -match $successPattern) {
            $verdictAt = [DateTime]::UtcNow
        }

        # A suite prints its final verdict immediately before quit(). If the
        # process is still alive five seconds later it is hanging in engine
        # teardown — the exact state that used to trigger four JIT windows.
        if ($null -ne $verdictAt -and [DateTime]::UtcNow -gt $verdictAt.AddSeconds(5)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $killedAfterVerdict = $true
            break
        }
        if ([DateTime]::UtcNow -gt $deadline) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $timedOut = $true
            break
        }
    }
    $process.WaitForExit()

    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    [IO.File]::WriteAllText($stdoutPath, $stdout)
    [IO.File]::WriteAllText($stderrPath, $stderr)
    $engineOutput = if (Test-Path -LiteralPath $engineLogPath) {
        Read-SharedText -Path $engineLogPath
    } else {
        ""
    }
    $combined = $stdout + [Environment]::NewLine + $stderr + [Environment]::NewLine + $engineOutput
    $displayOutput = ($stdout + [Environment]::NewLine + $stderr).Trim()
    if ([string]::IsNullOrWhiteSpace($displayOutput)) {
        $displayOutput = $engineOutput.Trim()
    }
    Write-Output $displayOutput

    if ($timedOut) {
        Write-Error "Godot suite exceeded ${TimeoutSeconds}s and was terminated. Logs: $runRoot"
        exit 124
    }
    if ($killedAfterVerdict) {
        Write-Error "Godot printed a verdict but hung during shutdown and was terminated. Logs: $runRoot"
        exit 125
    }
    if ($process.ExitCode -ne 0) {
        Write-Error "Godot exited with code $($process.ExitCode). Logs: $runRoot"
        exit $process.ExitCode
    }
    if ($combined -notmatch $successPattern) {
        Write-Error "The suite exited without a success verdict. Logs: $runRoot"
        exit 1
    }
}
finally {
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
    }
    if ($hasMutex) {
        $mutex.ReleaseMutex()
    }
    $mutex.Dispose()
}

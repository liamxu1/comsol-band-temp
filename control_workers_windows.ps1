param(
    [string]$OutputDir = "output",
    [ValidateSet("status", "stop")]
    [string]$Action = "status"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $resolvedOutputDir = $OutputDir
} else {
    $resolvedOutputDir = Join-Path $scriptDir $OutputDir
}

$configFile = Join-Path $resolvedOutputDir "batch_config.mat"

function Get-ResolvedBatchProcesses {
    param(
        [string]$ConfigFile
    )

    $allProcesses = @(Get-CimInstance Win32_Process)
    $workerProcesses = @(
        $allProcesses | Where-Object {
            $_.CommandLine -and $_.CommandLine -like "*run_band_dataset_worker('$ConfigFile')*"
        }
    )

    $seen = @{}
    $queue = New-Object System.Collections.Queue

    foreach ($proc in $workerProcesses) {
        $pid = [int]$proc.ProcessId
        if (-not $seen.ContainsKey($pid)) {
            $seen[$pid] = $proc
            $queue.Enqueue($pid)
        }
    }

    $descendantProcesses = @()
    while ($queue.Count -gt 0) {
        $parentPid = $queue.Dequeue()
        $children = @($allProcesses | Where-Object { $_.ParentProcessId -eq $parentPid })
        foreach ($child in $children) {
            $childPid = [int]$child.ProcessId
            if (-not $seen.ContainsKey($childPid)) {
                $seen[$childPid] = $child
                $descendantProcesses += $child
                $queue.Enqueue($childPid)
            }
        }
    }

    [pscustomobject]@{
        Workers     = $workerProcesses
        Descendants = $descendantProcesses
    }
}

function Write-ProcessGroup {
    param(
        [string]$Title,
        [object[]]$Processes
    )

    Write-Host "${Title}:"
    if (-not $Processes -or $Processes.Count -eq 0) {
        Write-Host "  <none>"
        return
    }

    $Processes |
        Sort-Object ProcessId |
        Select-Object ProcessId, ParentProcessId, Name, CreationDate, CommandLine |
        Format-Table -AutoSize
}

function Stop-ProcessTree {
    param(
        [object[]]$Processes
    )

    if (-not $Processes -or $Processes.Count -eq 0) {
        return
    }

    $Processes |
        Sort-Object ProcessId -Descending |
        ForEach-Object {
            $procId = [int]$_.ProcessId
            try {
                Stop-Process -Id $procId -Force -ErrorAction Stop
                Write-Host "Stopped PID=$procId Name=$($_.Name)"
            } catch {
                Write-Warning "Failed to stop PID=$procId Name=$($_.Name): $($_.Exception.Message)"
            }
        }
}

$processInfo = Get-ResolvedBatchProcesses -ConfigFile $configFile

switch ($Action) {
    "status" {
        Write-ProcessGroup -Title "MATLAB worker processes" -Processes $processInfo.Workers
        Write-ProcessGroup -Title "Worker child processes (includes COMSOL server descendants)" -Processes $processInfo.Descendants
    }
    "stop" {
        Stop-ProcessTree -Processes $processInfo.Descendants
        Stop-ProcessTree -Processes $processInfo.Workers
        Write-Host "Sent stop requests to matching MATLAB workers and child processes."
        Write-Host "If some cases remain locked after stop, run cleanup_portable_batch_windows.ps1."
    }
}

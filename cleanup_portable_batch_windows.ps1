param(
    [string]$OutputDir = "output"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $resolvedOutputDir = $OutputDir
} else {
    $resolvedOutputDir = Join-Path $scriptDir $OutputDir
}

$configFile = Join-Path $resolvedOutputDir "batch_config.mat"
$lockNames = @(".lock", ".batch_summary.lock", ".comsol_server_start.lock")

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

    $allMatched = @()
    while ($queue.Count -gt 0) {
        $parentPid = $queue.Dequeue()
        $children = @($allProcesses | Where-Object { $_.ParentProcessId -eq $parentPid })
        foreach ($child in $children) {
            $childPid = [int]$child.ProcessId
            if (-not $seen.ContainsKey($childPid)) {
                $seen[$childPid] = $child
                $allMatched += $child
                $queue.Enqueue($childPid)
            }
        }
    }

    @($allMatched + $workerProcesses | Sort-Object ProcessId -Unique)
}

function Stop-ProcessTree {
    param(
        [object[]]$Processes
    )

    if (-not $Processes -or $Processes.Count -eq 0) {
        Write-Host "No batch worker or child processes found for $resolvedOutputDir"
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

if (-not (Test-Path -LiteralPath $resolvedOutputDir -PathType Container)) {
    Write-Host "Output directory does not exist: $resolvedOutputDir"
} else {
    Write-Host "Removing lock directories under $resolvedOutputDir"
    Get-ChildItem -LiteralPath $resolvedOutputDir -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $lockNames -contains $_.Name } |
        ForEach-Object {
            Write-Host $_.FullName
            Remove-Item -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
}

$processes = Get-ResolvedBatchProcesses -ConfigFile $configFile
Stop-ProcessTree -Processes $processes

Write-Host "Cleanup finished."

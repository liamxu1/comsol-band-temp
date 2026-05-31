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

function Get-RegisteredWorkerPids {
    param(
        [string]$ResolvedOutputDir
    )

    $pids = New-Object System.Collections.Generic.List[int]
    $registryDir = Join-Path $ResolvedOutputDir ".worker_pids"
    if (Test-Path -LiteralPath $registryDir -PathType Container) {
        Get-ChildItem -LiteralPath $registryDir -File -Filter "*.pid" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $content = Get-Content -LiteralPath $_.FullName -ErrorAction SilentlyContinue
                foreach ($line in $content) {
                    if ($line -match "^pid=(\d+)$") {
                        [void]$pids.Add([int]$matches[1])
                    }
                }
            }
    }

    @($pids | Sort-Object -Unique)
}

function Get-LockClaimWorkerPids {
    param(
        [string]$ResolvedOutputDir
    )

    $pids = New-Object System.Collections.Generic.List[int]
    Get-ChildItem -LiteralPath $ResolvedOutputDir -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -eq ".lock" } |
        ForEach-Object {
            $claimFile = Join-Path $_.FullName "claim.txt"
            if (Test-Path -LiteralPath $claimFile -PathType Leaf) {
                $content = Get-Content -LiteralPath $claimFile -ErrorAction SilentlyContinue
                foreach ($line in $content) {
                    if ($line -match "^worker=(\d+)$") {
                        [void]$pids.Add([int]$matches[1])
                    }
                }
            }
        }

    @($pids | Sort-Object -Unique)
}

function Get-WorkerProcessesByPid {
    param(
        [object[]]$AllProcesses,
        [int[]]$Pids
    )

    $matched = @()
    foreach ($targetPid in $Pids) {
        $matched += @($AllProcesses | Where-Object { $_.ProcessId -eq $targetPid })
    }
    @($matched | Sort-Object ProcessId -Unique)
}

function Get-WorkerProcessesByMatch {
    param(
        [object[]]$AllProcesses,
        [string]$ConfigFile,
        [string]$ResolvedOutputDir
    )

    @(
        $AllProcesses | Where-Object {
            Test-WorkerProcessMatch -Process $_ -ConfigFile $ConfigFile -ResolvedOutputDir $ResolvedOutputDir
        }
    )
}

function Normalize-MatchText {
    param(
        [AllowNull()]
        [string]$Text
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return ""
    }

    return $Text.ToLowerInvariant().Replace("/", "\")
}

function Test-WorkerProcessMatch {
    param(
        [object]$Process,
        [string]$ConfigFile,
        [string]$ResolvedOutputDir
    )

    $commandLine = Normalize-MatchText $Process.CommandLine
    if ([string]::IsNullOrEmpty($commandLine)) {
        return $false
    }

    $normalizedConfig = Normalize-MatchText $ConfigFile
    $normalizedOutputDir = Normalize-MatchText $ResolvedOutputDir
    $configFileName = [System.IO.Path]::GetFileName($ConfigFile).ToLowerInvariant()
    $processName = ($Process.Name | ForEach-Object { $_.ToLowerInvariant() })

    if ($commandLine.Contains("run_band_dataset_worker(") -and $commandLine.Contains($normalizedConfig)) {
        return $true
    }
    if ($commandLine.Contains("run_band_dataset_worker(") -and $commandLine.Contains($normalizedOutputDir)) {
        return $true
    }
    if ($commandLine.Contains("launch_worker_") -and $commandLine.Contains($normalizedOutputDir)) {
        return $true
    }
    if ($processName -eq "matlab.exe" -and $commandLine.Contains($configFileName) -and $commandLine.Contains($normalizedOutputDir)) {
        return $true
    }

    return $false
}

function Get-ResolvedBatchProcesses {
    param(
        [string]$ConfigFile,
        [string]$ResolvedOutputDir
    )

    $allProcesses = @(Get-CimInstance Win32_Process)
    $registeredPids = @(Get-RegisteredWorkerPids -ResolvedOutputDir $ResolvedOutputDir)
    $matchedWorkerProcesses = @(Get-WorkerProcessesByPid -AllProcesses $allProcesses -Pids $registeredPids)
    $matchedWorkerProcesses += @(Get-WorkerProcessesByMatch -AllProcesses $allProcesses -ConfigFile $ConfigFile -ResolvedOutputDir $ResolvedOutputDir)
    $workerProcesses = @($matchedWorkerProcesses | Sort-Object ProcessId -Unique)

    $lockClaimPids = @()
    if ($workerProcesses.Count -eq 0) {
        $lockClaimPids = @(Get-LockClaimWorkerPids -ResolvedOutputDir $ResolvedOutputDir)
        $workerProcesses = @(Get-WorkerProcessesByPid -AllProcesses $allProcesses -Pids $lockClaimPids)
    }

    $seen = @{}
    $queue = New-Object System.Collections.Queue

    foreach ($proc in $workerProcesses) {
        $procPid = [int]$proc.ProcessId
        if (-not $seen.ContainsKey($procPid)) {
            $seen[$procPid] = $proc
            $queue.Enqueue($procPid)
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
        LockClaimPids = $lockClaimPids
        RegisteredPids = $registeredPids
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

$processInfo = Get-ResolvedBatchProcesses -ConfigFile $configFile -ResolvedOutputDir $resolvedOutputDir

switch ($Action) {
    "status" {
        Write-Host ("Registered worker PIDs: {0}" -f ($(if ($processInfo.RegisteredPids.Count -gt 0) { $processInfo.RegisteredPids -join ", " } else { "<none>" })))
        if ($processInfo.LockClaimPids.Count -gt 0) {
            Write-Host ("Fallback lock claim PIDs: {0}" -f ($processInfo.LockClaimPids -join ", "))
        }
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

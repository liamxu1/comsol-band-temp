param(
    [string]$OutputDir = "output"
)

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
if ([System.IO.Path]::IsPathRooted($OutputDir)) {
    $resolvedOutputDir = $OutputDir
} else {
    $resolvedOutputDir = Join-Path $scriptDir $OutputDir
}

if (-not (Test-Path -LiteralPath $resolvedOutputDir -PathType Container)) {
    Write-Error "Output directory does not exist: $resolvedOutputDir"
    exit 1
}

function Escape-CsvField {
    param([AllowNull()][string]$Value)

    if ($null -eq $Value) {
        $Value = ""
    }
    $Value = $Value.Replace('"', '""')
    return '"' + $Value + '"'
}

Write-Output '"case_id","attempt_count","failure_kind","worker_exit_reason","message"'

$doneFiles = Get-ChildItem -LiteralPath $resolvedOutputDir -Recurse -Force -File -Filter ".done" |
    Sort-Object FullName

foreach ($doneFile in $doneFiles) {
    $caseDir = Split-Path -Parent $doneFile.FullName
    $caseId = Split-Path -Leaf $caseDir
    $status = ""
    $attemptCount = ""
    $failureKind = ""
    $workerExitReason = ""
    $message = ""

    $lines = Get-Content -LiteralPath $doneFile.FullName -ErrorAction SilentlyContinue
    foreach ($line in $lines) {
        if ($line -notmatch '^([^=]+)=(.*)$') {
            continue
        }
        $key = $matches[1]
        $value = $matches[2]
        switch ($key) {
            'status' { $status = $value }
            'attempt_count' { $attemptCount = $value }
            'failure_kind' { $failureKind = $value }
            'worker_exit_reason' { $workerExitReason = $value }
            'message' { $message = $value }
        }
    }

    if ($status -ne 'error') {
        continue
    }

    $row = @(
        Escape-CsvField $caseId
        Escape-CsvField $attemptCount
        Escape-CsvField $failureKind
        Escape-CsvField $workerExitReason
        Escape-CsvField $message
    ) -join ','
    Write-Output $row
}

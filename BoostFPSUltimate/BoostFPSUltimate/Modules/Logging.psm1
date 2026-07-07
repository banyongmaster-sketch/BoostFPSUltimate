<#
.SYNOPSIS
    Logging.psm1 - Central logging module for Boost FPS Ultimate
.DESCRIPTION
    Every other module calls Write-BFULog instead of Write-Host directly,
    so every action (Success / Failed / Skipped / Warning) is recorded to
    both the console and a persistent log file.
#>

$Script:LogPath = $null

function Initialize-BFULogging {
    param(
        [string]$LogFolder = "$PSScriptRoot\..\Logs"
    )
    if (-not (Test-Path $LogFolder)) {
        New-Item -Path $LogFolder -ItemType Directory -Force | Out-Null
    }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $Script:LogPath = Join-Path $LogFolder "BoostFPS_$timestamp.log"
    "==== Boost FPS Ultimate Log started $(Get-Date) ====" | Out-File -FilePath $Script:LogPath -Encoding UTF8
    return $Script:LogPath
}

function Write-BFULog {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet("INFO","SUCCESS","FAILED","SKIPPED","WARNING")]
        [string]$Level = "INFO"
    )

    $color = switch ($Level) {
        "SUCCESS" { "Green" }
        "FAILED"  { "Red" }
        "SKIPPED" { "DarkYellow" }
        "WARNING" { "Yellow" }
        default   { "Gray" }
    }

    $line = "[{0}] [{1}] {2}" -f (Get-Date -Format "HH:mm:ss"), $Level, $Message
    Write-Host $line -ForegroundColor $color

    if ($Script:LogPath) {
        $line | Out-File -FilePath $Script:LogPath -Append -Encoding UTF8
    }
}

function Invoke-BFUSafe {
    <#
    .SYNOPSIS
        Wraps any scriptblock in try/catch and logs the result automatically.
        This is the standard pattern every optimization function should use.
    #>
    param(
        [Parameter(Mandatory)][string]$ActionName,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    try {
        & $Action
        Write-BFULog -Message "$ActionName - OK" -Level SUCCESS
        return $true
    }
    catch {
        Write-BFULog -Message "$ActionName - FAILED: $($_.Exception.Message)" -Level FAILED
        return $false
    }
}

Export-ModuleMember -Function Initialize-BFULogging, Write-BFULog, Invoke-BFUSafe

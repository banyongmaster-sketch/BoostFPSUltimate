#Requires -Version 5.1
<#
.SYNOPSIS
    Boost FPS Ultimate - main entry point
.DESCRIPTION
    Interactive menu that ties every module together:
    1. Detect hardware/network
    2. Create restore point + backups
    3. Run pre-optimization benchmark
    4. Apply a profile (Esports / Balanced / Battery / Custom)
    5. Run post-optimization benchmark and show delta
    6. Offer rollback

    Run this as Administrator. Most optimization functions will fail
    (and log FAILED, not crash the whole script) without elevation.
#>

param(
    [ValidateSet("Esports","Balanced","Battery")]
    [string]$Profile = $null,
    [switch]$Unattended
)

$here = $PSScriptRoot
Import-Module "$here\Modules\Logging.psm1" -Force
Import-Module "$here\Modules\HardwareInfo.psm1" -Force
Import-Module "$here\Modules\NetworkInfo.psm1" -Force
Import-Module "$here\Modules\RestoreBackup.psm1" -Force
Import-Module "$here\Modules\CPUOptimize.psm1" -Force
Import-Module "$here\Modules\GPUOptimize.psm1" -Force
Import-Module "$here\Modules\MemoryStorageOptimize.psm1" -Force
Import-Module "$here\Modules\NetworkOptimize.psm1" -Force
Import-Module "$here\Modules\WindowsOptimize.psm1" -Force
Import-Module "$here\Modules\Benchmark.psm1" -Force

$logPath = Initialize-BFULogging
Write-Host @"
============================================
   Boost FPS Ultimate v1.0.0
   Log file: $logPath
============================================
"@ -ForegroundColor Cyan

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
if (-not $isAdmin) {
    Write-BFULog -Message "Not running as Administrator - most optimizations will be skipped/fail. Right-click PowerShell > Run as Administrator and re-run." -Level WARNING
}

function Show-BFUMenu {
    Write-Host "`n1) Show hardware + network report"
    Write-Host "2) Create restore point + backup current settings"
    Write-Host "3) Run benchmark only"
    Write-Host "4) Apply optimization profile (Esports / Balanced / Battery)"
    Write-Host "5) Rollback last registry backups"
    Write-Host "6) Exit"
}

function Invoke-BFUProfile {
    param([string]$ProfileName)

    $profilePath = "$here\Profiles\$ProfileName.json"
    if (-not (Test-Path $profilePath)) {
        Write-BFULog -Message "Profile '$ProfileName' not found" -Level FAILED
        return
    }
    $cfg = Get-Content $profilePath -Raw | ConvertFrom-Json
    Write-BFULog -Message "Applying profile: $($cfg.ProfileName) - $($cfg.Description) [Risk: $($cfg.RiskLevel)]" -Level INFO

    # Safety net first, always
    New-BFURestorePoint -Description "BoostFPS - before $($cfg.ProfileName) profile" | Out-Null
    Export-BFUCurrentSettings | Out-Null

    $before = Invoke-BFUBenchmark -Label "Before-$($cfg.ProfileName)"

    Invoke-BFUCPUOptimize -RiskLevel $cfg.RiskLevel
    Invoke-BFUGPUOptimize -RiskLevel $cfg.RiskLevel
    Invoke-BFUMemoryStorageOptimize -RiskLevel $cfg.RiskLevel
    Invoke-BFUNetworkOptimize -RiskLevel $cfg.RiskLevel
    Invoke-BFUWindowsOptimize -RiskLevel $cfg.RiskLevel

    $after = Invoke-BFUBenchmark -Label "After-$($cfg.ProfileName)"
    $delta = Compare-BFUBenchmarks -Before $before -After $after

    Write-Host "`n=== Result ===" -ForegroundColor Cyan
    $delta | Format-List
    Write-BFULog -Message "Profile '$($cfg.ProfileName)' applied. See summary above. Some settings (HAGS) need a reboot to take effect." -Level SUCCESS
}

if ($Unattended -and $Profile) {
    Invoke-BFUProfile -ProfileName $Profile
    return
}

$exit = $false
while (-not $exit) {
    Show-BFUMenu
    $choice = Read-Host "`nEnter choice (1-6)"
    switch ($choice) {
        "1" { Get-BFUFullReport | Format-List; Get-BFUNetworkFullReport | Format-List }
        "2" { New-BFURestorePoint | Out-Null; Export-BFUCurrentSettings | Out-Null }
        "3" { Invoke-BFUBenchmark -Label "Manual" | Format-List }
        "4" {
            $p = Read-Host "Profile name (Esports / Balanced / Battery)"
            Invoke-BFUProfile -ProfileName $p
        }
        "5" {
            $backups = Get-BFUAvailableBackups
            if (-not $backups) { Write-Host "No backups found." -ForegroundColor Yellow }
            else {
                $backups | Select-Object -First 10 | ForEach-Object -Begin { $i = 0 } -Process { Write-Host "[$i] $($_.Name)"; $i++ }
                $sel = Read-Host "Enter index to restore"
                Restore-BFURegistryBackup -RegFilePath $backups[$sel].FullName
            }
        }
        "6" { $exit = $true }
        default { Write-Host "Invalid choice" -ForegroundColor Red }
    }
}

<#
.SYNOPSIS
    RestoreBackup.psm1 - Safety net: restore points, registry backups, rollback
.DESCRIPTION
    This module MUST be run before any optimization module touches the
    system. It creates a real System Restore checkpoint and exports the
    actual registry keys that will be modified, so every change can be
    reversed with Restore-BFUSettings.
#>

$Script:BackupRoot = "$PSScriptRoot\..\Backups"

function New-BFURestorePoint {
    param([string]$Description = "Boost FPS Ultimate - Pre-Optimization")
    try {
        # System Restore must be enabled on the target volume for this to work.
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description $Description -RestorePointType "MODIFY_SETTINGS"
        Write-BFULog -Message "System Restore Point created: $Description" -Level SUCCESS
        return $true
    } catch {
        Write-BFULog -Message "Could not create Restore Point: $($_.Exception.Message). Continuing, but you have no OS-level rollback." -Level WARNING
        return $false
    }
}

function Backup-BFURegistryKey {
    <#
    .SYNOPSIS
        Exports a registry key to a .reg file before it's modified.
    #>
    param(
        [Parameter(Mandatory)][string]$KeyPath,   # e.g. "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
        [Parameter(Mandatory)][string]$Tag        # short label e.g. "GraphicsDrivers"
    )
    if (-not (Test-Path $Script:BackupRoot)) { New-Item -Path $Script:BackupRoot -ItemType Directory -Force | Out-Null }
    $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $file = Join-Path $Script:BackupRoot "$Tag`_$timestamp.reg"
    reg export $KeyPath $file /y *> $null
    if (Test-Path $file) {
        Write-BFULog -Message "Backed up registry key '$KeyPath' -> $file" -Level SUCCESS
        return $file
    } else {
        Write-BFULog -Message "Failed to back up '$KeyPath' (key may not exist yet, which is fine)" -Level SKIPPED
        return $null
    }
}

function Export-BFUCurrentSettings {
    <#
    .SYNOPSIS
        Snapshots the current power plan + key network settings to JSON
        so Restore-BFUSettings can put them back.
    #>
    $snapshot = [ordered]@{
        Timestamp   = Get-Date -Format "o"
        PowerPlan   = (powercfg /getactivescheme)
        TcpGlobal   = (netsh int tcp show global)
    }
    if (-not (Test-Path $Script:BackupRoot)) { New-Item -Path $Script:BackupRoot -ItemType Directory -Force | Out-Null }
    $path = Join-Path $Script:BackupRoot "settings_snapshot_$(Get-Date -Format 'yyyyMMdd_HHmmss').json"
    $snapshot | ConvertTo-Json -Depth 5 | Out-File -FilePath $path -Encoding UTF8
    Write-BFULog -Message "Settings snapshot saved to $path" -Level SUCCESS
    return $path
}

function Restore-BFURegistryBackup {
    param([Parameter(Mandatory)][string]$RegFilePath)
    if (-not (Test-Path $RegFilePath)) {
        Write-BFULog -Message "Backup file not found: $RegFilePath" -Level FAILED
        return $false
    }
    reg import $RegFilePath *> $null
    Write-BFULog -Message "Restored registry from $RegFilePath" -Level SUCCESS
    return $true
}

function Get-BFUAvailableBackups {
    if (-not (Test-Path $Script:BackupRoot)) { return @() }
    Get-ChildItem -Path $Script:BackupRoot -Filter "*.reg" | Sort-Object LastWriteTime -Descending
}

Export-ModuleMember -Function New-BFURestorePoint, Backup-BFURegistryKey, Export-BFUCurrentSettings, `
    Restore-BFURegistryBackup, Get-BFUAvailableBackups

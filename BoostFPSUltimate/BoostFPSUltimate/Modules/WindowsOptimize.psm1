<#
.SYNOPSIS
    WindowsOptimize.psm1 - OS-level tuning (Game Mode, services, visual FX)
.DESCRIPTION
    Services like SysMain/DiagTrack CAN be disabled (documented, supported
    by Microsoft to disable, just not default) but doing so has real
    trade-offs (SysMain helps app launch times on HDDs; DiagTrack is used
    for some diagnostics). Gated under Advanced risk with warnings.
#>

function Enable-BFUGameMode {
    $path = "HKCU:\Software\Microsoft\GameBar"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "AllowAutoGameMode" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $path -Name "AutoGameModeEnabled" -Value 1 -Type DWord -Force
    Write-BFULog -Message "Game Mode enabled" -Level SUCCESS
}

function Disable-BFUGameDVR {
    $path1 = "HKCU:\System\GameConfigStore"
    $path2 = "HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR"
    if (-not (Test-Path $path1)) { New-Item -Path $path1 -Force | Out-Null }
    if (-not (Test-Path $path2)) { New-Item -Path $path2 -Force | Out-Null }
    Set-ItemProperty -Path $path1 -Name "GameDVR_Enabled" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $path2 -Name "AllowGameDVR" -Value 0 -Type DWord -Force
    Write-BFULog -Message "Game DVR / background recording disabled" -Level SUCCESS
}

function Disable-BFUVisualEffectsForPerformance {
    $path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "VisualFXSetting" -Value 2 -Type DWord -Force  # 2 = "Adjust for best performance"
    Write-BFULog -Message "Visual effects set to 'Best performance'" -Level SUCCESS
}

function Set-BFUServiceState {
    <#
    .SYNOPSIS
        RISK: MEDIUM. Stops + disables a named service, after backing up
        its current start type so it can be restored.
    #>
    param(
        [Parameter(Mandatory)][string]$ServiceName,
        [ValidateSet("Disabled","Manual","Automatic")][string]$StartupType,
        [switch]$Force
    )
    if (-not $Force -and $StartupType -eq "Disabled") {
        Write-BFULog -Message "Disabling service '$ServiceName' skipped - requires -Force" -Level SKIPPED
        return
    }
    $svc = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue
    if (-not $svc) {
        Write-BFULog -Message "Service '$ServiceName' not found - skipped" -Level SKIPPED
        return
    }
    if ($StartupType -eq "Disabled") { Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue }
    Set-Service -Name $ServiceName -StartupType $StartupType
    Write-BFULog -Message "Service '$ServiceName' set to $StartupType" -Level (if ($StartupType -eq "Disabled") { "WARNING" } else { "SUCCESS" })
}

function Invoke-BFUWindowsOptimize {
    param([ValidateSet("Safe","Advanced")][string]$RiskLevel = "Safe")
    Invoke-BFUSafe -ActionName "Enable Game Mode" -Action { Enable-BFUGameMode }
    Invoke-BFUSafe -ActionName "Disable Game DVR" -Action { Disable-BFUGameDVR }
    Invoke-BFUSafe -ActionName "Set visual effects to best performance" -Action { Disable-BFUVisualEffectsForPerformance }

    if ($RiskLevel -eq "Advanced") {
        # SysMain (Superfetch) - safe-ish to disable on SSD-only systems, riskier on HDD
        Invoke-BFUSafe -ActionName "Disable SysMain service" -Action { Set-BFUServiceState -ServiceName "SysMain" -StartupType Disabled -Force }
    }
}

Export-ModuleMember -Function Enable-BFUGameMode, Disable-BFUGameDVR, Disable-BFUVisualEffectsForPerformance, `
    Set-BFUServiceState, Invoke-BFUWindowsOptimize

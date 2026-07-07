<#
.SYNOPSIS
    GPUOptimize.psm1 - GPU scheduling and presentation tuning
.DESCRIPTION
    Uses documented registry values (HAGS, GPU preference, Fullscreen
    Optimizations) that Microsoft publishes in its own support docs.
    Does NOT touch vendor-specific driver internals (NVIDIA/AMD control
    panel settings aren't exposed via public registry keys, so we don't
    fabricate those).
#>

function Enable-BFUHags {
    <#
    .SYNOPSIS
        Enables Hardware-accelerated GPU Scheduling.
        Documented key: HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers\HwSchMode
        Requires reboot to take effect. Requires WDDM 2.7+ driver.
    #>
    $path = "HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers"
    Backup-BFURegistryKey -KeyPath "HKLM\SYSTEM\CurrentControlSet\Control\GraphicsDrivers" -Tag "GraphicsDrivers" | Out-Null
    Set-ItemProperty -Path $path -Name "HwSchMode" -Value 2 -Type DWord -Force
    Write-BFULog -Message "HAGS enabled (reboot required)" -Level SUCCESS
}

function Disable-BFUFullscreenOptimizations {
    <#
    .SYNOPSIS
        Disables Fullscreen Optimizations globally for the current user.
        Documented key: HKCU\System\GameConfigStore
    #>
    $path = "HKCU:\System\GameConfigStore"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name "GameDVR_FSEBehaviorMode" -Value 2 -Type DWord -Force
    Set-ItemProperty -Path $path -Name "GameDVR_DXGIHonorFSEWindowsCompatible" -Value 1 -Type DWord -Force
    Write-BFULog -Message "Fullscreen Optimizations disabled (lower latency, may reduce Alt-Tab speed)" -Level SUCCESS
}

function Set-BFUGpuPreferenceHighPerformance {
    <#
    .SYNOPSIS
        Sets "High performance" GPU preference for a given executable via
        the documented per-app GPU preference key.
    #>
    param([Parameter(Mandatory)][string]$ExePath)
    $path = "HKCU:\Software\Microsoft\DirectX\UserGpuPreferences"
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    Set-ItemProperty -Path $path -Name $ExePath -Value "GpuPreference=2;" -Type String -Force
    Write-BFULog -Message "Set high-performance GPU preference for $ExePath" -Level SUCCESS
}

function Invoke-BFUGPUOptimize {
    param(
        [ValidateSet("Safe","Advanced")]
        [string]$RiskLevel = "Safe",
        [string[]]$GameExePaths = @()
    )
    Invoke-BFUSafe -ActionName "Enable HAGS" -Action { Enable-BFUHags }
    Invoke-BFUSafe -ActionName "Disable Fullscreen Optimizations" -Action { Disable-BFUFullscreenOptimizations }

    foreach ($exe in $GameExePaths) {
        Invoke-BFUSafe -ActionName "Set GPU preference for $exe" -Action { Set-BFUGpuPreferenceHighPerformance -ExePath $exe }
    }
}

Export-ModuleMember -Function Enable-BFUHags, Disable-BFUFullscreenOptimizations, Set-BFUGpuPreferenceHighPerformance, Invoke-BFUGPUOptimize

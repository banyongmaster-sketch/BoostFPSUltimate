<#
.SYNOPSIS
    CPUOptimize.psm1 - CPU scheduling / power plan tuning
.DESCRIPTION
    Uses powercfg (documented Microsoft tool) exclusively for CPU power
    behavior. No undocumented registry hacks for core parking - the only
    supported way to control it is via the "Processor performance core
    parking" powercfg setting, which we use here.
#>

# GUID for the built-in "High performance" power plan (constant on all Windows installs)
$Script:HighPerfGUID = "8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c"
$Script:UltimatePerfGUID = "e9a42b02-d5df-448d-aa00-03f14749eb61"  # Windows 10 1809+/Windows 11

function Set-BFUPowerPlan {
    param(
        [ValidateSet("HighPerformance","UltimatePerformance","Balanced")]
        [string]$Plan = "HighPerformance"
    )
    switch ($Plan) {
        "HighPerformance" {
            powercfg /setactive $Script:HighPerfGUID 2>$null
            if ($LASTEXITCODE -ne 0) { powercfg /duplicatescheme $Script:HighPerfGUID | Out-Null; powercfg /setactive $Script:HighPerfGUID }
        }
        "UltimatePerformance" {
            $exists = powercfg /list | Select-String $Script:UltimatePerfGUID
            if (-not $exists) { powercfg /duplicatescheme $Script:UltimatePerfGUID | Out-Null }
            powercfg /setactive $Script:UltimatePerfGUID
        }
        "Balanced" {
            powercfg /setactive "381b4222-f694-41f0-9685-ff5bb260df2e"
        }
    }
}

function Set-BFUCoreParking {
    <#
    .SYNOPSIS
        Sets minimum processor state so cores don't park under load.
        Documented powercfg sub-setting: PROCTHROTTLEMIN
    #>
    param([int]$MinStatePct = 100)
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR PROCTHROTTLEMIN $MinStatePct
    powercfg /setactive SCHEME_CURRENT
}

function Disable-BFUCStates {
    <#
    .SYNOPSIS
        Reduces CPU idle-state (C-state) depth for lower input latency.
        RISK: HIGH - can increase power draw/heat noticeably. Gated behind -Force.
        Documented powercfg sub-setting: SUB_PROCESSOR / IDLESTATEMAXIMUM (0072e9d0-...)
    #>
    param([switch]$Force)
    if (-not $Force) {
        Write-BFULog -Message "Disable-BFUCStates skipped - requires -Force (high risk: heat/power draw)" -Level SKIPPED
        return
    }
    powercfg /setacvalueindex SCHEME_CURRENT SUB_PROCESSOR 0072e9d0-ba43-4363-8bc9-8f4c9b03f1e2 0
    powercfg /setactive SCHEME_CURRENT
    Write-BFULog -Message "C-States limited to shallow idle states (HIGH RISK setting applied)" -Level WARNING
}

function Invoke-BFUCPUOptimize {
    param(
        [ValidateSet("Safe","Advanced")]
        [string]$RiskLevel = "Safe"
    )
    Invoke-BFUSafe -ActionName "Set High Performance power plan" -Action { Set-BFUPowerPlan -Plan HighPerformance }
    Invoke-BFUSafe -ActionName "Disable core parking (min CPU state 100%)" -Action { Set-BFUCoreParking -MinStatePct 100 }

    if ($RiskLevel -eq "Advanced") {
        Write-BFULog -Message "Advanced risk level: applying C-State limiting" -Level WARNING
        Invoke-BFUSafe -ActionName "Limit CPU C-States" -Action { Disable-BFUCStates -Force }
    }
}

Export-ModuleMember -Function Set-BFUPowerPlan, Set-BFUCoreParking, Disable-BFUCStates, Invoke-BFUCPUOptimize

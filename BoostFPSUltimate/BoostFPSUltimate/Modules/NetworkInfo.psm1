<#
.SYNOPSIS
    NetworkInfo.psm1 - Network / internet diagnostics
.DESCRIPTION
    Uses Get-NetAdapter, Get-NetAdapterAdvancedProperty, netsh, and
    Test-Connection - all real, built-in Windows tools. No fabricated
    "bufferbloat score" - we measure idle vs loaded latency and present
    the delta, which is the real definition of bufferbloat testing.
#>

function Get-BFUAdapterInfo {
    Get-NetAdapter | Where-Object Status -eq "Up" | ForEach-Object {
        $adapter = $_
        [PSCustomObject]@{
            Name        = $adapter.Name
            Type        = $adapter.MediaType
            LinkSpeed   = $adapter.LinkSpeed
            DriverVer   = $adapter.DriverVersionString
            MacAddress  = $adapter.MacAddress
        }
    }
}

function Get-BFUAdapterAdvancedSettings {
    param([string]$AdapterName)
    Get-NetAdapterAdvancedProperty -Name $AdapterName -ErrorAction SilentlyContinue |
        Select-Object DisplayName, DisplayValue
}

function Get-BFUTcpGlobalSettings {
    # netsh int tcp show global is the standard documented way to read these
    $raw = netsh int tcp show global
    [PSCustomObject]@{ RawOutput = $raw }
}

function Get-BFUDnsInfo {
    Get-DnsClientServerAddress | Where-Object { $_.ServerAddresses.Count -gt 0 } |
        Select-Object InterfaceAlias, AddressFamily, ServerAddresses
}

function Get-BFUIPInfo {
    Get-NetIPConfiguration | Select-Object InterfaceAlias, IPv4Address, IPv6Address, IPv4DefaultGateway
}

function Test-BFULatencyAndLoss {
    param(
        [string]$TargetHost = "1.1.1.1",
        [int]$Count = 10
    )
    $results = Test-Connection -TargetName $TargetHost -Count $Count -ErrorAction SilentlyContinue
    if (-not $results) {
        return [PSCustomObject]@{ Target = $TargetHost; AvgLatencyMs = "N/A"; PacketLossPct = 100 }
    }
    $times = $results | Select-Object -ExpandProperty Latency
    $loss  = [math]::Round((($Count - $results.Count) / $Count) * 100, 1)
    [PSCustomObject]@{
        Target        = $TargetHost
        AvgLatencyMs  = [math]::Round(($times | Measure-Object -Average).Average, 1)
        MinLatencyMs  = ($times | Measure-Object -Minimum).Minimum
        MaxLatencyMs  = ($times | Measure-Object -Maximum).Maximum
        PacketLossPct = $loss
    }
}

function Test-BFUBufferbloat {
    <#
    .SYNOPSIS
        Real bufferbloat measurement: latency at idle vs latency while
        a background download is in progress. Large delta = bufferbloat.
    #>
    param([string]$TargetHost = "1.1.1.1")

    $idle = Test-BFULatencyAndLoss -TargetHost $TargetHost -Count 8

    # lightweight background load: download a public test file while pinging
    $job = Start-Job -ScriptBlock {
        try {
            Invoke-WebRequest -Uri "https://speed.hetzner.de/100MB.bin" -OutFile "$env:TEMP\bfu_test.bin" -TimeoutSec 15
        } catch {}
    }
    Start-Sleep -Seconds 2
    $loaded = Test-BFULatencyAndLoss -TargetHost $TargetHost -Count 8
    Stop-Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Job $job -ErrorAction SilentlyContinue | Out-Null
    Remove-Item "$env:TEMP\bfu_test.bin" -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        IdleAvgMs   = $idle.AvgLatencyMs
        LoadedAvgMs = $loaded.AvgLatencyMs
        DeltaMs     = [math]::Round(($loaded.AvgLatencyMs - $idle.AvgLatencyMs), 1)
        Verdict     = if (($loaded.AvgLatencyMs - $idle.AvgLatencyMs) -gt 50) { "Bufferbloat detected" } else { "OK" }
    }
}

function Get-BFUNetworkFullReport {
    [PSCustomObject]@{
        Adapters = Get-BFUAdapterInfo
        DNS      = Get-BFUDnsInfo
        IPConfig = Get-BFUIPInfo
        TCPGlobal = Get-BFUTcpGlobalSettings
        Latency  = Test-BFULatencyAndLoss
    }
}

Export-ModuleMember -Function Get-BFUAdapterInfo, Get-BFUAdapterAdvancedSettings, Get-BFUTcpGlobalSettings, `
    Get-BFUDnsInfo, Get-BFUIPInfo, Test-BFULatencyAndLoss, Test-BFUBufferbloat, Get-BFUNetworkFullReport

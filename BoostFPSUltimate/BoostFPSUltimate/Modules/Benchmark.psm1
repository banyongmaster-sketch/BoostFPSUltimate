<#
.SYNOPSIS
    Benchmark.psm1 - simple, real, repeatable before/after benchmarks
.DESCRIPTION
    These are lightweight, self-contained tests (no external benchmark
    suite bundled) so results are comparable pre/post optimization without
    needing internet access or third-party binaries. Not a substitute for
    3DMark/CapFrameX for real FPS numbers - labelled honestly as a system
    responsiveness indicator, not an "FPS score".
#>

function Measure-BFUCpuScore {
    <#
    .SYNOPSIS
        Single-threaded integer math workload, timed. Lower ms = faster.
    #>
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $sum = 0
    for ($i = 0; $i -lt 40000000; $i++) { $sum += $i % 7 }
    $sw.Stop()
    [PSCustomObject]@{ TestName = "CPU single-thread loop"; TimeMs = $sw.ElapsedMilliseconds }
}

function Measure-BFUDiskScore {
    param([string]$Drive = $env:SystemDrive)
    $testFile = Join-Path "$Drive\" "bfu_disktest.tmp"
    $data = New-Object byte[] (256MB)
    (New-Object Random).NextBytes($data)

    $swWrite = [System.Diagnostics.Stopwatch]::StartNew()
    [System.IO.File]::WriteAllBytes($testFile, $data)
    $swWrite.Stop()

    $swRead = [System.Diagnostics.Stopwatch]::StartNew()
    [System.IO.File]::ReadAllBytes($testFile) | Out-Null
    $swRead.Stop()

    Remove-Item $testFile -Force -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        WriteMBps = [math]::Round(256 / ($swWrite.ElapsedMilliseconds / 1000), 1)
        ReadMBps  = [math]::Round(256 / ($swRead.ElapsedMilliseconds / 1000), 1)
    }
}

function Invoke-BFUBenchmark {
    param([string]$Label = "Benchmark")
    Write-BFULog -Message "Running benchmark: $Label" -Level INFO
    [PSCustomObject]@{
        Label     = $Label
        Timestamp = Get-Date -Format "o"
        CPU       = Measure-BFUCpuScore
        Disk      = Measure-BFUDiskScore
        Network   = Test-BFULatencyAndLoss
    }
}

function Compare-BFUBenchmarks {
    param(
        [Parameter(Mandatory)]$Before,
        [Parameter(Mandatory)]$After
    )
    [PSCustomObject]@{
        CPU_ImprovementMs   = $Before.CPU.TimeMs - $After.CPU.TimeMs
        Disk_ReadDeltaMBps  = $After.Disk.ReadMBps - $Before.Disk.ReadMBps
        Disk_WriteDeltaMBps = $After.Disk.WriteMBps - $Before.Disk.WriteMBps
        Latency_DeltaMs     = $Before.Network.AvgLatencyMs - $After.Network.AvgLatencyMs
    }
}

Export-ModuleMember -Function Measure-BFUCpuScore, Measure-BFUDiskScore, Invoke-BFUBenchmark, Compare-BFUBenchmarks

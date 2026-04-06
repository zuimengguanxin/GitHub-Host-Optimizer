<#
.SYNOPSIS
    IP Test module
#>

function Test-IPSpeed {
    param(
        [Parameter(Mandatory=$true)]
        [string]$IP,
        [int]$TimeoutMs = 1000,
        [int]$RetryCount = 1
    )

    for ($attempt = 0; $attempt -le $RetryCount; $attempt++) {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

        try {
            $asyncResult = $tcp.BeginConnect($IP, 443, $null, $null)
            $success = $asyncResult.AsyncWaitHandle.WaitOne($TimeoutMs)

            if ($success) {
                $tcp.EndConnect($asyncResult)
                $stopwatch.Stop()
                $tcp.Close()
                return @{ Success = $true; Latency = $stopwatch.ElapsedMilliseconds }
            }
        } catch {}
        finally {
            if ($tcp.Connected) { $tcp.Close() }
            $stopwatch.Stop()
        }

        if ($attempt -lt $RetryCount) { Start-Sleep -Milliseconds 100 }
    }

    return @{ Success = $false; Latency = -1 }
}

function Select-BestIP {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$IPs,
        [int]$TimeoutMs = 1000,
        [int]$RetryCount = 1
    )

    $results = @()

    foreach ($ip in $IPs) {
        $testResult = Test-IPSpeed -IP $ip -TimeoutMs $TimeoutMs -RetryCount $RetryCount
        if ($testResult.Success) {
            $results += @{ IP = $ip; Latency = $testResult.Latency }
        }
    }

    if ($results.Count -eq 0) { return $null }

    return $results | Sort-Object Latency | Select-Object -First 1
}

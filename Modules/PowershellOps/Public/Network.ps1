# ── PUBLIC: NETWORK FUNCTIONS ──────────────────────────────────────────────

function Get-OpsNetCheck {
    <#
    .SYNOPSIS
    Tests internet connectivity by pinging 1.1.1.1.
    .OUTPUTS
    PSCustomObject with Internet boolean.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingComputerNameHardcoded', '')]
    [CmdletBinding()]
    param()
    [PSCustomObject]@{ Internet = (Test-Connection -ComputerName 1.1.1.1 -Count 1 -Quiet -ErrorAction SilentlyContinue) }
}

function Get-OpsWifi {
    <#
    .SYNOPSIS
    Returns Wi-Fi SSID and signal strength percentage.
    .OUTPUTS
    PSCustomObject with SSID and SignalPercent.
    #>
    [CmdletBinding()]
    param()
    $raw = netsh wlan show interfaces 2>$null | Out-String
    if (-not $raw) { return [PSCustomObject]@{ SSID = 'N/A'; Signal = 'N/A' } }
    $ssid = if ($raw -match 'SSID\s+:\s+(.+)') { $matches[1].Trim() } else { 'Disconnected' }
    $signal = if ($raw -match 'Signal\s+:\s+(\d+)%') { $matches[1] } else { '0' }
    [PSCustomObject]@{ SSID = $ssid; SignalPercent = $signal }
}

function Get-OpsEstablished {
    <#
    .SYNOPSIS
    Returns established TCP connections with remote address and process name.
    .OUTPUTS
    PSCustomObject with LocalPort, RemotePort, RemoteAddress, ProcessName, and State.
    #>
    [CmdletBinding()]
    param()
    if (-not (Get-Command Get-NetTCPConnection -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Connections = 'N/A - NetTCPConnection cmdlet unavailable' }
    }
    Get-NetTCPConnection -State Established -ErrorAction SilentlyContinue |
        Select-Object LocalPort, RemotePort, RemoteAddress, @{N='ProcessName';E={ (Get-Process -Id $_.OwningProcess -ErrorAction SilentlyContinue).ProcessName }}, State |
        Sort-Object RemoteAddress | Select-Object -First 20
}

function Get-OpsDnsBench {
    <#
    .SYNOPSIS
    Benchmarks DNS resolver response times for Cloudflare, Google, and Quad9.
    .OUTPUTS
    PSCustomObject with Resolver, Name, and SpeedMS.
    #>
    [CmdletBinding()]
    param()
    $resolvers = [ordered]@{ '1.1.1.1' = 'Cloudflare'; '8.8.8.8' = 'Google'; '9.9.9.9' = 'Quad9' }
    foreach ($server in $resolvers.Keys) {
        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $null = Resolve-DnsName -Name 'google.com' -Server $server -Type A -QuickTimeout -ErrorAction Stop
            $sw.Stop()
            [PSCustomObject]@{ Resolver = $server; Name = $resolvers[$server]; SpeedMS = $sw.ElapsedMilliseconds }
        } catch {
            [PSCustomObject]@{ Resolver = $server; Name = $resolvers[$server]; SpeedMS = 'TIMEOUT' }
        }
    }
}

function Get-OpsDnsCache {
    <#
    .SYNOPSIS
    Returns DNS client cache entries sorted by TTL.
    .OUTPUTS
    PSCustomObject with Entry, Type, TimeToLive, and DataLength.
    #>
    [CmdletBinding()]
    param()
    if (-not (Get-Command Get-DnsClientCache -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Entry = 'N/A'; Status = 'Cmdlet unavailable' }
    }
    Get-DnsClientCache -ErrorAction SilentlyContinue |
        Select-Object Entry, Type, TimeToLive, DataLength |
        Sort-Object TimeToLive | Select-Object -First 20
}

function Get-OpsLinkSpeed {
    <#
    .SYNOPSIS
    Returns network adapter link speed and MAC address.
    .OUTPUTS
    PSCustomObject with Name, LinkSpeed, InterfaceDescription, and MacAddress.
    #>
    [CmdletBinding()]
    param()
    if (-not (Get-Command Get-NetAdapter -ErrorAction SilentlyContinue)) {
        return [PSCustomObject]@{ Name = 'N/A'; LinkSpeed = 'N/A' }
    }
    Get-NetAdapter -ErrorAction SilentlyContinue | Where-Object Status -eq Up |
        Select-Object Name, @{N='LinkSpeed';E={$_.LinkSpeed}}, InterfaceDescription, MacAddress
}

function Get-OpsShare {
    <#
    .SYNOPSIS
    Returns SMB share names, paths, and descriptions.
    .OUTPUTS
    PSCustomObject with Name, Path, and Description.
    #>
    [CmdletBinding()]
    param()
    Get-CimInstance Win32_Share | Select-Object Name, Path, Description
}

function Get-OpsHostsCheck {
    <#
    .SYNOPSIS
    Parses the hosts file for custom IP-to-hostname mappings.
    .OUTPUTS
    PSCustomObject with IP and Hostname.
    #>
    [CmdletBinding()]
    param()
    Get-Content "$env:windir\system32\drivers\etc\hosts" -ErrorAction SilentlyContinue |
        Where-Object { $_ -match '^\s*[^#]' -and $_ -match '\S' } |
        ForEach-Object {
            $parts = $_ -split '\s+' | Where-Object { $_ }
            [PSCustomObject]@{ IP = $parts[0]; Hostname = $parts[1..($parts.Count-1)] -join ' ' }
        }
}

function Get-OpsNetworkTriage {
    <#
    .SYNOPSIS
    Returns network adapter IP addresses and MAC addresses.
    .OUTPUTS
    PSCustomObject with Description, IPAddress, and MACAddress.
    #>
    [CmdletBinding()]
    param()
    Get-CimInstance Win32_NetworkAdapterConfiguration -Filter "IPEnabled=True" | Select-Object Description, IPAddress, MACAddress
}

function Get-OpsNetwork {
    <#
    .SYNOPSIS
    Routes to a specific network diagnostic function by type.
    .OUTPUTS
    PSCustomObject from the selected diagnostic sub-function.
    #>
    [CmdletBinding()]
    param([ValidateSet('NetCheck','Wifi','DnsBench','LinkSpeed','Share','HostsCheck','DnsCache','Triage')][string]$Type = 'NetCheck')
    switch ($Type) {
        'NetCheck'   { Get-OpsNetCheck }
        'Wifi'       { Get-OpsWifi }
        'DnsBench'   { Get-OpsDnsBench }
        'LinkSpeed'  { Get-OpsLinkSpeed }
        'Share'      { Get-OpsShare }
        'HostsCheck' { Get-OpsHostsCheck }
        'DnsCache'   { Get-OpsDnsCache }
        'Triage'     { Get-OpsNetworkTriage }
    }
}

function Resolve-OpsDuckDuckGoHref {
    <#
    .SYNOPSIS
    Extracts the target URL from a DuckDuckGo redirect href.
    .OUTPUTS
    String URL or null.
    #>
    [CmdletBinding()]
    param([string]$Href)
    if (-not $Href) { return $null }
    if ($Href -match 'uddg=([^&]+)') { return [Uri]::UnescapeDataString($matches[1]) }
    if ($Href -match '^//') { return "https:$Href" }
    if ($Href -match '^https?://') { return $Href }
    return $null
}

function Invoke-OpsSearch {
    <#
    .SYNOPSIS
    Searches the web using Google, DuckDuckGo, GitHub, StackOverflow, or Bing with optional AI synthesis.
    .OUTPUTS
    Search results or AI-synthesized report.
    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidGlobalVars', 'Intentional rate-limiting state')]
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0, ValueFromRemainingArguments = $true)][string[]]$Query,
        [ValidateSet('google', 'ddg', 'gh', 'so', 'bing')][string]$Engine = 'google',
        [switch]$AI,
        [switch]$Deep,
        [switch]$DryRun,
        [switch]$Background,
        [ValidateRange(1, 30)][int]$Sources = 5,
        [string]$Instruction = 'Synthesize a concise report answering the query based on the following website contents.',
        [int]$BackgroundTimeoutSec = 120
    )

    $minIntervalSeconds = 5
    $now = Get-Date
    if ($script:OpsLastSearchTime) {
        $elapsed = ($now - $script:OpsLastSearchTime).TotalSeconds
        if ($elapsed -lt $minIntervalSeconds) {
            Start-Sleep -Seconds ([int]($minIntervalSeconds - $elapsed))
        }
    }
    $script:OpsLastSearchTime = Get-Date

    $cleanTokens = $Query | Where-Object { $_ -notmatch '^-(AI|a|Deep|Engine|e|Sources)$' }
    $jq = ($cleanTokens -join ' ').Trim()

    if (-not $jq) {
        throw 'Search query parameters evaluate to empty payload context.'
    }

    $enc = [Uri]::EscapeDataString($jq)
    $urls = @{
        google = "https://www.google.com/search?q=$enc"
        ddg    = "https://duckduckgo.com/?q=$enc"
        gh     = "https://github.com/search?q=$enc&type=repositories"
        so     = "https://stackoverflow.com/search?q=$enc"
        bing   = "https://www.bing.com/search?q=$enc"
    }

    if (-not $AI) {
        Write-OpsHeader " [Search] Spawning Context [$Engine] -> $jq" Cyan
        Start-Process $urls[$Engine]
        return
    }

    Write-OpsHeader " [Search] Processing Link Nodes for: $jq" Cyan
    try {
        $resp = Invoke-WebRequest -Uri 'https://lite.duckduckgo.com/lite/' -Method Post -Body @{ q = $jq } -UseBasicParsing -ErrorAction Stop

        $targetUrls = [regex]::Matches($resp.Content, 'href="([^"]+)"') | ForEach-Object { $_.Groups[1].Value } |
            Where-Object { $_ -match 'uddg=' } | ForEach-Object { Resolve-OpsDuckDuckGoHref -Href $_ } |
            Where-Object { $_ -and $_ -notmatch '^https?://(www\.)?duckduckgo\.com' } | Select-Object -Unique -First 30

        if (-not $targetUrls) { Start-Process $urls[$Engine]; return }

        $context = "Search Query: $jq`n`n"
        $read = 0
        $targetCount = if ($Sources -gt 0) { $Sources } elseif ($Deep) { 10 } else { 4 }
        $progressId = Get-Random -Minimum 1 -Maximum 9999

        foreach ($u in $targetUrls) {
            if ($read -ge $targetCount) { break }
            Write-Progress -Id $progressId -Activity "Web Search: $jq" -Status "Reading $read/$targetCount sources" -PercentComplete (($read / [Math]::Max(1, $targetCount)) * 100)
            Write-OpsHeader "  [Read] Processing structural node: $u" DarkGray

            $page = $null
            $maxRetries = 2
            for ($attempt = 0; $attempt -le $maxRetries; $attempt++) {
                try {
                    $page = Invoke-WebRequest -Uri $u -Headers @{ 'User-Agent' = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64)' } -UseBasicParsing -TimeoutSec (if ($Deep){10}else{5}) -ErrorAction Stop
                    break
                } catch {
                    if ($attempt -eq $maxRetries) { break }
                    Start-Sleep -Seconds ([Math]::Pow(2, $attempt))
                }
            }

            if (-not $page) { continue }

            $contentType = $page.BaseResponse.ContentType
            if ($contentType -notmatch 'text/html|application/xhtml\+xml') {
                Write-OpsHeader "  [Validation Warning] Skipping binary content payload: $contentType" Yellow
                continue
            }

            $txt = [System.Net.WebUtility]::HtmlDecode(($page.Content -replace '(?s)<style[^>]*>.*?</style>', '' -replace '(?s)<script[^>]*>.*?</script>', '' -replace '<[^>]+>', ' ').Trim()) -replace '\s+', ' '
            if ([string]::IsNullOrWhiteSpace($txt)) { continue }

            if (Test-OpsPromptInjection -Payload $txt) {
                Write-OpsHeader "  [Security Triggered] High anomaly metric identified inside text layout node. Node isolated." Red
                continue
            }

            $qualityScore = Get-OpsSourceQualityScore -Url $u -Content $txt
            if ($qualityScore -lt 40) {
                Write-OpsHeader "  [Quality Check Failed] Payload score ($qualityScore/100) below threshold of 40. Skipping." Yellow
                continue
            }

            if ($txt.Length -gt $(if($Deep){3000}else{1800})) { $txt = $txt.Substring(0, $(if($Deep){3000}else{1800})) }
            $context += "Source: $u (Score: $qualityScore)`nContent: $txt`n`n"
            $read++

            Start-Sleep -Milliseconds 400
        }

        Write-Progress -Id $progressId -Activity "Web Search: $jq" -Completed

        if ($DryRun) {
            Write-OpsHeader "  [Dry-Run] Target URLs to be scraped:" Yellow
            $targetUrls | Select-Object -First $targetCount | ForEach-Object { Write-Host "    - $_" -ForegroundColor DarkGray }
            Write-OpsHeader "  [Dry-Run] $read URLs resolved, $targetCount would be scraped. No requests made." Green
            return
        }

        if ($Background) {
            Write-OpsHeader "  [Background] Spawning detached background job (Start-Job) ..." Yellow
            $contextFile = [System.IO.Path]::GetTempFileName()
            $context | Out-File -FilePath $contextFile -Encoding UTF8 -Force
            $moduleManifest = Join-Path $PSScriptRoot 'PowershellOps.psd1'
            $sb = {
                param($CtxFile, $Instr, $ModPath, $Timeout)
                try {
                    Import-Module $ModPath -Force -ErrorAction Stop
                    $ctx = Get-Content $CtxFile -Raw -ErrorAction Stop
                    $ctx | Invoke-OpsAI -Instruction $Instr
                } catch { Write-Warning "Background job error: $($_.Exception.Message)" }
                finally { Remove-Item $CtxFile -Force -ErrorAction SilentlyContinue }
            }
            $job = Start-Job -ScriptBlock $sb -ArgumentList $contextFile, $Instruction, $moduleManifest, $BackgroundTimeoutSec
            Write-OpsHeader "  [Background] Background job started (ID: $($job.Id)). Results arrive in background." Green
            Write-OpsHeader "  [Background] Use: Receive-Job -Id $($job.Id) [-Keep] | Wait-Job -Id $($job.Id)" DarkGray
            return
        }

            if ($read -eq 0) { Start-Process $urls[$Engine]; return }
            Write-OpsHeader '  [AI] Synthesizing engines across checked endpoints...' Magenta
            $context | Invoke-OpsAI -Instruction $Instruction
        } catch { Start-Process $urls[$Engine] }
}

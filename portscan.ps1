# Network Scanner with Full Port Range (1-10000) and HTML/CSV Reporting
# Requires PowerShell 5.1+ and ThreadJob module (install with: Install-Module ThreadJob -Force)

param(
    [string]$network = "192.168.0",  # Modify to your network (e.g., 10.0.0)
    [int]$timeout = 100,             # Milliseconds per port check
    [int]$maxThreads = 50,           # Concurrent port checks
    [switch]$skipPortScan = $false,  # Skip port scanning for faster network discovery
    [int]$startPort = 20,             # Start port for scanning
    [int]$endPort = 32400,            # End port for scanning (reduced to common ports for speed)
    [switch]$verbose = $false,       # Enable verbose output
    [int]$maxPortBatchSize = 100,    # Maximum number of ports to scan at once
    [int]$maxMemoryMB = 1024,        # Maximum memory usage in MB (default 1GB)
    [int]$gcInterval = 5,            # Run garbage collection after this many devices
    [switch]$commonPortsOnly = $false, # Scan only common ports instead of a range
    [switch]$checkHTMLHeaders = $true, # Try to retrieve HTML titles from web ports
    [int]$headerTimeout = 3000        # Timeout in milliseconds for HTML header requests
)

# Import the System.Collections.Concurrent namespace for ConcurrentBag
Add-Type -AssemblyName System.Collections.Concurrent

# Install ThreadJob module if missing
if (-not (Get-Module -ListAvailable ThreadJob)) {
    try {
        Write-Host "Installing ThreadJob module..." -ForegroundColor Cyan
        Install-Module ThreadJob -Force -Scope CurrentUser -ErrorAction Stop
        Import-Module ThreadJob -ErrorAction Stop
        Write-Host "ThreadJob module installed successfully." -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to install the ThreadJob module: $_"
        Write-Host "Please run PowerShell as administrator and try again, or install manually with: Install-Module ThreadJob -Force" -ForegroundColor Red
        exit 1
    }
}

# Ensure ThreadJob module is loaded
Import-Module ThreadJob -ErrorAction Stop

# Helper function to get current memory usage
function Get-MemoryUsage {
    $process = Get-Process -Id $PID
    return [math]::Round($process.WorkingSet64 / 1MB, 2)
}

# Helper function to check memory usage and throttle if needed
function Test-MemoryThreshold {
    $currentMemory = Get-MemoryUsage
    if ($currentMemory -gt $maxMemoryMB) {
        Write-Host "  ! Memory usage ($currentMemory MB) exceeds threshold ($maxMemoryMB MB) - pausing for GC" -ForegroundColor Yellow
        [System.GC]::Collect()
        Start-Sleep -Seconds 2
        $newMemory = Get-MemoryUsage
        Write-Host "  ✓ Memory reduced from $currentMemory MB to $newMemory MB" -ForegroundColor Green
        return $true
    }
    return $false
}

# Define list of common ports to scan
$commonPorts = @(
    21, #FTP 
    22, #SSH 
    23, #Telnet 
    25, #SMTP 
    53, #DNS 
    80, #HTTP 
    88, #Kerberos 
    110, #POP3 
    123, #NTP 
    135, #RPC 
    139, #NetBIOS 
    143, #IMAP 
    161, #SNMP 
    389, #LDAP 
    443, #HTTPS 
    445, #SMB 
    465, #SMTPS 
    514, #Syslog 
    587, #SMTP Submission 
    636, #LDAPS 
    873, #RSYNC 
    993, #IMAPS 
    995, #POP3S 
    1080, #SOCKS Proxy 
    1194, #OpenVPN 
    1433, #MSSQL 
    1521, #Oracle 
    1723, #PPTP 
    1883, #MQTT 
    1900, #UPnP 
    2082, #cPanel 
    2083, #cPanel SSL 
    2222, #DirectAdmin 
    2375, #Docker API 
    2376, #Docker TLS 
    2377, #Docker Swarm 
    2483, #Oracle SSL 
    2484, #Oracle TNS 
    3000, #Node.js/Grafana 
    3030, #Cassandra 
    3306, #MySQL 
    3389, #RDP 
    3478, #STUN/TURN 
    3632, #DistCC 
    4369, #EPMD 
    4789, #Docker Swarm 
    5000, #Flask 
    5432, #PostgreSQL 
    5672, #AMQP (RabbitMQ) 
    5900, #VNC 
    5984, #CouchDB 
    6379, #Redis 
    6443, #Kubernetes API 
    6666, #IRC 
    6881, #BitTorrent 
    6969, #TFTP 
    8000, #Django 
    8080, #HTTP-Alt 
    8081, #HTTP-Alt2 
    8083, #InfluxDB HTTP 
    8086, #InfluxDB API 
    8096, #Jellyfin 
    8125, #StatsD 
    8200, #Vault 
    8333, #Bitcoin 
    8443, #HTTPS-Alt 
    8500, #Consul 
    8635, #Plex 
    8880, #IP Camera 
    8883, #MQTT SSL 
    8888, #Jupyter 
    9000, #Portainer/PHP-FPM 
    9001, #Portainer Agent 
    9042, #Cassandra 
    9090, #Prometheus 
    9093, #AlertManager 
    9100, #Printer/JetDirect 
    9200, #Elasticsearch 
    9300, #Elasticsearch Cluster 
    9418, #Git 
    9443, #Portainer SSL 
    9666, #Plex 
    9993, #ZeroTier 
    10000, #Webmin 
    10250, #Kubelet 
    11211, #Memcached 
    15672, #RabbitMQ Mgmt 
    25565, #Minecraft 
    27017, #MongoDB 
    32400 #Plex Media 
)

# Define which ports are likely to have HTTP/HTTPS services
$webPorts = @(80, 443, 3000, 5000, 7000, 7001, 8000, 8008, 8080, 8081, 8088, 8443, 8834, 8888, 9000, 9090, 9200, 9433, 9443, 10000, 10250, 30000, 32400, 50000, 5601, 8000, 8086, 8088, 8096, 8888, 9000, 9090, 9200, 9300, 9418, 9443, 9993, 10000, 10250, 11211, 15672, 25565, 27017, 32400)

# Display startup information
Write-Host "╔═════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  PowerShell Network & Port Scanner                  ║" -ForegroundColor Cyan
Write-Host "╚═════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "• Network: $network.0/24" -ForegroundColor Yellow

if ($commonPortsOnly) {
    Write-Host "• Scan Mode: Common Ports Only ($($commonPorts.Count) ports)" -ForegroundColor Yellow
    Write-Host "  (Use -commonPortsOnly:$false to scan a port range instead)" -ForegroundColor Yellow
} else {
    Write-Host "• Scan Mode: Port Range $startPort-$endPort" -ForegroundColor Yellow 
    Write-Host "  (Use -commonPortsOnly to scan only common ports for faster results)" -ForegroundColor Yellow
}

Write-Host "• Retrieve HTML Titles: $checkHTMLHeaders" -ForegroundColor Yellow
Write-Host "• Timeout: ${timeout}ms per port" -ForegroundColor Yellow
Write-Host "• Max Threads: $maxThreads" -ForegroundColor Yellow
Write-Host "• Skip Port Scan: $skipPortScan" -ForegroundColor Yellow
Write-Host "• Max Memory: $maxMemoryMB MB" -ForegroundColor Yellow
Write-Host "• Max Port Batch Size: $maxPortBatchSize" -ForegroundColor Yellow
Write-Host "• Verbose Output: $verbose" -ForegroundColor Yellow
Write-Host "• Current Memory Usage: $(Get-MemoryUsage) MB" -ForegroundColor Yellow
Write-Host ""

# Common service port mapping (extend as needed)
$serviceMap = @{
    21 = 'FTP'
    22 = 'SSH'
    23 = 'Telnet'
    25 = 'SMTP'
    53 = 'DNS'
    80 = 'HTTP'
    88 = 'Kerberos'
    110 = 'POP3'
    123 = 'NTP'
    135 = 'RPC'
    139 = 'NetBIOS'
    143 = 'IMAP'
    161 = 'SNMP'
    389 = 'LDAP'
    443 = 'HTTPS'
    445 = 'SMB'
    465 = 'SMTPS'
    514 = 'Syslog'
    587 = 'SMTP Submission'
    636 = 'LDAPS'
    873 = 'RSYNC'
    993 = 'IMAPS'
    995 = 'POP3S'
    1080 = 'SOCKS Proxy'
    1194 = 'OpenVPN'
    1433 = 'MSSQL'
    1521 = 'Oracle'
    1723 = 'PPTP'
    1883 = 'MQTT'
    1900 = 'UPnP'
    2082 = 'cPanel'
    2083 = 'cPanel SSL'
    2222 = 'DirectAdmin'
    2375 = 'Docker API'
    2376 = 'Docker TLS'
    2377 = 'Docker Swarm'
    2483 = 'Oracle SSL'
    2484 = 'Oracle TNS'
    3000 = 'Node.js/Grafana'
    3030 = 'Cassandra'
    3306 = 'MySQL'
    3389 = 'RDP'
    3478 = 'STUN/TURN'
    3632 = 'DistCC'
    4369 = 'EPMD'
    4789 = 'Docker Swarm'
    5000 = 'Flask'
    5432 = 'PostgreSQL'
    5672 = 'AMQP (RabbitMQ)'
    5900 = 'VNC'
    5984 = 'CouchDB'
    6379 = 'Redis'
    6443 = 'Kubernetes API'
    6666 = 'IRC'
    6881 = 'BitTorrent'
    6969 = 'TFTP'
    8000 = 'Django'
    8080 = 'HTTP-Alt'
    8081 = 'HTTP-Alt2'
    8083 = 'InfluxDB HTTP'
    8086 = 'InfluxDB API'
    8096 = 'Jellyfin'
    8125 = 'StatsD'
    8200 = 'Vault'
    8333 = 'Bitcoin'
    8443 = 'HTTPS-Alt'
    8500 = 'Consul'
    8635 = 'Plex'
    8880 = 'IP Camera'
    8883 = 'MQTT SSL'
    8888 = 'Jupyter'
    9000 = 'Portainer/PHP-FPM'
    9001 = 'Portainer Agent'
    9042 = 'Cassandra'
    9090 = 'Prometheus'
    9093 = 'AlertManager'
    9100 = 'Printer/JetDirect'
    9200 = 'Elasticsearch'
    9300 = 'Elasticsearch Cluster'
    9418 = 'Git'
    9443 = 'Portainer SSL'
    9666 = 'Plex'
    9993 = 'ZeroTier'
    10000 = 'Webmin'
    10250 = 'Kubelet'
    11211 = 'Memcached'
    15672 = 'RabbitMQ Mgmt'
    25565 = 'Minecraft'
    27017 = 'MongoDB'
    32400 = 'Plex Media'
}
# HTML Styling
$css = @"
<style>
    body { font-family: 'Segoe UI', sans-serif; margin: 2em; }
    h1 { color: #2c3e50; border-bottom: 3px solid #3498db; }
    .device-card { background: #f8f9fa; padding: 1em; margin: 1em 0; border-radius: 5px; }
    .port-table { width: 100%; border-collapse: collapse; margin-top: 1em; }
    .port-table th { background: #3498db; color: white; padding: 12px; }
    .port-table td { padding: 10px; border: 1px solid #ddd; }
    .port-open { color: #27ae60; }
    .service-name { font-weight: 600; }
    .title-info { color: #7f8c8d; font-style: italic; font-size: 0.9em; display: block; margin-top: 5px; }
    a.port-link { color: #2980b9; text-decoration: none; }
    a.port-link:hover { text-decoration: underline; }
    .tag { display: inline-block; border-radius: 3px; padding: 2px 6px; font-size: 0.8em; margin-right: 4px; }
    .tag-web { background-color: #3498db; color: white; }
</style>
"@

# Initialize HTML report
$htmlContent = @"
<!DOCTYPE html>
<html>
<head>
    <title>Network Scan Report - $(Get-Date)</title>
    $css
</head>
<body>
    <h1>Network Scan Report</h1>
    <h3>Network: $network.0/24</h3>
    <p>Generated: $(Get-Date)</p>
"@

# Create timestamp for filenames
$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$desktopPath = [Environment]::GetFolderPath("Desktop")
$reportPathHTML = "$desktopPath\NetworkScan-Report-$timestamp.html"
$reportPathCSV = "$desktopPath\NetworkScan-Report-$timestamp.csv"
Write-Host "Reports will be saved to:" -ForegroundColor Cyan
Write-Host "• HTML: $reportPathHTML" -ForegroundColor White
Write-Host "• CSV: $reportPathCSV" -ForegroundColor White
Write-Host ""

# Function to get MAC address with error handling
function Get-MacAddress($ip) {
    if ($verbose) { Write-Host "  → Looking up MAC address for $ip..." -ForegroundColor Gray }
    try {
        $arpOutput = arp -a $ip
        $macMatch = $arpOutput | Select-String '([0-9a-f]{2}-){5}[0-9a-f]{2}'
        if ($macMatch) {
            if ($verbose) { Write-Host "  ✓ Found MAC: $($macMatch.Matches.Value)" -ForegroundColor Gray }
            return $macMatch.Matches.Value
        } else {
            if ($verbose) { Write-Host "  ✗ MAC address not found in ARP table" -ForegroundColor Gray }
            return "Unknown"
        }
    } catch {
        if ($verbose) { Write-Host "  ✗ Error getting MAC address: $_" -ForegroundColor Gray }
        return "Unknown"
    }
}

# Function to attempt to resolve hostname
function Get-HostName($ip) {
    if ($verbose) { Write-Host "  → Resolving hostname for $ip..." -ForegroundColor Gray }
    try {
        $hostEntry = [System.Net.Dns]::GetHostEntry($ip)
        if ($verbose) { Write-Host "  ✓ Hostname resolved: $($hostEntry.HostName)" -ForegroundColor Gray }
        return $hostEntry.HostName
    } catch {
        if ($verbose) { Write-Host "  ✗ Could not resolve hostname" -ForegroundColor Gray }
        return "Unknown"
    }
}

# Function to get HTML title from a web page
function Get-HTMLTitle($ip, $port, $isSecure) {
    try {
        # Set security protocol to use TLS 1.2
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        
        # Create URI
        $protocol = if ($isSecure) { "https" } else { "http" }
        $uri = "$protocol`://$ip`:$port"
        
        if ($verbose) { Write-Host "      → Retrieving HTML title from $uri..." -ForegroundColor Gray }
        
        # Configure request options
        $request = [System.Net.WebRequest]::Create($uri)
        $request.Timeout = $headerTimeout
        $request.AllowAutoRedirect = $true
        
        # Ignore SSL certificate errors
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
        
        # Get response
        $response = $request.GetResponse()
        $stream = $response.GetResponseStream()
        $reader = New-Object System.IO.StreamReader($stream)
        $html = $reader.ReadToEnd()
        
        # Parse title
        if ($html -match "<title[^>]*>(.*?)</title>") {
            $title = $matches[1].Trim()
            if ($verbose) { Write-Host "      ✓ Found title: $title" -ForegroundColor Green }
            return $title
        } else {
            if ($verbose) { Write-Host "      ✗ No title found, but response received" -ForegroundColor Gray }
            return "No title"
        }
        
    } catch [System.Net.WebException] {
        if ($_.Exception.Response -ne $null) {
            $statusCode = [int]$_.Exception.Response.StatusCode
            if ($verbose) { Write-Host "      ✗ HTTP Error: $statusCode" -ForegroundColor Gray }
            return "HTTP $statusCode"
        } else {
            if ($verbose) { Write-Host "      ✗ Connection error: $($_.Exception.Message)" -ForegroundColor Gray }
            return $null
        }
    } catch {
        if ($verbose) { Write-Host "      ✗ Error: $($_.Exception.Message)" -ForegroundColor Gray }
        return $null
    } finally {
        # Reset the callback
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = $null
        
        # Close response resources
        if ($reader) { $reader.Close() }
        if ($stream) { $stream.Close() }
        if ($response) { $response.Close() }
    }
}

# Define the script blocks to be used in parallel jobs
$GetMacAddressScriptBlock = ${function:Get-MacAddress}.ToString()
$GetHostNameScriptBlock = ${function:Get-HostName}.ToString()
$GetHTMLTitleScriptBlock = ${function:Get-HTMLTitle}.ToString()

# Create results collection
$scanResults = @()

# PHASE 1: Discover online devices with MAC addresses
Write-Host "┌─ PHASE 1: Discovering active devices on network $network.0/24 ─┐" -ForegroundColor Cyan
$startTime = Get-Date

# Create a counter for discovered devices
$discoveredCounter = 0
$discoveredIPs = @()

# First ping sweep to find active devices - use smaller batches to reduce memory usage
Write-Host "Starting ping sweep..." -ForegroundColor Yellow
$batchSize = 50  # Process 50 IPs at a time
$devices = @()

for ($startIP = 1; $startIP -le 254; $startIP += $batchSize) {
    $endIP = [Math]::Min($startIP + $batchSize - 1, 254)
    Write-Host "  → Processing IP batch: $network.$startIP to $network.$endIP" -ForegroundColor Gray
    
    # Check memory before starting a new batch
    Test-MemoryThreshold
    
    $batchDevices = $startIP..$endIP | ForEach-Object -Parallel {
        $ip = "$using:network.$_"
        $isVerbose = $using:verbose
        
        # Import the functions inside the parallel context
        ${function:Get-MacAddress} = $using:GetMacAddressScriptBlock
        ${function:Get-HostName} = $using:GetHostNameScriptBlock
        
        if ($isVerbose) {
            Write-Host "  → Pinging $ip..." -ForegroundColor Gray
        }
        
        if (Test-Connection -TargetName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            if ($isVerbose) { 
                Write-Host "  ✓ $ip is ONLINE" -ForegroundColor Green 
            }
            
            $mac = Get-MacAddress $ip
            $hostname = Get-HostName $ip
            [PSCustomObject]@{
                IPAddress = $ip
                MAC = $mac
                HostName = $hostname
                Ports = @()
            }
        } elseif ($isVerbose) {
            Write-Host "  ✗ $ip is offline" -ForegroundColor Gray
        }
    } -ThrottleLimit ($maxThreads / 2) | Where-Object { $_ }
    
    $devices += $batchDevices
    
    # Force garbage collection after each batch
    [System.GC]::Collect()
    
    Write-Host "    Found $($batchDevices.Count) devices in this batch" -ForegroundColor Green
}

$discoverTime = (Get-Date) - $startTime
Write-Host "Discovery completed in $($discoverTime.TotalSeconds.ToString("0.00")) seconds." -ForegroundColor Green
Write-Host "Found $(($devices | Measure-Object).Count) active devices." -ForegroundColor Yellow
Write-Host "Current Memory Usage: $(Get-MemoryUsage) MB" -ForegroundColor Yellow
Write-Host ""

# Show discovered devices summary
Write-Host "┌─ Discovered Devices ─┐" -ForegroundColor Cyan
foreach ($device in $devices) {
    Write-Host "• $($device.IPAddress) (MAC: $($device.MAC), Host: $($device.HostName))" -ForegroundColor White
}
Write-Host ""

# Port scanning function with thread pooling and memory management
function Scan-Device($device) {
    # Create a thread-safe collection to store open ports
    try {
        # Try to create ConcurrentBag (preferred for thread safety)
        $openPorts = New-Object System.Collections.Concurrent.ConcurrentBag[PSObject]
        if ($verbose) {
            Write-Host "    Using ConcurrentBag for thread-safe collection" -ForegroundColor Gray
        }
    } catch {
        # Fallback to regular ArrayList if ConcurrentBag is not available
        Write-Host "    Note: ConcurrentBag not available, using ArrayList with synchronization" -ForegroundColor Yellow
        $openPorts = [System.Collections.ArrayList]::Synchronized([System.Collections.ArrayList]::new())
    }
    
    # Determine which ports to scan based on the commonPortsOnly flag
    $portsToScan = if ($commonPortsOnly) { $commonPorts } else { $startPort..$endPort }
    $totalPorts = $portsToScan.Count
    
    Write-Host "  → Starting port scan on $($device.IPAddress) (scanning $totalPorts ports)" -ForegroundColor Yellow
    if ($commonPortsOnly) {
        Write-Host "    Using common ports mode (faster scan)" -ForegroundColor Gray
    }
    
    $jobStartTime = Get-Date
    
    # Show port scan progress counters
    $checkedPortsCounter = 0
    $foundPortsCounter = 0
    
    # Split port scanning into smaller batches to limit memory usage
    $maxBatchSize = [Math]::Min($maxPortBatchSize, $totalPorts)
    $batchCount = [Math]::Ceiling($totalPorts / $maxBatchSize)
    $foundOpenPorts = @()
    
    for ($batchIndex = 0; $batchIndex -lt $batchCount; $batchIndex++) {
        $batchStartIndex = $batchIndex * $maxBatchSize
        $batchEndIndex = [Math]::Min(($batchStartIndex + $maxBatchSize), $totalPorts) - 1
        $currentBatch = $portsToScan[$batchStartIndex..$batchEndIndex]
        
        if ($verbose -or $batchCount -gt 1) {
            Write-Host "    Processing port batch $($batchIndex+1)/$batchCount ($($currentBatch.Count) ports)" -ForegroundColor Gray
        }
        
        # Check memory before launching a new batch
        if (Test-MemoryThreshold) {
            Write-Host "    Memory threshold reached - pausing before continuing port scan" -ForegroundColor Yellow
            Start-Sleep -Seconds 1
        }
        
        $jobs = foreach ($port in $currentBatch) {
            Start-ThreadJob -ArgumentList $port, $device -ScriptBlock {
                param($port, $device)
                $tcpClient = New-Object System.Net.Sockets.TcpClient
                try {
                    $async = $tcpClient.BeginConnect($device.IPAddress, $port, $null, $null)
                    $wait = $async.AsyncWaitHandle.WaitOne($using:timeout, $false)
                    if ($tcpClient.Connected) {
                        $localServiceMap = $using:serviceMap
                        $service = if ($localServiceMap.ContainsKey($port)) { 
                                      $localServiceMap[$port] 
                                  } else { 
                                      'Unknown' 
                                  }
                        [PSCustomObject]@{
                            Port = $port
                            Service = $service
                            Status = 'Open'
                            Title = $null
                        }
                    }
                } catch {
                    # Silent error handling for connection failures
                } finally {
                    if ($tcpClient) {
                        $tcpClient.Close()
                        $tcpClient.Dispose()
                    }
                }
            }
        }
    
        if ($verbose) {
            Write-Host "    Launched $($jobs.Count) scanner threads, waiting for completion..." -ForegroundColor Gray
        }
        
        # Show periodic updates during scanning
        $spinner = @('|', '/', '-', '\')
        $spinIndex = 0
        $lastUpdateTime = Get-Date
        
        while (($jobs | Where-Object { $_.State -ne 'Completed' } | Measure-Object).Count -gt 0) {
            $completedJobs = ($jobs | Where-Object { $_.State -eq 'Completed' } | Measure-Object).Count
            $checkedPortsCounter = $completedJobs
            
            # Update status every second
            if (((Get-Date) - $lastUpdateTime).TotalMilliseconds -gt 1000) {
                $percentComplete = [math]::Round(($completedJobs / $jobs.Count) * 100)
                $currentSpinner = $spinner[$spinIndex]
                $overallProgress = [math]::Round((($batchIndex * $maxBatchSize) + $completedJobs) * 100 / $totalPorts)
                
                # Fix: Change the colon in the string to avoid PowerShell parsing issues
                Write-Host "`r    $currentSpinner Batch $($batchIndex+1)/$($batchCount) - $percentComplete% (Overall$([char]0x3A) $overallProgress%)      " -NoNewline -ForegroundColor Yellow
                
                $spinIndex = ($spinIndex + 1) % 4
                $lastUpdateTime = Get-Date
            }
            
            Start-Sleep -Milliseconds 100
        }
        
        Write-Host "`r    ✓ Batch scan complete: $($currentBatch.Count) ports checked                           " -ForegroundColor Green
        
        # Process job results
        $jobResults = $jobs | Receive-Job -AutoRemoveJob -Wait
        foreach ($result in $jobResults) {
            if ($result) { 
                $foundOpenPorts += $result
                $foundPortsCounter++
                if ($verbose) {
                    Write-Host "    → Port $($result.Port) ($($result.Service)): OPEN" -ForegroundColor Green
                }
            }
        }
        
        # Clean up after each batch
        Remove-Variable jobs -ErrorAction SilentlyContinue
        [System.GC]::Collect()
        
        if ($batchCount -gt 1) {
            Write-Host "    Memory after batch $($batchIndex+1): $(Get-MemoryUsage) MB" -ForegroundColor Gray
        }
    }
    
    # Sort ports by number
    $sortedOpenPorts = $foundOpenPorts | Sort-Object Port
    
    # Phase 2.5: Retrieve HTML headers for web ports if checkHTMLHeaders is enabled
    if ($checkHTMLHeaders) {
        Write-Host "    → Checking for HTML titles on web ports..." -ForegroundColor Yellow
        $webPortsFound = $sortedOpenPorts | Where-Object { $webPorts -contains $_.Port } 
        
        $webCount = ($webPortsFound | Measure-Object).Count
        if ($webCount -gt 0) {
            Write-Host "      Found $webCount potential web services" -ForegroundColor Green
            
            foreach ($webPort in $webPortsFound) {
                # Determine if the port is likely HTTPS
                $isSecure = $webPort.Port -eq 443 -or $webPort.Port -eq 8443 -or $webPort.Service -like "*SSL*" -or $webPort.Service -like "*HTTPS*"
                
                # Try to get the HTML title
                Write-Host "      → Checking port $($webPort.Port) on $($device.IPAddress)..." -ForegroundColor Gray
                
                # Try secure protocol if it's normally a secure port
                if ($isSecure) {
                    $webPort.Title = Get-HTMLTitle -ip $device.IPAddress -port $webPort.Port -isSecure $true
                }
                
                # If no title found and it's not explicitly HTTPS port, try HTTP protocol
                if ([string]::IsNullOrEmpty($webPort.Title) -and $webPort.Port -ne 443 -and $webPort.Port -ne 8443) {
                    $webPort.Title = Get-HTMLTitle -ip $device.IPAddress -port $webPort.Port -isSecure $false
                }
                
                if (-not [string]::IsNullOrEmpty($webPort.Title)) {
                    Write-Host "      ✓ Port $($webPort.Port): Title found - $($webPort.Title)" -ForegroundColor Green
                }
            }
        }
        else {
            Write-Host "      No web ports found on this device" -ForegroundColor Gray
        }
    }
    
    $device.Ports = $sortedOpenPorts
    
    $jobDuration = (Get-Date) - $jobStartTime
    Write-Host "    ✓ Found $foundPortsCounter open ports in $($jobDuration.TotalSeconds.ToString("0.00")) seconds" -ForegroundColor Green
    
    return $device
}

# Scan each device
if (-not $skipPortScan) {
    Write-Host "┌─ PHASE 2: Port Scanning $($devices.Count) Devices ─┐" -ForegroundColor Cyan
    $portScanStartTime = Get-Date
}

$totalDevices = $devices.Count
$currentDevice = 0

foreach ($device in $devices) {
    $currentDevice++
    Write-Progress -Activity "Scanning network devices" -Status "$($device.IPAddress) (MAC: $($device.MAC))" -PercentComplete (($currentDevice / $totalDevices) * 100)
    
    if (-not $skipPortScan) {
        Write-Host "• Device $currentDevice of $($totalDevices): $($device.IPAddress) (MAC: $($device.MAC))" -ForegroundColor White
        $scannedDevice = Scan-Device $device
        
        # Run garbage collection periodically
        if ($currentDevice % $gcInterval -eq 0) {
            $memBefore = Get-MemoryUsage
            [System.GC]::Collect()
            $memAfter = Get-MemoryUsage
            Write-Host "  → Memory cleanup: $memBefore MB → $memAfter MB" -ForegroundColor Gray
        }
    } else {
        $scannedDevice = $device
    }
    
    # Add to HTML report
    $htmlContent += @"
    <div class="device-card">
        <h3>Device: $($scannedDevice.IPAddress)</h3>
        <p>MAC Address: $($scannedDevice.MAC)</p>
        <p>Hostname: $($scannedDevice.HostName)</p>
"@

    if (-not $skipPortScan) {
        $htmlContent += @"
        <table class="port-table">
            <tr><th>Port</th><th>Status</th><th>Service</th><th>Details</th></tr>
"@
    
        foreach ($port in $scannedDevice.Ports) {
            # Determine if it's a web port for link and styling
            $isWebPort = $webPorts -contains $port.Port
            $protocol = if ($port.Port -eq 443 -or $port.Port -eq 8443 -or $port.Service -like "*SSL*" -or $port.Service -like "*HTTPS*") { "https" } else { "http" }
            
            # Create a hyperlink for web services
            $portDisplay = if ($isWebPort) {
                "<a href='$protocol`://$($scannedDevice.IPAddress):$($port.Port)' class='port-link' target='_blank'>$($port.Port)</a>"
            } else {
                "$($port.Port)"
            }
            
            # Add tags for port type
            $tags = if ($isWebPort) {
                "<span class='tag tag-web'>Web</span>"
            } else {
                ""
            }
            
            # Add HTML title if available
            $titleInfo = if (-not [string]::IsNullOrEmpty($port.Title)) {
                "<span class='title-info'>$($port.Title)</span>"
            } else {
                ""
            }
            
            $htmlContent += @"
            <tr>
                <td>$portDisplay</td>
                <td class="port-open">Open</td>
                <td><span class="service-name">$($port.Service)</span></td>
                <td>$tags $titleInfo</td>
            </tr>
"@
        }
    
        $htmlContent += "</table>"
    }
    
    $htmlContent += "</div>"
    
    # Build results for CSV - only keep what's needed to reduce memory consumption
    if ($scannedDevice.Ports.Count -gt 0) {
        foreach ($port in $scannedDevice.Ports) {
            $scanResults += [PSCustomObject]@{
                IPAddress = $scannedDevice.IPAddress
                MAC = $scannedDevice.MAC
                HostName = $scannedDevice.HostName
                Port = $port.Port
                Status = 'Open'
                Service = $port.Service
                Title = $port.Title
                IsWebPort = if ($webPorts -contains $port.Port) { "Yes" } else { "No" }
            }
        }
    } else {
        # Add a device even if no open ports
        $scanResults += [PSCustomObject]@{
            IPAddress = $scannedDevice.IPAddress
            MAC = $scannedDevice.MAC
            HostName = $scannedDevice.HostName
            Port = $null
            Status = $null
            Service = $null
            Title = $null
            IsWebPort = "No"
        }
    }
    
    # Clear the device ports to free memory
    $scannedDevice.Ports = $null
}

# Complete HTML report
$htmlContent += @"
</body>
</html>
"@

# Save reports
Write-Host ""
Write-Host "┌─ PHASE 3: Generating Reports ─┐" -ForegroundColor Cyan
Write-Host "• Current Memory: $(Get-MemoryUsage) MB" -ForegroundColor Yellow
Write-Host "• Saving HTML report to $reportPathHTML" -ForegroundColor White
$htmlContent | Out-File $reportPathHTML -Encoding UTF8

Write-Host "• Saving CSV report to $reportPathCSV" -ForegroundColor White  
$scanResults | Export-Csv -Path $reportPathCSV -NoTypeInformation

# Clear variables to free memory
$htmlContent = $null
$scanResults = $null
$devices = $null
[System.GC]::Collect()

$totalScanTime = (Get-Date) - $startTime
Write-Host ""
Write-Host "╔═════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║  Network Scan Complete                  ║" -ForegroundColor Green
Write-Host "╚═════════════════════════════════════════╝" -ForegroundColor Green
Write-Host "• Total scan time: $($totalScanTime.TotalSeconds.ToString("0.00")) seconds" -ForegroundColor Yellow
Write-Host "• Final Memory Usage: $(Get-MemoryUsage) MB" -ForegroundColor Yellow
Write-Host ""
Write-Host "Reports saved to:" -ForegroundColor White
Write-Host "• HTML Report: $reportPathHTML" -ForegroundColor Cyan
Write-Host "• CSV Report: $reportPathCSV" -ForegroundColor Cyan

# Open reports if available
if (Test-Path $reportPathHTML) {
    Write-Host "Opening HTML report in default browser..." -ForegroundColor White
    Invoke-Item $reportPathHTML
}
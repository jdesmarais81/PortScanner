# PowerShell Network & Port Scanner

A comprehensive network discovery and port scanning tool built for PowerShell 7+.

## Features

- Network device discovery with MAC address and hostname resolution
- Customizable port scanning (common ports or user-defined range)
- HTML and CSV report generation
- Memory-optimized for scanning large networks
- Retrieves HTML titles from web services
- Supports multi-threading for faster scans

## Prerequisites

- PowerShell 7.0 or higher
- ThreadJob module (auto-installed if missing)

## Usage

```.\portscan.ps1 [-network <string>] [-timeout <int>] [-maxThreads <int>] [-skipPortScan] [-startPort <int>] [-endPort <int>] [-verbose] [-maxPortBatchSize <int>] [-maxMemoryMB <int>] [-gcInterval <int>] [-commonPortsOnly] [-checkHTMLHeaders] [-headerTimeout <int>]```


### Parameters

- `-network`: Target network (default: 192.168.0)
- `-timeout`: Milliseconds per port check (default: 100)
- `-maxThreads`: Concurrent port checks (default: 1000)
- `-skipPortScan`: Skip port scanning for faster network discovery
- `-startPort`: Start port for scanning (default: 20)
- `-endPort`: End port for scanning (default: 32400)
- `-verbose`: Enable detailed output
- `-maxPortBatchSize`: Maximum number of ports to scan at once (default: 2000)
- `-maxMemoryMB`: Maximum memory usage in MB (default: 4096)
- `-gcInterval`: Run garbage collection after this many devices (default: 5)
- `-commonPortsOnly`: Scan only common ports instead of a range
- `-checkHTMLHeaders`: Try to retrieve HTML titles from web ports (default: true)
- `-headerTimeout`: Timeout in milliseconds for HTML header requests (default: 3000)

## Examples

1. Scan default network with common ports:
```.\portscan.ps1 -commonPortsOnly```

2. Scan a specific network with custom port range:
```.\portscan.ps1 -network "10.0.0" -startPort 1 -endPort 1024```

3. Quick network discovery without port scanning:
```.\portscan.ps1 -skipPortScan```



## Output

The script generates two report files on your desktop:
1. HTML report with detailed device and port information
2. CSV report for easy data analysis

## Notes

- Ensure you have permission to scan the target network
- Scanning all ports (1-65535) can take a significant amount of time and Memory
- Use `-commonPortsOnly` for faster scans of well-known services
- Adjust `-maxMemoryMB` if you encounter out-of-memory errors

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

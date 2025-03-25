# PowerShell Network & Port Scanner

A comprehensive network discovery and port scanning tool built for PowerShell 7+.

![Port Scanner in Action](https://github.com/jdesmarais81/PortScanner/blob/main/In%20Action.png)

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

```Powershell
.\portscan.ps1 [-network <string>] [-timeout <int>] [-maxThreads <int>] [-skipPortScan] [-startPort <int>] [-endPort <int>] [-verbose] [-maxPortBatchSize <int>] [-maxMemoryMB <int>] [-gcInterval <int>] [-commonPortsOnly] [-checkHTMLHeaders] [-headerTimeout <int>]
```

### Parameters

- `-network`: Target network (default: 192.168.0)
- `-timeout`: Milliseconds per port check (default: 100)
- `-maxThreads`: Concurrent port checks (default: 50)
- `-skipPortScan`: Skip port scanning for faster network discovery
- `-startPort`: Start port for scanning (default: 20)
- `-endPort`: End port for scanning (default: 32400)
- `-verbose`: Enable detailed output
- `-maxPortBatchSize`: Maximum number of ports to scan at once (default: 100)
- `-maxMemoryMB`: Maximum memory usage in MB (default: 1024)
- `-gcInterval`: Run garbage collection after this many devices (default: 5)
- `-commonPortsOnly`: Scan only common ports instead of a range
- `-checkHTMLHeaders`: Try to retrieve HTML titles from web ports (default: true)
- `-headerTimeout`: Timeout in milliseconds for HTML header requests (default: 3000)

## Common Ports Scanned

| Port | Service | Port | Service | Port | Service |
|------|---------|------|---------|------|---------|
| 21   | FTP     | 80   | HTTP    | 3306 | MySQL   |
| 22   | SSH     | 88   | Kerberos| 3389 | RDP     |
| 23   | Telnet  | 110  | POP3    | 5432 | PostgreSQL |
| 25   | SMTP    | 123  | NTP     | 6379 | Redis   |
| 53   | DNS     | 135  | RPC     | 8080 | HTTP-Alt|
| 69   | TFTP    | 139  | NetBIOS | 8443 | HTTPS-Alt |
| 443  | HTTPS   | 445  | SMB     | 9443 | Portainer |
| 465  | SMTPS   | 1433 | MSSQL   | 9090 | Prometheus |
| 587  | SMTP Sub| 2375 | Docker  | 27017| MongoDB |
| 636  | LDAPS   | 3000 | Grafana | 32400| Plex    |

## Examples

1. Scan default network with common ports: (Recommended for Quick Scans)
```
.\portscan.ps1 -commonPortsOnly
```

3. Scan a specific network with custom port range:
```
.\portscan.ps1 -network "10.0.0" -startPort 1 -endPort 1024
```

5. Quick network discovery without port scanning:
```
.\portscan.ps1 -skipPortScan
```

## Output

The script generates two report files on your desktop:
1. HTML report with detailed device and port information
2. CSV report for easy data analysis
![HTML Export Example](https://github.com/jdesmarais81/PortScanner/blob/main/HTML-Export.png)

## Notes

- Ensure you have permission to scan the target network
- Scanning all ports (1-65535) can take a significant amount of time and Memory
- Use `-commonPortsOnly` for faster scans of well-known services
- Adjust `-maxMemoryMB` if you encounter out-of-memory errors

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

This project is licensed under the MIT License - see the LICENSE file for details.

# Fleet Monitor

A lightweight Bash monitoring agent for Linux systems. Collects disk, RAM, CPU, temp, swap, load, uptime, users, hardware, network, top processes, disk I/O, and service status, then reports to a central dashboard every 5 minutes via cron.

## Features

- **Zero dependencies** — pure Bash + standard Linux tools (`df`, `free`, `top`, `uptime`, `systemctl`, `curl`, `lsusb`, `lspci`, `lsblk`, `ip`, `who`)
- **Lightweight** — runs in under 1 second, negligible CPU/memory footprint
- **Threshold alerts** — email alerts when disk >80%, RAM >85%, CPU >90%, or CPU temp >75°C
- **Service monitoring** — checks critical services (ssh, headscale-admin, tailscaled, betterdesk-server, cdap-agent)
- **Hardware inventory** — USB devices, PCI devices, block devices
- **Network info** — interface names, IP addresses
- **Process tracking** — top 3 CPU/memory consumers, zombie process count
- **User tracking** — logged-in usernames and count
- **Disk I/O** — read/write throughput from `/proc/diskstats`
- **Centralized reporting** — JSON payload to a central dashboard endpoint
- **Cron-based** — runs every 5 minutes, no daemon needed
- **Multi-distro** — works on Ubuntu 20.04+, Debian 11+, RHEL/Rocky/AlmaLinux 8+

## Quick Start

### 1. Install the agent

```bash
sudo install -m 0755 ppch-agent.sh /usr/local/bin/ppch-agent
sudo mkdir -p /var/log/sysmon
```

### 2. Configure

Edit `/usr/local/bin/ppch-agent.sh` and set:

```bash
CENTRAL_URL="https://your-dashboard.example.com"
REPORT_ENDPOINT="/api/monitoring/report"
```

Optional: set `MONITORING_API_KEY` if the dashboard requires auth.

### 3. Add to crontab

```bash
(crontab -l 2>/dev/null; echo '*/5 * * * * /usr/local/bin/ppch-agent >> /var/log/sysmon/cron.log 2>&1') | sudo crontab -
```

### 4. Test

```bash
/usr/local/bin/ppch-agent
```

Check the log:

```bash
cat /var/log/sysmon/sysmon.log
```

## What It Collects

| Metric | Source | Threshold |
|---|---|---|
| Disk usage (%) | `df -h /` | 80% |
| RAM usage (%) | `free -m` | 85% |
| Swap usage (%) | `free -m` | — |
| CPU usage (%) | `top -bn1` | 90% |
| CPU temperature (°C) | `/sys/class/thermal/` | 75°C |
| Load average | `uptime` | — |
| Uptime | `uptime -p` | — |
| Boot time | `who -b` | — |
| Zombie processes | `ps aux` | — |
| Logged-in users | `who` | — |
| USB devices | `lsusb` | — |
| PCI devices | `lspci` | — |
| Block devices | `lsblk` | — |
| Network interfaces | `ip link` | — |
| Network IPs | `ip addr` | — |
| Top CPU processes | `ps aux --sort=-%cpu` | — |
| Top memory processes | `ps aux --sort=-%mem` | — |
| Disk I/O (MB/s) | `/proc/diskstats` | — |
| Services running | `systemctl is-active` | — |
| Failed services | `systemctl is-active` | — |

## Configuration

| Variable | Default | Description |
|---|---|---|
| `CENTRAL_URL` | `https://ppch.ddns.net:8443` | Dashboard base URL |
| `REPORT_ENDPOINT` | `/api/monitoring/report` | API endpoint path |
| `API_KEY` | _(empty)_ | Bearer token if required |
| `THRESHOLD_DISK` | `80` | Disk alert threshold (%) |
| `THRESHOLD_RAM` | `85` | RAM alert threshold (%) |
| `THRESHOLD_CPU` | `90` | CPU alert threshold (%) |
| `THRESHOLD_TEMP` | `75` | CPU temp alert threshold (°C) |
| `SERVICES` | `ssh headscale-admin tailscaled betterdesk-server cdap-agent` | Services to monitor |

## Dashboard Integration

The agent POSTs JSON to the dashboard:

```json
{
    "hostname": "nebula",
    "os": "Ubuntu 24.04 LTS",
    "timestamp": "2026-10-11T11:45:00-05:00",
    "metrics": {
        "disk_usage_percent": 45,
        "ram_usage_percent": 32,
        "swap_usage_percent": 5,
        "cpu_usage_percent": 12,
        "cpu_temp_celsius": 52,
        "load_average": 0.52,
        "uptime": "up 3 days, 2 hours",
        "boot_time": "2026-10-08 09:15",
        "zombie_processes": 0,
        "logged_in_users": "jdvann",
        "logged_in_count": 1,
        "usb_devices": 6,
        "pci_devices": 12,
        "block_devices": 2,
        "network_interfaces": "eth0,tailscale0",
        "network_ips": "eth0 192.168.0.203/24; tailscale0 100.64.0.2/32",
        "top_cpu_processes": "python3(8%) sshd(3%)",
        "top_mem_processes": "python3(12%) Xorg(8%)",
        "disk_io": "r:12 w:45",
        "services_running": "5/5",
        "services_failed": "none"
    }
}
```

The dashboard stores reports in SQLite and displays them on the Monitoring page.

## Log Files

| Path | Description |
|---|---|
| `/var/log/sysmon/sysmon.log` | Agent output (alerts, report status) |
| `/var/log/sysmon/cron.log` | Cron stdout/stderr |

## Uninstall

```bash
sudo rm /usr/local/bin/ppch-agent
sudo crontab -l | grep -v ppch-agent | sudo crontab -
sudo rm -rf /var/log/sysmon
```

## Related Repos

- [headscale-dashboard](https://github.com/jdvann/headscale-dashboard) — central dashboard that receives reports
- [Headscale](https://github.com/juanfont/headscale) — self-hosted Tailscale control server

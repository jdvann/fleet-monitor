# Fleet Monitor

A lightweight Bash monitoring agent for Linux systems. Collects disk, RAM, CPU, load, uptime, and service status, then reports to a central dashboard every 5 minutes via cron.

## Features

- **Zero dependencies** — pure Bash + standard Linux tools (`df`, `free`, `top`, `uptime`, `systemctl`, `curl`)
- **Lightweight** — runs in under 1 second, negligible CPU/memory footprint
- **Threshold alerts** — email alerts when disk >80%, RAM >85%, or CPU >90%
- **Service monitoring** — checks critical services (ssh, headscale-admin, tailscaled, betterdesk-server, cdap-agent)
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
| CPU usage (%) | `top -bn1` | 90% |
| Load average | `uptime` | — |
| Uptime | `uptime -p` | — |
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
        "cpu_usage_percent": 12,
        "load_average": 0.52,
        "uptime": "up 3 days, 2 hours",
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

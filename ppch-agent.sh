#!/bin/bash
# Lightweight system monitoring agent for Patient PC Help fleet
# Collects disk, RAM, CPU, temp, load, uptime, users, hardware, network, services
# Reports to central dashboard every 5 minutes via cron

set -euo pipefail

# Configuration
CENTRAL_URL="${CENTRAL_URL:-https://ppch.ddns.net:8443}"
REPORT_ENDPOINT="${REPORT_ENDPOINT:-/api/monitoring/report}"
API_KEY="${MONITORING_API_KEY:-}"
HOSTNAME="$(hostname -s)"
OS="$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
KERNEL="$(uname -r)"
THRESHOLD_DISK=80
THRESHOLD_RAM=85
THRESHOLD_CPU=90
THRESHOLD_TEMP=75
SERVICES=("ssh" "headscale-admin" "tailscaled" "betterdesk-server" "cdap-agent")

RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

LOG_FILE="/var/log/sysmon/sysmon.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

mkdir -p "$(dirname "$LOG_FILE")"

# --- Collect metrics ---

get_disk_usage() {
    df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
}

get_ram_usage() {
    free -m | awk 'NR==2 {printf "%.0f", $3/$2*100}'
}

get_swap_usage() {
    free -m | awk '/^Swap:/ {if ($2==0) print 0; else printf "%.0f", $3/$2*100}'
}

get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1
}

get_cpu_temp() {
    local temp=""
    if [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        temp=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null)
    elif ls /sys/class/thermal/thermal_zone*/temp &>/dev/null; then
        temp=$(cat /sys/class/thermal/thermal_zone*/temp 2>/dev/null | head -1)
    fi
    if [ -n "$temp" ] && [ "$temp" -gt 0 ] 2>/dev/null; then
        echo $((temp / 1000))
    else
        echo "0"
    fi
}

get_load_avg() {
    uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs
}

get_uptime() {
    uptime -p | sed 's/up //'
}

get_boot_time() {
    who -b 2>/dev/null | awk '{print $3, $4}' || echo "unknown"
}

get_zombie_count() {
    ps aux | awk '$8 ~ /Z/ {count++} END {print count+0}'
}

# --- Users ---

get_logged_in_users() {
    who 2>/dev/null | awk '{print $1}' | sort -u | tr '\n' ',' | sed 's/,$//'
}

get_user_count() {
    who 2>/dev/null | wc -l
}

# --- Hardware ---

get_usb_devices() {
    lsusb 2>/dev/null | tail -n +2 | wc -l
}

get_pci_devices() {
    lspci 2>/dev/null | wc -l
}

get_block_devices() {
    lsblk -d -n 2>/dev/null | wc -l
}

get_network_interfaces() {
    ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -v lo | tr '\n' ',' | sed 's/,$//'
}

get_network_ips() {
    ip -o -4 addr show 2>/dev/null | awk '{print $2, $4}' | grep -v '127.0.0.1' | awk '{print $2, $1}' | tr '\n' ';' | sed 's/;$//'
}

# --- Top processes ---

get_top_cpu_processes() {
    ps aux --sort=-%cpu 2>/dev/null | awk 'NR>1 && NR<=4 {printf "%s(%s%%) ", $11, $3}'
}

get_top_mem_processes() {
    ps aux --sort=-%mem 2>/dev/null | awk 'NR>1 && NR<=4 {printf "%s(%s%%) ", $11, $4}'
}

# --- Disk I/O ---

get_disk_io() {
    if [ -f /proc/diskstats ]; then
        awk '/(sd[a-z]|nvme[0-9]|vd[a-z]|xvd[a-z])/ {read+=$6; write+=$10} END {printf "r:%d w:%d", read*512/1048576, write*512/1048576}' /proc/diskstats
    else
        echo "r:0 w:0"
    fi
}

# --- Services ---

get_running_services() {
    local running=0
    local total=0
    for svc in "${SERVICES[@]}"; do
        if systemctl is-active --quiet "$svc" 2>/dev/null; then
            ((running++))
        fi
        ((total++))
    done
    echo "$running/$total"
}

get_failed_services() {
    local failed=""
    for svc in "${SERVICES[@]}"; do
        if ! systemctl is-active --quiet "$svc" 2>/dev/null; then
            failed="$failed $svc"
        fi
    done
    echo "${failed:-none}"
}

# --- Alerts ---

check_alerts() {
    local disk=$(get_disk_usage)
    local ram=$(get_ram_usage)
    local cpu=$(get_cpu_usage)
    local temp=$(get_cpu_temp)
    local alerts=()

    [ "$disk" -ge "$THRESHOLD_DISK" ] && alerts+=("DISK:${disk}%")
    [ "$ram" -ge "$THRESHOLD_RAM" ] && alerts+=("RAM:${ram}%")
    [ "$cpu" -ge "$THRESHOLD_CPU" ] && alerts+=("CPU:${cpu}%")
    [ "$temp" -ge "$THRESHOLD_TEMP" ] && [ "$temp" -gt 0 ] && alerts+=("TEMP:${temp}C")

    if [ ${#alerts[@]} -gt 0 ]; then
        log "${RED}ALERT${NC} $HOSTNAME: ${alerts[*]}"
        if command -v mail &>/dev/null; then
            echo "System alert on $HOSTNAME: ${alerts[*]}" | \
                mail -s "[ALERT] $HOSTNAME: ${alerts[*]}" alerts@ppch.ddns.net 2>/dev/null || true
        fi
    fi
}

# --- Build JSON payload ---

build_payload() {
    local disk=$(get_disk_usage)
    local ram=$(get_ram_usage)
    local swap=$(get_swap_usage)
    local cpu=$(get_cpu_usage)
    local temp=$(get_cpu_temp)
    local load=$(get_load_avg)
    local uptime_str=$(get_uptime)
    local boot=$(get_boot_time)
    local zombies=$(get_zombie_count)
    local users=$(get_logged_in_users)
    local user_count=$(get_user_count)
    local usb=$(get_usb_devices)
    local pci=$(get_pci_devices)
    local block=$(get_block_devices)
    local net_ifaces=$(get_network_interfaces)
    local net_ips=$(get_network_ips)
    local top_cpu=$(get_top_cpu_processes)
    local top_mem=$(get_top_mem_processes)
    local disk_io=$(get_disk_io)
    local services_running=$(get_running_services)
    local services_failed=$(get_failed_services)

    users=$(echo "$users" | sed 's/"/\\"/g')
    net_ifaces=$(echo "$net_ifaces" | sed 's/"/\\"/g')
    net_ips=$(echo "$net_ips" | sed 's/"/\\"/g')
    top_cpu=$(echo "$top_cpu" | sed 's/"/\\"/g')
    top_mem=$(echo "$top_mem" | sed 's/"/\\"/g')

    cat <<EOF
{
    "hostname": "$HOSTNAME",
    "os": "$OS",
    "kernel": "$KERNEL",
    "timestamp": "$(date -Iseconds)",
    "metrics": {
        "disk_usage_percent": $disk,
        "ram_usage_percent": $ram,
        "swap_usage_percent": $swap,
        "cpu_usage_percent": $cpu,
        "cpu_temp_celsius": $temp,
        "load_average": $load,
        "uptime": "$uptime_str",
        "boot_time": "$boot",
        "zombie_processes": $zombies,
        "logged_in_users": "$users",
        "logged_in_count": $user_count,
        "usb_devices": $usb,
        "pci_devices": $pci,
        "block_devices": $block,
        "network_interfaces": "$net_ifaces",
        "network_ips": "$net_ips",
        "top_cpu_processes": "$top_cpu",
        "top_mem_processes": "$top_mem",
        "disk_io": "$disk_io",
        "services_running": "$services_running",
        "services_failed": "$services_failed"
    }
}
EOF
}

# --- Report to central dashboard ---

report_metrics() {
    local payload=$(build_payload)
    local curl_opts="-sk -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 10"

    if [ -n "$API_KEY" ]; then
        curl_opts="$curl_opts -H 'Authorization: Bearer $API_KEY'"
    fi

    curl $curl_opts -X POST \
        -H 'Content-Type: application/json' \
        -d "$payload" \
        "${CENTRAL_URL}${REPORT_ENDPOINT}" >/dev/null 2>&1 && \
        log "Reported to central dashboard" || \
        log "Failed to report to central dashboard"
}

# --- Main ---

main() {
    check_alerts
    report_metrics
}

main "$@"

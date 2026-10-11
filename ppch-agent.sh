#!/bin/bash
# Lightweight system monitoring agent for Patient PC Help fleet
# Collects disk, RAM, CPU, load, uptime, service status, and reports to central dashboard
# Deploy to each machine, runs via cron every 5 minutes

set -euo pipefail

# Configuration
CENTRAL_URL="${CENTRAL_URL:-https://ppch.ddns.net:8443}"
REPORT_ENDPOINT="${REPORT_ENDPOINT:-/api/monitoring/report}"
API_KEY="${MONITORING_API_KEY:-}"  # if dashboard requires auth
HOSTNAME="$(hostname -s)"
OS="$(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
THRESHOLD_DISK=80
THRESHOLD_RAM=85
THRESHOLD_CPU=90
SERVICES=("ssh" "headscale-admin" "tailscaled" "betterdesk-server" "cdap-agent")

# Colors for local logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LOG_FILE="/var/log/sysmon/sysmon.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOG_FILE"
}

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# --- Collect metrics ---

get_disk_usage() {
    df -h / | awk 'NR==2 {gsub(/%/,"",$5); print $5}'
}

get_ram_usage() {
    free -m | awk 'NR==2 {printf "%.0f", $3/$2*100}'
}

get_cpu_usage() {
    top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1 | cut -d'.' -f1
}

get_load_avg() {
    uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $1}' | xargs
}

get_uptime() {
    uptime -p | sed 's/up //'
}

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

# --- Check thresholds and alert ---

check_alerts() {
    local disk=$(get_disk_usage)
    local ram=$(get_ram_usage)
    local cpu=$(get_cpu_usage)
    local alerts=()

    if [ "$disk" -ge "$THRESHOLD_DISK" ]; then
        alerts+=("DISK:${disk}%")
    fi
    if [ "$ram" -ge "$THRESHOLD_RAM" ]; then
        alerts+=("RAM:${ram}%")
    fi
    if [ "$cpu" -ge "$THRESHOLD_CPU" ]; then
        alerts+=("CPU:${cpu}%")
    fi

    if [ ${#alerts[@]} -gt 0 ]; then
        log "${RED}ALERT${NC} $HOSTNAME: ${alerts[*]}"
        # Send email alert if mail is configured
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
    local cpu=$(get_cpu_usage)
    local load=$(get_load_avg)
    local uptime_str=$(get_uptime)
    local services_running=$(get_running_services)
    local services_failed=$(get_failed_services)

    cat <<EOF
{
    "hostname": "$HOSTNAME",
    "os": "$OS",
    "timestamp": "$(date -Iseconds)",
    "metrics": {
        "disk_usage_percent": $disk,
        "ram_usage_percent": $ram,
        "cpu_usage_percent": $cpu,
        "load_average": $load,
        "uptime": "$uptime_str",
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

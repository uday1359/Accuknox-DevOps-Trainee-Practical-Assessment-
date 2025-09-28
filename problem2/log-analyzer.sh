#!/bin/bash

# Ubuntu System Health Monitor
# Author: Ubuntu System Administrator
# Description: Ubuntu-specific system monitoring with apt, snap, and systemd

# Configuration
THRESHOLD_CPU=80
THRESHOLD_MEM=80
THRESHOLD_DISK=85
THRESHOLD_TEMP=70
LOG_FILE="/var/log/ubuntu_health.log"
ALERT_FILE="/tmp/ubuntu_alerts.txt"

# Ubuntu-specific paths
SYSLOG_FILE="/var/log/syslog"
KERNEL_LOG="/var/log/kern.log"
APT_LOG="/var/log/apt/history.log"
SNAPD_LOG="/var/log/syslog | grep snapd"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m' # No Color

# Initialize
ALERTS=0
WARNINGS=0

# Check sudo
check_sudo() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}This script requires sudo privileges. Run with:${NC}"
        echo -e "sudo $0"
        exit 1
    fi
}

# Timestamp
timestamp() {
    date '+%Y-%m-%d %H:%M:%S %Z'
}

# Log function
log() {
    local level=$1
    local message=$2
    local color=$3
    
    echo -e "${color}$(timestamp) [$level] $message${NC}"
    echo "$(timestamp) [$level] $message" >> "$LOG_FILE"
}

# Ubuntu-specific: Check package updates
check_ubuntu_updates() {
    log "INFO" "Checking for Ubuntu updates..." "$BLUE"
    
    # Update package list
    if ! apt-get update > /dev/null 2>&1; then
        log "WARNING" "Failed to update package lists" "$YELLOW"
        return 1
    fi
    
    # Check for updates
    UPDATES=$(apt-get -s upgrade | grep -c "^Inst")
    SECURITY_UPDATES=$(apt-get -s upgrade | grep -i security | grep -c "^Inst")
    
    if [ "$UPDATES" -gt 0 ]; then
        log "WARNING" "$UPDATES packages need updates ($SECURITY_UPDATES security)" "$YELLOW"
        echo "Updates: $UPDATES packages ($SECURITY_UPDATES security)" >> "$ALERT_FILE"
        ((WARNINGS++))
    else
        log "INFO" "System is up to date" "$GREEN"
    fi
}

# Ubuntu-specific: Check automatic updates
check_automatic_updates() {
    log "INFO" "Checking automatic updates configuration..." "$BLUE"
    
    if systemctl is-active --quiet unattended-upgrades; then
        log "INFO" "Automatic updates are enabled" "$GREEN"
    else
        log "WARNING" "Automatic updates are not enabled" "$YELLOW"
        echo "Automatic updates: Disabled" >> "$ALERT_FILE"
        ((WARNINGS++))
    fi
}

# Ubuntu-specific: Check snap services
check_snap_services() {
    log "INFO" "Checking Snap services..." "$BLUE"
    
    if command -v snap > /dev/null 2>&1; then
        SNAP_COUNT=$(snap list 2>/dev/null | wc -l)
        if [ "$SNAP_COUNT" -le 1 ]; then
            log "INFO" "No snap packages installed" "$GREEN"
        else
            log "INFO" "$((SNAP_COUNT-1)) snap packages installed" "$GREEN"
            
            # Check for failed snap services
            SNAP_FAILED=$(snap services 2>/dev/null | grep failed | wc -l)
            if [ "$SNAP_FAILED" -gt 0 ]; then
                log "ERROR" "$SNAP_FAILED snap services failed" "$RED"
                echo "Snap services: $SNAP_FAILED failed" >> "$ALERT_FILE"
                ((ALERTS++))
            fi
        fi
    else
        log "INFO" "Snap not installed" "$GREEN"
    fi
}

# Ubuntu-specific: Check APT sources
check_apt_sources() {
    log "INFO" "Checking APT sources..." "$BLUE"
    
    # Check for third-party repositories
    THIRD_PARTY=$(find /etc/apt/sources.list.d/ -name "*.list" -exec grep -v "^#" {} \; | grep -v "ubuntu.com" | grep -v "canonical.com" | wc -l)
    
    if [ "$THIRD_PARTY" -gt 0 ]; then
        log "WARNING" "Third-party repositories detected" "$YELLOW"
        echo "APT: Third-party repositories detected" >> "$ALERT_FILE"
        ((WARNINGS++))
    fi
    
    # Check for held packages
    HELD_PACKAGES=$(apt-mark showhold | wc -l)
    if [ "$HELD_PACKAGES" -gt 0 ]; then
        log "INFO" "$HELD_PACKAGES packages on hold" "$GREEN"
    fi
}

# Ubuntu-specific: Check systemd services
check_ubuntu_services() {
    log "INFO" "Checking Ubuntu essential services..." "$BLUE"
    
    # Ubuntu-specific services
    UBUNTU_SERVICES=(
        "networking"
        "systemd-resolved"
        "ufw"
        "apparmor"
        "console-setup"
        "cron"
        "dbus"
        "grub-common"
        "kernel-config"
        "logrotate"
        "man-db"
        "networkd-dispatcher"
        "packagekit"
        "polkit"
        "rsyslog"
        "ssh"
        "systemd-journald"
        "ubuntu-advantage"
        "ubuntu-fan"
        "unattended-upgrades"
    )
    
    for service in "${UBUNTU_SERVICES[@]}"; do
        if systemctl list-unit-files | grep -q "$service.service"; then
            if systemctl is-active --quiet "$service"; then
                log "DEBUG" "Service $service: active" "$GREEN"
            else
                log "WARNING" "Service $service: not active" "$YELLOW"
                echo "Service: $service not active" >> "$ALERT_FILE"
                ((WARNINGS++))
            fi
        fi
    done
}

# Ubuntu-specific: Check cloud-init (if applicable)
check_cloud_init() {
    if command -v cloud-init > /dev/null 2>&1; then
        log "INFO" "Checking cloud-init status..." "$BLUE"
        
        CLOUD_INIT_STATUS=$(cloud-init status 2>/dev/null)
        if [ $? -eq 0 ]; then
            log "INFO" "cloud-init: $CLOUD_INIT_STATUS" "$GREEN"
        else
            log "WARNING" "cloud-init status check failed" "$YELLOW"
        fi
    fi
}

# Ubuntu-specific: Check landscape (if installed)
check_landscape() {
    if command -v landscape-client > /dev/null 2>&1; then
        log "INFO" "Checking Landscape client..." "$BLUE"
        
        if systemctl is-active --quiet landscape-client; then
            log "INFO" "Landscape client: active" "$GREEN"
        else
            log "WARNING" "Landscape client: not active" "$YELLOW"
            echo "Landscape client: not active" >> "$ALERT_FILE"
            ((WARNINGS++))
        fi
    fi
}

# Check CPU usage (Ubuntu optimized)
check_cpu() {
    log "INFO" "Checking CPU usage..." "$BLUE"
    
    # Use mpstat for more accurate reading
    if command -v mpstat > /dev/null 2>&1; then
        CPU_USAGE=$(mpstat 1 1 | awk '$12 ~ /[0-9.]+/ {print 100 - $12}' | tail -1)
    else
        CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    fi
    
    CPU_INT=$(printf "%.0f" "$CPU_USAGE")
    
    if [ "$CPU_INT" -gt "$THRESHOLD_CPU" ]; then
        log "ERROR" "CPU usage: ${CPU_INT}% (Threshold: ${THRESHOLD_CPU}%)" "$RED"
        echo "CPU: ${CPU_INT}%" >> "$ALERT_FILE"
        ((ALERTS++))
    else
        log "INFO" "CPU usage: ${CPU_INT}%" "$GREEN"
    fi
}

# Check memory (Ubuntu optimized)
check_memory() {
    log "INFO" "Checking memory usage..." "$BLUE"
    
    # Use free with human readable output
    MEM_INFO=$(free -h)
    MEM_USAGE=$(free | awk 'NR==2{printf "%.0f", $3*100/$2}')
    
    if [ "$MEM_USAGE" -gt "$THRESHOLD_MEM" ]; then
        log "ERROR" "Memory usage: ${MEM_USAGE}% (Threshold: ${THRESHOLD_MEM}%)" "$RED"
        echo "Memory: ${MEM_USAGE}%" >> "$ALERT_FILE"
        ((ALERTS++))
    else
        log "INFO" "Memory usage: ${MEM_USAGE}%" "$GREEN"
    fi
    
    # Check swap
    SWAP_USAGE=$(free | awk 'NR==3{printf "%.0f", $3*100/$2}')
    if [ "$SWAP_USAGE" -gt 50 ]; then
        log "WARNING" "High swap usage: ${SWAP_USAGE}%" "$YELLOW"
        echo "Swap: ${SWAP_USAGE}%" >> "$ALERT_FILE"
        ((WARNINGS++))
    fi
}

# Check disk space (Ubuntu specific mounts)
check_disk() {
    log "INFO" "Checking disk space..." "$BLUE"
    
    # Check critical Ubuntu partitions
    CRITICAL_MOUNTS=("/" "/boot" "/boot/efi" "/var" "/home")
    
    for mount in "${CRITICAL_MOUNTS[@]}"; do
        if mountpoint -q "$mount"; then
            USAGE=$(df "$mount" | awk 'NR==2{print $5}' | sed 's/%//')
            if [ "$USAGE" -gt "$THRESHOLD_DISK" ]; then
                log "ERROR" "Disk usage on $mount: ${USAGE}% (Threshold: ${THRESHOLD_DISK}%)" "$RED"
                echo "Disk: $mount ${USAGE}%" >> "$ALERT_FILE"
                ((ALERTS++))
            else
                log "INFO" "Disk usage on $mount: ${USAGE}%" "$GREEN"
            fi
        fi
    done
    
    # Check all mounts
    HIGH_USAGE_MOUNTS=$(df -h | awk 'NR>1 && $5+0 > '"$THRESHOLD_DISK"'{print $6 " (" $5 ")"}' | wc -l)
    if [ "$HIGH_USAGE_MOUNTS" -gt 0 ]; then
        log "WARNING" "$HIGH_USAGE_MOUNTS mount points above ${THRESHOLD_DISK}%" "$YELLOW"
    fi
}

# Check temperature (Ubuntu hardware)
check_temperature() {
    log "INFO" "Checking system temperature..." "$BLUE"
    
    if command -v sensors > /dev/null 2>&1; then
        TEMP=$(sensors | grep -E '(Core|Package|temp)' | grep -oE '[0-9]+\.[0-9]+°C' | head -1 | sed 's/°C//')
        TEMP_INT=$(printf "%.0f" "$TEMP")
        
        if [ "$TEMP_INT" -gt "$THRESHOLD_TEMP" ] 2>/dev/null; then
            log "ERROR" "High temperature: ${TEMP}°C (Threshold: ${THRESHOLD_TEMP}°C)" "$RED"
            echo "Temperature: ${TEMP}°C" >> "$ALERT_FILE"
            ((ALERTS++))
        else
            log "INFO" "Temperature: ${TEMP}°C" "$GREEN"
        fi
    else
        log "INFO" "Install lm-sensors for temperature monitoring: sudo apt install lm-sensors" "$YELLOW"
    fi
}

# Check Ubuntu logs for errors
check_ubuntu_logs() {
    log "INFO" "Checking system logs for errors..." "$BLUE"
    
    # Check syslog for critical errors in last hour
    RECENT_ERRORS=$(grep -i "error\|failed\|critical" "$SYSLOG_FILE" | grep "$(date -d '1 hour ago' '+%b %e %H:')" | wc -l)
    
    if [ "$RECENT_ERRORS" -gt 10 ]; then
        log "ERROR" "High error rate in syslog: $RECENT_ERRORS errors in last hour" "$RED"
        echo "Logs: $RECENT_ERRORS recent errors" >> "$ALERT_FILE"
        ((ALERTS++))
    fi
    
    # Check kernel logs for hardware issues
    KERNEL_ERRORS=$(grep -i "error\|warning" "$KERNEL_LOG" | grep "$(date -d '1 hour ago' '+%b %e %H:')" | wc -l)
    if [ "$KERNEL_ERRORS" -gt 5 ]; then
        log "WARNING" "Kernel errors detected: $KERNEL_ERRORS in last hour" "$YELLOW"
        echo "Kernel: $KERNEL_ERRORS recent errors" >> "$ALERT_FILE"
        ((WARNINGS++))
    fi
}

# Check security updates
check_security() {
    log "INFO" "Checking security status..." "$BLUE"
    
    # Check UFW status
    if command -v ufw > /dev/null 2>&1; then
        UFW_STATUS=$(ufw status | grep "Status:")
        if echo "$UFW_STATUS" | grep -q "active"; then
            log "INFO" "UFW firewall: active" "$GREEN"
        else
            log "WARNING" "UFW firewall: not active" "$YELLOW"
            echo "Security: UFW not active" >> "$ALERT_FILE"
            ((WARNINGS++))
        fi
    fi
    
    # Check fail2ban if installed
    if command -v fail2ban-client > /dev/null 2>&1; then
        if systemctl is-active --quiet fail2ban; then
            log "INFO" "Fail2ban: active" "$GREEN"
        else
            log "WARNING" "Fail2ban: not active" "$YELLOW"
            echo "Security: Fail2ban not active" >> "$ALERT_FILE"
            ((WARNINGS++))
        fi
    fi
    
    # Check AppArmor status
    if systemctl is-active --quiet apparmor; then
        log "INFO" "AppArmor: active" "$GREEN"
    else
        log "WARNING" "AppArmor: not active" "$YELLOW"
        echo "Security: AppArmor not active" >> "$ALERT_FILE"
        ((WARNINGS++))
    fi
}

# Generate summary report
generate_report() {
    log "INFO" "Generating Ubuntu health report..." "$PURPLE"
    
    REPORT_FILE="/tmp/ubuntu_health_report_$(date +%Y%m%d_%H%M%S).txt"
    
    cat > "$REPORT_FILE" << EOF
Ubuntu System Health Report
============================
Generated: $(timestamp)
Hostname: $(hostname)
Ubuntu Version: $(lsb_release -d | cut -f2)
Kernel: $(uname -r)

SYSTEM STATUS:
-------------
CPU Usage: $(mpstat 1 1 | awk '$12 ~ /[0-9.]+/ {print 100 - $12}' | tail -1)% 
Memory Usage: $(free | awk 'NR==2{printf "%.1f%%", $3*100/$2}')
Disk Usage: 
$(df -h / /boot /home /var 2>/dev/null | awk 'NR==1 || /\/$/ || /\/boot/ || /\/home/ || /\/var/')

UPDATES:
--------
Available Updates: $UPDATES
Security Updates: $SECURITY_UPDATES

SERVICES:
---------
$(systemctl list-units --type=service --state=failed | grep failed)

ALERTS: $ALERTS
WARNINGS: $WARNINGS
EOF

    if [ -f "$ALERT_FILE" ] && [ -s "$ALERT_FILE" ]; then
        echo "" >> "$REPORT_FILE"
        echo "ALERT DETAILS:" >> "$REPORT_FILE"
        echo "-------------" >> "$REPORT_FILE"
        cat "$ALERT_FILE" >> "$REPORT_FILE"
    fi
    
    log "INFO" "Report generated: $REPORT_FILE" "$GREEN"
    echo "Full report available at: $REPORT_FILE"
}

# Main function
main() {
    check_sudo
    
    # Initialize files
    > "$LOG_FILE"
    > "$ALERT_FILE"
    
    log "INFO" "Starting Ubuntu System Health Check" "$PURPLE"
    
    # Perform checks
    check_ubuntu_updates
    check_automatic_updates
    check_snap_services
    check_apt_sources
    check_ubuntu_services
    check_cloud_init
    check_landscape
    check_cpu
    check_memory
    check_disk
    check_temperature
    check_ubuntu_logs
    check_security
    
    # Generate summary
    log "INFO" "Ubuntu Health Check Complete" "$PURPLE"
    log "INFO" "Alerts: $ALERTS, Warnings: $WARNINGS" "$([ $ALERTS -gt 0 ] && echo "$RED" || echo "$GREEN")"
    
    generate_report
    
    if [ $ALERTS -gt 0 ]; then
        exit 1
    elif [ $WARNINGS -gt 0 ]; then
        exit 2
    else
        exit 0
    fi
}

# Help function
show_help() {
    echo "Ubuntu System Health Monitor"
    echo "Usage: sudo $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help          Show this help message"
    echo "  -c, --cpu-thresh    CPU threshold percentage (default: 80)"
    echo "  -m, --mem-thresh    Memory threshold percentage (default: 80)"
    echo "  -d, --disk-thresh   Disk threshold percentage (default: 85)"
    echo "  -t, --temp-thresh   Temperature threshold (default: 70)"
    echo ""
    echo "Examples:"
    echo "  sudo $0"
    echo "  sudo $0 --cpu-thresh 90 --disk-thresh 90"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help) show_help; exit 0 ;;
        -c|--cpu-thresh) THRESHOLD_CPU="$2"; shift 2 ;;
        -m|--mem-thresh) THRESHOLD_MEM="$2"; shift 2 ;;
        -d|--disk-thresh) THRESHOLD_DISK="$2"; shift 2 ;;
        -t|--temp-thresh) THRESHOLD_TEMP="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; show_help; exit 1 ;;
    esac
done

main 

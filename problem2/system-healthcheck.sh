#!/bin/bash

# System Health Monitoring Script with Sudo Privileges
# Author: Linux System Administrator
# Description: Monitors CPU, memory, disk space, and processes with sudo

# Configuration
THRESHOLD_CPU=80
THRESHOLD_MEM=80
THRESHOLD_DISK=80
LOG_FILE="/var/log/system_health.log"
ALERT_FILE="/tmp/system_alerts.txt"

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m' # No Color

# Check if running with sudo
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        echo "Running with root privileges"
    else
        echo "This script requires sudo privileges. Please run with:"
        echo "sudo $0"
        exit 1
    fi
}

# Initialize alert file
initialize_alert_file() {
    sudo touch "$ALERT_FILE"
    sudo chmod 644 "$ALERT_FILE"
    sudo echo "" > "$ALERT_FILE"
}

# Timestamp function
timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

# Log function with sudo
log_message() {
    local message="$1"
    local color="$2"
    
    echo -e "${color}$(timestamp) - $message${NC}"
    
    # Log to file with sudo
    sudo bash -c "echo '$(timestamp) - $message' >> '$LOG_FILE'"
}

# Check CPU usage with elevated privileges
check_cpu() {
    local cpu_usage=$(sudo top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    local cpu_usage_int=$(printf "%.0f" "$cpu_usage")
    
    if [ "$cpu_usage_int" -gt "$THRESHOLD_CPU" ]; then
        log_message "ALERT: CPU usage is ${cpu_usage_int}% (Threshold: ${THRESHOLD_CPU}%)" "$RED"
        sudo bash -c "echo 'CPU: ${cpu_usage_int}%' >> '$ALERT_FILE'"
        return 1
    else
        log_message "OK: CPU usage is ${cpu_usage_int}%" "$GREEN"
        return 0
    fi
}

# Check Memory usage with sudo
check_memory() {
    local mem_info=$(sudo free | grep Mem)
    local total_mem=$(echo "$mem_info" | awk '{print $2}')
    local used_mem=$(echo "$mem_info" | awk '{print $3}')
    local mem_usage=$((used_mem * 100 / total_mem))
    
    if [ "$mem_usage" -gt "$THRESHOLD_MEM" ]; then
        log_message "ALERT: Memory usage is ${mem_usage}% (Threshold: ${THRESHOLD_MEM}%)" "$RED"
        sudo bash -c "echo 'Memory: ${mem_usage}%' >> '$ALERT_FILE'"
        return 1
    else
        log_message "OK: Memory usage is ${mem_usage}%" "$GREEN"
        return 0
    fi
}

# Check Disk space with sudo for all filesystems
check_disk() {
    local disk_alerts=0
    
    # Check all filesystems including system ones
    sudo df -h | while read output; do
        local filesystem=$(echo "$output" | awk '{print $1}')
        local usage=$(echo "$output" | awk '{print $5}' | sed 's/%//g' 2>/dev/null)
        local mount_point=$(echo "$output" | awk '{print $6}')
        
        # Skip header and invalid lines
        if [[ "$filesystem" == "Filesystem" ]] || [[ -z "$usage" ]] || ! [[ "$usage" =~ ^[0-9]+$ ]]; then
            continue
        fi
        
        if [ "$usage" -gt "$THRESHOLD_DISK" ]; then
            log_message "ALERT: Disk usage on $filesystem ($mount_point) is ${usage}% (Threshold: ${THRESHOLD_DISK}%)" "$RED"
            sudo bash -c "echo 'Disk: $filesystem $usage%' >> '$ALERT_FILE'"
            disk_alerts=$((disk_alerts + 1))
        else
            log_message "OK: Disk usage on $filesystem ($mount_point) is ${usage}%" "$GREEN"
        fi
    done
    
    return $disk_alerts
}

# Check critical processes with sudo
check_processes() {
    local critical_processes=("sshd" "nginx" "apache2" "mysql" "postgresql" "docker" "rsyslog" "cron")
    local process_alerts=0
    
    for process in "${critical_processes[@]}"; do
        if sudo pgrep -x "$process" >/dev/null 2>&1; then
            log_message "OK: Process $process is running" "$GREEN"
        else
            log_message "ALERT: Process $process is not running" "$RED"
            sudo bash -c "echo 'Process: $process not running' >> '$ALERT_FILE'"
            process_alerts=$((process_alerts + 1))
        fi
    done
    
    return $process_alerts
}

# Check system load with sudo
check_load() {
    local load=$(sudo uptime | awk -F'load average:' '{print $2}' | cut -d, -f1 | sed 's/ //g')
    local cores=$(sudo nproc)
    local load_per_core=$(echo "scale=2; $load / $cores" | bc)
    
    if (( $(echo "$load_per_core > 1.0" | bc -l) )); then
        log_message "WARNING: System load is high: $load (Per core: $load_per_core)" "$YELLOW"
        sudo bash -c "echo 'Load: $load' >> '$ALERT_FILE'"
        return 1
    else
        log_message "OK: System load is normal: $load" "$GREEN"
        return 0
    fi
}

# Check system services with systemctl
check_services() {
    local critical_services=("ssh" "nginx" "apache2" "mysql" "postgresql" "docker" "rsyslog" "cron")
    local service_alerts=0
    
    for service in "${critical_services[@]}"; do
        if sudo systemctl is-active --quiet "$service" 2>/dev/null; then
            log_message "OK: Service $service is active" "$GREEN"
        else
            # Check if service exists before reporting error
            if sudo systemctl list-unit-files | grep -q "$service.service"; then
                log_message "ALERT: Service $service is not active" "$RED"
                sudo bash -c "echo 'Service: $service not active' >> '$ALERT_FILE'"
                service_alerts=$((service_alerts + 1))
            else
                log_message "INFO: Service $service is not installed" "$NC"
            fi
        fi
    done
    
    return $service_alerts
}

# Check system temperature (if sensors are available)
check_temperature() {
    if command -v sensors >/dev/null 2>&1; then
        local temp=$(sudo sensors | grep -E '(Core|Package|temp)' | grep -oE '[0-9]+\.[0-9]+°C' | head -1 | sed 's/°C//')
        local temp_int=$(printf "%.0f" "$temp")
        
        if [ "$temp_int" -gt 80 ] 2>/dev/null; then
            log_message "WARNING: High temperature detected: ${temp}°C" "$YELLOW"
            sudo bash -c "echo 'Temperature: ${temp}°C' >> '$ALERT_FILE'"
            return 1
        else
            log_message "OK: Temperature is normal: ${temp}°C" "$GREEN"
            return 0
        fi
    else
        log_message "INFO: lm-sensors not installed, skipping temperature check" "$NC"
        return 0
    fi
}

# Check zombie processes
check_zombies() {
    local zombie_count=$(sudo ps aux | awk '{print $8}' | grep -c Z)
    
    if [ "$zombie_count" -gt 0 ]; then
        log_message "ALERT: Found $zombie_count zombie processes" "$RED"
        sudo bash -c "echo 'Zombies: $zombie_count processes' >> '$ALERT_FILE'"
        return 1
    else
        log_message "OK: No zombie processes found" "$GREEN"
        return 0
    fi
}

# Check system updates
check_updates() {
    if [ -f /etc/redhat-release ]; then
        # RedHat/CentOS
        local updates=$(sudo yum check-update --quiet 2>/dev/null | wc -l)
    elif [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        sudo apt-get update >/dev/null 2>&1
        local updates=$(sudo apt-get upgrade -s | grep -c "^Inst")
    else
        log_message "INFO: Unknown distribution, skipping update check" "$NC"
        return 0
    fi
    
    if [ "$updates" -gt 50 ]; then
        log_message "WARNING: $updates packages need updates" "$YELLOW"
        sudo bash -c "echo 'Updates: $updates packages pending' >> '$ALERT_FILE'"
        return 1
    elif [ "$updates" -gt 0 ]; then
        log_message "INFO: $updates packages need updates" "$NC"
        return 0
    else
        log_message "OK: System is up to date" "$GREEN"
        return 0
    fi
}

# Main monitoring function
main() {
    check_sudo
    
    # Create log directory if it doesn't exist
    sudo mkdir -p "$(dirname "$LOG_FILE")"
    sudo touch "$LOG_FILE"
    sudo chmod 644 "$LOG_FILE"
    
    initialize_alert_file
    
    log_message "=== Starting System Health Check ===" "$NC"
    
    local alerts=0
    
    check_cpu || alerts=$((alerts + 1))
    check_memory || alerts=$((alerts + 1))
    check_disk || alerts=$((alerts + 1))
    check_processes || alerts=$((alerts + 1))
    check_services || alerts=$((alerts + 1))
    check_load || alerts=$((alerts + 1))
    check_temperature || alerts=$((alerts + 1))
    check_zombies || alerts=$((alerts + 1))
    check_updates || alerts=$((alerts + 1))
    
    # Summary
    log_message "=== System Health Check Complete ===" "$NC"
    
    if [ "$alerts" -gt 0 ]; then
        log_message "ALERT: $alerts issues detected. Check $ALERT_FILE for details." "$RED"
        
        # Add summary to alert file
        sudo bash -c "cat >> '$ALERT_FILE'" << EOF

=== System Alerts Summary ===
Total alerts: $alerts
Generated: $(timestamp)
System: $(hostname)
EOF
        
        # Display alert file content
        echo ""
        echo "=== Alert Details ==="
        sudo cat "$ALERT_FILE"
    else
        log_message "SUCCESS: All systems are operating within normal parameters." "$GREEN"
        sudo rm -f "$ALERT_FILE"
    fi
    
    log_message "Detailed log available at: $LOG_FILE" "$NC"
}

# Help function
show_help() {
    echo "System Health Monitoring Script (with Sudo)"
    echo "Usage: sudo $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -h, --help     Show this help message"
    echo "  -c, --cpu      Set CPU threshold (default: 80)"
    echo "  -m, --mem      Set memory threshold (default: 80)"
    echo "  -d, --disk     Set disk threshold (default: 80)"
    echo "  -l, --log      Set log file path (default: /var/log/system_health.log)"
    echo ""
    echo "Examples:"
    echo "  sudo $0                          # Run with default thresholds"
    echo "  sudo $0 -c 90 -m 85 -d 90       # Run with custom thresholds"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -c|--cpu)
            THRESHOLD_CPU="$2"
            shift 2
            ;;
        -m|--mem)
            THRESHOLD_MEM="$2"
            shift 2
            ;;
        -d|--disk)
            THRESHOLD_DISK="$2"
            shift 2
            ;;
        -l|--log)
            LOG_FILE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
done

# Run main function
main  

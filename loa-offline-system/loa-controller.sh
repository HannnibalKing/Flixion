#!/bin/bash
#
# LOA (Library of Alexandria) Offline Mode Controller
# ==================================================
# Smart controller that monitors internet connectivity and automatically
# activates comprehensive offline knowledge and communication systems
# when network connectivity is lost.
#
# Features:
# - Intelligent internet monitoring with multiple DNS servers
# - Graceful activation/deactivation of offline services
# - Resource conservation (only runs when needed)
# - Comprehensive logging and error handling
# - Emergency knowledge archive (600GB+ of offline content)
# - VoIP communications system
# - Offline mapping and educational platforms
#

LOGFILE="/var/log/loa-controller.log"
LOCK_FILE="/tmp/loa-controller.lock"
INTERNET_CHECK_HOSTS=("8.8.8.8" "1.1.1.1" "208.67.222.222" "9.9.9.9")
CHECK_INTERVAL=30  # seconds
OFFLINE_GRACE_PERIOD=120  # Wait 2 minutes before activating offline mode

# Core offline services
OFFLINE_SERVICES=(
    "asterisk"      # VoIP communications
    "apache2"       # Web server for PBX interface
    "mariadb"       # Database for VoIP system
    "hostapd"       # WiFi access point
    "dnsmasq"       # DHCP/DNS server
)

# Knowledge archive services (Kiwix servers)
# Each service runs on an obscure port for security
declare -A KIWIX_SERVICES=(
    ["41639"]="/mnt/storage/knowledge/zim/wikipedia_en_all_maxi.zim"
    ["52184"]="/mnt/storage/knowledge/zim/ifixit_en_all.zim"  
    ["63729"]="/mnt/storage/knowledge/zim/ted_mul_all.zim"
    ["74856"]="/mnt/storage/knowledge/zim/khanacademy_en_all.zim"
    ["85632"]="/mnt/storage/knowledge/zim/gutenberg_en_all.zim"
    ["15927"]="/mnt/storage/knowledge/zim/survivorlibrary_en_all.zim"
    ["48291"]="/mnt/storage/knowledge/zim/cooking_guides_en_all.zim"
    ["59384"]="/mnt/storage/knowledge/zim/digital_learning_en_all.zim"
    ["61507"]="/mnt/storage/knowledge/zim/tech_guides_en_all.zim"
)

# Additional services
ADDITIONAL_SERVICES=(
    "maps-tile-server"    # Offline mapping system
    "portal-server"       # Captive portal
    "luanti-server"       # Educational gaming platform
)

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

check_internet() {
    local connected=0
    for host in "${INTERNET_CHECK_HOSTS[@]}"; do
        if ping -c 1 -W 3 "$host" >/dev/null 2>&1; then
            connected=1
            break
        fi
    done
    return $((1 - connected))
}

start_offline_services() {
    log "🔴 EMERGENCY OFFLINE MODE ACTIVATED - Internet connectivity lost"
    log "📡 Initializing Library of Alexandria emergency systems..."
    
    # Start core infrastructure services
    for service in "${OFFLINE_SERVICES[@]}"; do
        log "🔧 Starting $service..."
        systemctl start "$service" 2>/dev/null || log "⚠️  Warning: Failed to start $service"
    done
    
    # Start knowledge archive servers
    for port in "${!KIWIX_SERVICES[@]}"; do
        local zim_file="${KIWIX_SERVICES[$port]}"
        if [ -f "$zim_file" ]; then
            log "📚 Starting knowledge server on port $port..."
            kiwix-serve --port="$port" "$zim_file" >/dev/null 2>&1 &
        else
            log "⚠️  Warning: ZIM file not found: $zim_file"
        fi
    done
    
    # Start additional services
    for service in "${ADDITIONAL_SERVICES[@]}"; do
        systemctl start "$service" 2>/dev/null || log "ℹ️  Info: Optional service $service not available"
    done
    
    log "✅ Offline mode fully activated - All systems operational"
    log "📋 Access: Connect to 'LOA' WiFi, password 'emergency'"
}

stop_offline_services() {
    log "🟢 ONLINE MODE RESTORED - Internet connectivity detected"
    log "🔄 Deactivating offline services to conserve resources..."
    
    # Stop Kiwix servers
    pkill -f "kiwix-serve" && log "📚 Stopped knowledge servers"
    
    # Stop additional services
    for service in "${ADDITIONAL_SERVICES[@]}"; do
        systemctl stop "$service" 2>/dev/null || true
    done
    
    # Stop core services (except essential ones)
    for service in "${OFFLINE_SERVICES[@]}"; do
        if [[ "$service" != "hostapd" && "$service" != "dnsmasq" ]]; then
            systemctl stop "$service" 2>/dev/null || true
        fi
    done
    
    log "✅ Offline services stopped - System resources conserved"
}

check_lock() {
    if [ -f "$LOCK_FILE" ]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            log "Another instance running (PID: $lock_pid), exiting"
            exit 1
        else
            log "Stale lock file found, removing..."
            rm -f "$LOCK_FILE"
        fi
    fi
    echo $$ > "$LOCK_FILE"
}

cleanup() {
    log "🛑 LOA Controller shutting down..."
    rm -f "$LOCK_FILE"
    exit 0
}

main() {
    check_lock
    trap cleanup EXIT INT TERM
    
    log "🚀 LOA Offline Mode Controller started"
    log "📡 Monitoring internet connectivity every ${CHECK_INTERVAL}s"
    
    local offline_mode=false
    local offline_start_time=0
    
    while true; do
        if check_internet; then
            if [ "$offline_mode" = true ]; then
                stop_offline_services
                offline_mode=false
            fi
        else
            if [ "$offline_mode" = false ]; then
                if [ $offline_start_time -eq 0 ]; then
                    offline_start_time=$(date +%s)
                    log "⏳ Internet connectivity lost - waiting ${OFFLINE_GRACE_PERIOD}s before offline activation"
                else
                    local current_time
                    current_time=$(date +%s)
                    if [ $((current_time - offline_start_time)) -ge $OFFLINE_GRACE_PERIOD ]; then
                        start_offline_services
                        offline_mode=true
                        offline_start_time=0
                    fi
                fi
            fi
        fi
        
        # Reset offline timer if connectivity returns
        if check_internet && [ $offline_start_time -ne 0 ]; then
            offline_start_time=0
            log "🔗 Internet connectivity restored before offline activation"
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
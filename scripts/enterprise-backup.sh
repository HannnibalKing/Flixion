#!/bin/bash
#
# Enterprise Backup System using Borg
# ====================================
# Automated, encrypted, deduplicated backups with comprehensive logging
# and error handling for production environments.
#

# Configuration
REPO_BASE="/mnt/backups/borg"
BACKUP_NAME="homelab-$(hostname)"
REPO_PATH="$REPO_BASE/$BACKUP_NAME"
LOGFILE="/var/log/borg-backup.log"
LOCK_FILE="/tmp/borg-backup.lock"

# Backup sources
BACKUP_SOURCES=(
    "/mnt/docker/configs"           # Docker configurations
    "/etc"                          # System configurations
    "/home/*/scripts"               # Custom scripts
    "/var/lib/docker/volumes"       # Docker persistent data
    "/opt"                          # Additional software
)

# Exclude patterns
EXCLUDE_PATTERNS=(
    "*.log"
    "*.tmp"
    "*cache*"
    "*Cache*"
    "*.pyc"
    "__pycache__"
    "node_modules"
    ".git"
)

# Notification settings
DISCORD_WEBHOOK="YOUR_DISCORD_WEBHOOK_URL"
EMAIL_RECIPIENT="admin@example.com"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOGFILE"
}

# Error handling
error_exit() {
    log "ERROR: $1"
    send_notification "❌ Backup Failed" "$1" "16711680"  # Red color
    cleanup
    exit 1
}

# Send notifications
send_notification() {
    local title="$1"
    local message="$2"
    local color="${3:-65280}"  # Default green
    
    # Discord notification
    if [[ -n "$DISCORD_WEBHOOK" ]]; then
        curl -H "Content-Type: application/json" \
             -X POST \
             -d "{\"embeds\":[{\"title\":\"$title\",\"description\":\"$message\",\"color\":$color}]}" \
             "$DISCORD_WEBHOOK" &>/dev/null
    fi
    
    # Email notification
    if command -v mail >/dev/null 2>&1; then
        echo "$message" | mail -s "$title" "$EMAIL_RECIPIENT" &>/dev/null
    fi
}

# Check prerequisites
check_prerequisites() {
    # Check if borg is installed
    if ! command -v borg >/dev/null 2>&1; then
        error_exit "Borg backup not installed"
    fi
    
    # Check repository directory
    if [[ ! -d "$REPO_BASE" ]]; then
        log "Creating repository base directory: $REPO_BASE"
        mkdir -p "$REPO_BASE" || error_exit "Cannot create repository directory"
    fi
    
    # Check lock file
    if [[ -f "$LOCK_FILE" ]]; then
        local lock_pid
        lock_pid=$(cat "$LOCK_FILE")
        if kill -0 "$lock_pid" 2>/dev/null; then
            error_exit "Another backup process is running (PID: $lock_pid)"
        else
            log "Removing stale lock file"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
}

# Initialize repository if needed
init_repository() {
    if [[ ! -d "$REPO_PATH" ]]; then
        log "Initializing new Borg repository: $REPO_PATH"
        borg init --encryption=repokey-blake2 "$REPO_PATH" || error_exit "Failed to initialize repository"
        log "Repository initialized successfully"
    fi
}

# Create backup
create_backup() {
    local archive_name="${BACKUP_NAME}-$(date +%Y%m%d-%H%M%S)"
    
    # Build exclude arguments
    local exclude_args=()
    for pattern in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args+=(--exclude "$pattern")
    done
    
    log "Starting backup: $archive_name"
    log "Backup sources: ${BACKUP_SOURCES[*]}"
    
    # Set environment variables
    export BORG_RELOCATED_REPO_ACCESS_IS_OK=yes
    export BORG_UNKNOWN_UNENCRYPTED_REPO_ACCESS_IS_OK=yes
    
    # Create backup with progress and stats
    borg create \
        --verbose \
        --stats \
        --progress \
        --compression zstd,3 \
        --exclude-caches \
        "${exclude_args[@]}" \
        "$REPO_PATH::$archive_name" \
        "${BACKUP_SOURCES[@]}" \
        2>&1 | tee -a "$LOGFILE"
    
    local backup_result=${PIPESTATUS[0]}
    
    if [[ $backup_result -eq 0 ]]; then
        log "Backup completed successfully: $archive_name"
    else
        error_exit "Backup failed with exit code: $backup_result"
    fi
}

# Prune old backups
prune_backups() {
    log "Pruning old backups..."
    
    borg prune \
        --list \
        --prefix "$BACKUP_NAME-" \
        --show-rc \
        --keep-daily 7 \
        --keep-weekly 4 \
        --keep-monthly 6 \
        --keep-yearly 2 \
        "$REPO_PATH" \
        2>&1 | tee -a "$LOGFILE"
    
    local prune_result=${PIPESTATUS[0]}
    
    if [[ $prune_result -eq 0 ]]; then
        log "Pruning completed successfully"
    else
        error_exit "Pruning failed with exit code: $prune_result"
    fi
}

# Verify backup integrity
verify_backup() {
    log "Verifying repository integrity..."
    
    borg check --verify-data "$REPO_PATH" 2>&1 | tee -a "$LOGFILE"
    
    local check_result=${PIPESTATUS[0]}
    
    if [[ $check_result -eq 0 ]]; then
        log "Repository verification completed successfully"
    else
        error_exit "Repository verification failed with exit code: $check_result"
    fi
}

# Get backup statistics
get_statistics() {
    log "Gathering backup statistics..."
    
    # Repository info
    borg info "$REPO_PATH" 2>&1 | tee -a "$LOGFILE"
    
    # List recent archives
    log "Recent archives:"
    borg list --short "$REPO_PATH" | tail -5 | tee -a "$LOGFILE"
}

# Cleanup function
cleanup() {
    log "Cleaning up..."
    rm -f "$LOCK_FILE"
}

# Main execution
main() {
    local start_time
    start_time=$(date +%s)
    
    log "=== Borg Backup Started ==="
    log "Hostname: $(hostname)"
    log "Repository: $REPO_PATH"
    
    # Trap signals for cleanup
    trap cleanup EXIT INT TERM
    
    check_prerequisites
    init_repository
    create_backup
    prune_backups
    verify_backup
    get_statistics
    
    local end_time
    end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    log "=== Backup Completed Successfully ==="
    log "Duration: ${duration} seconds"
    
    # Send success notification
    send_notification "✅ Backup Successful" \
        "Homelab backup completed in ${duration} seconds" \
        "65280"  # Green color
}

# Run main function if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
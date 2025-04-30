#!/usr/bin/env bash

# syncutil.sh - File/Folder Synchronization Utility
# Author: gfedder
# Version: 1.0.0

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default settings
CONFIG_FILE="$HOME/.config/syncutil/rules.conf"
VERBOSE=true
DRY_RUN=false
SHOW_RULES=false
OPERATION="sync"

# Helper functions
print_usage() {
    echo -e "${BLUE}Usage:${NC} $(basename "$0") [options] [command]"
    echo ""
    echo "Commands:"
    echo "  sync               Execute the synchronization (default)"
    echo "  list               List all configured sync rules"
    echo "  add <src> <dest>   Add a new synchronization rule"
    echo "  remove <index>     Remove a rule by its index"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run      Show what would be copied without making changes"
    echo "  -q, --quiet        Suppress all output except errors"
    echo "  -v, --verbose      Show detailed output (default)"
    echo "  -h, --help         Show this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") sync              # Run synchronization"
    echo "  $(basename "$0") -d sync           # Dry run synchronization"
    echo "  $(basename "$0") list              # List all rules"
    echo "  $(basename "$0") add ~/docs /backup/docs  # Add a new rule"
    echo "  $(basename "$0") remove 2          # Remove rule at index 2"
}

log_info() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${GREEN}[INFO]${NC} $1"
    fi
}

log_warn() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${YELLOW}[WARN]${NC} $1"
    fi
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Ensure config directory exists
ensure_config_dir() {
    CONFIG_DIR=$(dirname "$CONFIG_FILE")
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        if [ $? -ne 0 ]; then
            log_error "Failed to create config directory: $CONFIG_DIR"
            exit 1
        fi
        log_info "Created config directory: $CONFIG_DIR"
    fi
    
    # Create config file if it doesn't exist
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
        if [ $? -ne 0 ]; then
            log_error "Failed to create config file: $CONFIG_FILE"
            exit 1
        fi
        log_info "Created config file: $CONFIG_FILE"
    fi
}

# List all sync rules
list_rules() {
    ensure_config_dir
    
    if [ ! -s "$CONFIG_FILE" ]; then
        log_info "No synchronization rules defined."
        return 0
    fi
    
    echo -e "${BLUE}Synchronization Rules:${NC}"
    echo -e "${BLUE}-------------------${NC}"
    
    index=0
    while IFS="|" read -r src dest; do
        index=$((index + 1))
        echo -e "${BLUE}$index.${NC} Source: $src"
        echo -e "   Destination: $dest"
    done < "$CONFIG_FILE"
}

# Add a new sync rule
add_rule() {
    ensure_config_dir
    
    if [ $# -lt 2 ]; then
        log_error "Missing source and destination parameters"
        print_usage
        exit 1
    fi
    
    src="$1"
    dest="$2"
    
    # Validate source exists
    if [ ! -e "$src" ]; then
        log_error "Source does not exist: $src"
        exit 1
    fi
    
    # Add rule to config file
    echo "$src|$dest" >> "$CONFIG_FILE"
    log_info "Added new sync rule: $src -> $dest"
}

# Remove a sync rule
remove_rule() {
    ensure_config_dir
    
    if [ $# -lt 1 ]; then
        log_error "Missing rule index parameter"
        print_usage
        exit 1
    fi
    
    index="$1"
    
    # Validate index is a number
    if ! [[ "$index" =~ ^[0-9]+$ ]]; then
        log_error "Index must be a number"
        exit 1
    fi
    
    # Check if file is empty
    if [ ! -s "$CONFIG_FILE" ]; then
        log_error "No rules to remove"
        exit 1
    fi
    
    # Count lines in config file
    line_count=$(wc -l < "$CONFIG_FILE")
    
    # Validate index is within range
    if [ "$index" -lt 1 ] || [ "$index" -gt "$line_count" ]; then
        log_error "Index out of range (1-$line_count)"
        exit 1
    fi
    
    # Create a temporary file
    temp_file=$(mktemp)
    
    # Copy all lines except the one to be removed
    current_line=0
    while IFS= read -r line; do
        current_line=$((current_line + 1))
        if [ "$current_line" -ne "$index" ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$CONFIG_FILE"
    
    # Replace config file with temp file
    mv "$temp_file" "$CONFIG_FILE"
    
    log_info "Removed rule at index $index"
}

# Execute sync for a single rule
sync_rule() {
    src="$1"
    dest="$2"
    
    # Skip if source doesn't exist
    if [ ! -e "$src" ]; then
        log_warn "Source does not exist: $src"
        return 1
    fi
    
    # Create destination directory if it doesn't exist
    if [ ! -d "$(dirname "$dest")" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would create directory: $(dirname "$dest")"
        else
            mkdir -p "$(dirname "$dest")"
            if [ $? -ne 0 ]; then
                log_error "Failed to create destination directory: $(dirname "$dest")"
                return 1
            fi
            log_info "Created directory: $(dirname "$dest")"
        fi
    fi
    
    # Use rsync to copy files
    if [ "$DRY_RUN" = true ]; then
        if [ "$VERBOSE" = true ]; then
            rsync -ain --delete "$src" "$dest"
        else
            # Capture rsync output to check if changes would be made
            changes=$(rsync -ain --delete "$src" "$dest" | grep -v "^$" | wc -l)
            if [ "$changes" -gt 0 ]; then
                log_info "[DRY RUN] Would copy: $src -> $dest"
            else
                log_info "[DRY RUN] No changes needed: $src -> $dest"
            fi
        fi
    else
        if [ "$VERBOSE" = true ]; then
            # Use rsync with verbose output
            rsync_output=$(rsync -ai --delete "$src" "$dest")
            exit_code=$?
            
            if [ $exit_code -ne 0 ]; then
                log_error "Sync failed: $src -> $dest"
                return 1
            fi
            
            # Check if any files were copied
            if [ -n "$rsync_output" ]; then
                echo "$rsync_output"
                log_info "Sync completed: $src -> $dest"
            else
                log_info "No changes needed: $src -> $dest"
            fi
        else
            # Use rsync with quiet output
            rsync_output=$(rsync -ai --delete "$src" "$dest" 2>&1)
            exit_code=$?
            
            if [ $exit_code -ne 0 ]; then
                log_error "Sync failed: $src -> $dest"
                return 1
            fi
            
            # Check if any files were copied
            if [ -n "$rsync_output" ]; then
                log_info "Sync completed: $src -> $dest"
            else
                log_info "No changes needed: $src -> $dest"
            fi
        fi
    fi
    
    return 0
}

# Execute sync for all rules
sync_all() {
    ensure_config_dir
    
    if [ ! -s "$CONFIG_FILE" ]; then
        log_info "No synchronization rules defined."
        return 0
    fi
    
    log_info "Starting synchronization..."
    
    # Track success/failure counts
    success_count=0
    failure_count=0
    
    # Process each rule
    while IFS="|" read -r src dest; do
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Processing: $src -> $dest"
        else
            log_info "Processing: $src -> $dest"
        fi
        
        # Execute sync
        if sync_rule "$src" "$dest"; then
            success_count=$((success_count + 1))
        else
            failure_count=$((failure_count + 1))
        fi
    done < "$CONFIG_FILE"
    
    # Summary
    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Synchronization completed"
    else
        log_info "Synchronization completed"
    fi
    
    if [ $failure_count -gt 0 ]; then
        log_warn "$success_count succeeded, $failure_count failed"
    else
        log_info "All $success_count rules processed successfully"
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        sync)
            OPERATION="sync"
            shift
            ;;
        list)
            OPERATION="list"
            shift
            ;;
        add)
            OPERATION="add"
            shift
            SRC="$1"
            shift
            DEST="$1"
            shift
            ;;
        remove)
            OPERATION="remove"
            shift
            INDEX="$1"
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -q|--quiet)
            VERBOSE=false
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            log_error "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# Execute requested operation
case "$OPERATION" in
    sync)
        sync_all
        ;;
    list)
        list_rules
        ;;
    add)
        add_rule "$SRC" "$DEST"
        ;;
    remove)
        remove_rule "$INDEX"
        ;;
    *)
        log_error "Unknown operation: $OPERATION"
        print_usage
        exit 1
        ;;
esac

exit 0

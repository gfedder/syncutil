#!/usr/bin/env bash

# File sync utility script
# Author: gfedder
# Version: 1.1.0

# Terminal color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default settings
CONFIG_FILE="$HOME/.config/syncutil/rules.conf"
VERBOSE=true
DRY_RUN=false
SHOW_RULES=false
OPERATION="sync"
FORCE=false

UPDATE_COUNT=0

# Helper functions
print_usage() {
    echo -e "${BLUE}Usage:${NC} $(basename "$0") [options] [command]"
    echo ""
    echo "Commands:"
    echo "  sync               Execute the synchronization (default)"
    echo "  list               Display all synchronization rules"
    echo "  add <src> <dest>   Add a new synchronizatoin rule"
    echo "  remove <index>     Remove a rule by its index"
    echo ""
    echo "Options:"
    echo "  -d, --dry-run      Preview without making changes"
    echo "  -q, --quiet        Suppress all non-error output"
    echo "  -v, --verbose      Show detailed output (default)"
    echo "  -f, --force        Skip deletion confirmation"
    echo "  -h, --help         Display this help message"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") sync              # Start sync"
    echo "  $(basename "$0") -d sync           # Preview sync"
    echo "  $(basename "$0") -f sync           # Sync with forced deletions"
    echo "  $(basename "$0") list              # Show all rules"
    echo "  $(basename "$0") add ~/docs /backup/docs  # Add a rule"
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

# New function: Identify files for deletion
get_deletions() {
    src="$1"
    dest="$2"
    
    # Add trailing slashes for directories
    if [ -d "$src" ]; then
        src="${src%/}/"
    fi
    
    if [ -d "$dest" ]; then
        dest="${dest%/}/"
    fi
    
    # Employ rsync to list deletions
    rsync -ain --delete "$src" "$dest" | grep "^*deleting" | sed 's/^*deleting //'
}

# New function: Confirm deletions with user
confirm_deletions() {
    if [ -z "$1" ]; then
        return 0  # No deletions, confirmed
    fi
    
    echo -e "${YELLOW}Items to be deleted:${NC}"
    echo "$1"
    echo ""
    
    read -p "Proceed with deletion? [y/N] " response
    case "$response" in
        [yY][eE][sS]|[yY]) 
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# Ensure existence of config directory
ensure_config_dir() {
    CONFIG_DIR=$(dirname "$CONFIG_FILE")
    if [ ! -d "$CONFIG_DIR" ]; then
        mkdir -p "$CONFIG_DIR"
        if [ $? -ne 0 ]; then
            log_error "Failed to create config directory: $CONFIG_DIR"
            exit 1
        fi
        log_info "Config directory created: $CONFIG_DIR"
	UPDATE_COUNT=$((UPDATE_COUNT + 1))
    fi
    
    # Create config file if absent
    if [ ! -f "$CONFIG_FILE" ]; then
        touch "$CONFIG_FILE"
        if [ $? -ne 0 ]; then
            log_error "Failed to create config file: $CONFIG_FILE"
            exit 1
        fi
        log_info "Config file created: $CONFIG_FILE"
	UPDATE_COUNT=$((UPDATE_COUNT + 1))
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
    echo -e "${BLUE}--------------------${NC}"
    
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
    
    # Verify source existence
    if [ ! -e "$src" ]; then
        log_error "Source not found: $src"
        exit 1
    fi
    
    # Include rule in config file
    echo "$src|$dest" >> "$CONFIG_FILE"
    log_info "New sync rule added: $src -> $dest"
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
    
    # Confirm index is a number
    if ! [[ "$index" =~ ^[0-9]+$ ]]; then
        log_error "Index must be a number"
        exit 1
    fi
    
    # Check for empty file
    if [ ! -s "$CONFIG_FILE" ]; then
        log_error "No rules to remove"
        exit 1
    fi
    
    # Count lines in config file
    line_count=$(wc -l < "$CONFIG_FILE")
    
    # Validate index range
    if [ "$index" -lt 1 ] || [ "$index" -gt "$line_count" ]; then
        log_error "Index out of range (1-$line_count)"
        exit 1
    fi
    
    # Create temporary file
    temp_file=$(mktemp)
    
    # Copy all lines except the one to remove
    current_line=0
    while IFS= read -r line; do
        current_line=$((current_line + 1))
        if [ "$current_line" -ne "$index" ]; then
            echo "$line" >> "$temp_file"
        fi
    done < "$CONFIG_FILE"
    
    # Replace config file with temp file
    mv "$temp_file" "$CONFIG_FILE"
    
    log_info "Rule removed at index $index"
}

# Execute sync for a single rule
sync_rule() {
    src="$1"
    dest="$2"
    
    # Skip if source does not exist
    if [ ! -e "$src" ]; then
        log_warn "Source not found: $src"
        return 1
    fi
    
    # Create destination directory if absent
    if [ ! -d "$(dirname "$dest")" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would create directory: $(dirname "$dest")"
	    UPDATE_COUNT=$((UPDATE_COUNT + 1))
        else
            mkdir -p "$(dirname "$dest")"
            if [ $? -ne 0 ]; then
                log_error "Failed to create destination directory: $(dirname "$dest")"
                return 1
            fi
            log_info "Directory created: $(dirname "$dest")"
	    UPDATE_COUNT=$((UPDATE_COUNT + 1))
        fi
    fi
    
    # Check for deletions
    deletions=$(get_deletions "$src" "$dest")
    
    # Initialize rsync delete flag
    rsync_delete_flag="--delete"
    
    # Handle deletions based on mode
    if [ -n "$deletions" ]; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Items to be deleted:"
	    # TODO: figure out how to add to UPDATE_COUNT
            echo "$deletions"
            echo ""
        elif [ "$FORCE" = false ]; then
            if ! confirm_deletions "$deletions"; then
                log_info "Deletions skipped by user"
                rsync_delete_flag=""
	    else
		# Count number of deletions
		deletion_count=$(echo "$deletions" | wc -l)
		UPDATE_COUNT=$((UPDATE_COUNT + deletion_count))
            fi
        else
	    # Count number of deletions
	    deletion_count=$(echo "$deletions" | wc -l)
	    UPDATE_COUNT=$((UPDATE_COUNT + deletion_count))

            log_info "Items to be deleted (--force enabled):"
            echo "$deletions"
            echo ""
        fi
    fi
    
    # Use rsync to copy files
    if [ "$DRY_RUN" = true ]; then
        if [ "$VERBOSE" = true ]; then
            rsync -ain $rsync_delete_flag "$src" "$dest"
        else
            changes=$(rsync -ain $rsync_delete_flag "$src" "$dest" | grep -v "^$" | wc -l)
            if [ "$changes" -gt 0 ]; then
                log_info "[DRY RUN] Would copy: $src -> $dest"
            else
                log_info "[DRY RUN] No changes needed: $src -> $dest"
            fi
        fi
    else
        if [ "$VERBOSE" = true ]; then
            rsync_output=$(rsync -ai $rsync_delete_flag "$src" "$dest")
            exit_code=$?
            
            if [ $exit_code -ne 0 ]; then
                log_error "Sync failed: $src -> $dest"
                return 1
            fi
            
            if [ -n "$rsync_output" ]; then
                echo "$rsync_output"
		# Count changes by counting non-empty lines in rsync output
		change_count=$(echo "$rsync_output" | grep -v "^$" | wc -l)
		UPDATE_COUNT=$((UPDATE_COUNT + change_count))
                log_info "Sync completed: $src -> $dest"
            else
                log_info "No changes needed: $src -> $dest"
            fi
        else
            rsync_output=$(rsync -ai $rsync_delete_flag "$src" "$dest" 2>&1)
            exit_code=$?
            
            if [ $exit_code -ne 0 ]; then
                log_error "Sync failed: $src -> $dest"
                return 1
            fi
            
            if [ -n "$rsync_output" ]; then
		# Count changes by counting non-empty lines in rsync output
		change_count=$(echo "$rsync_output" | grep -v "^$" | wc -l)
		UPDATE_COUNT=$((UPDATE_COUNT + change_count))
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
        log_info "[DRY RUN] Synchronization complete"
    else
        log_info "Synchronization complete"
    fi
    
    if [ $failure_count -gt 0 ]; then
        log_warn "$success_count succeeded, $failure_count failed"
    else
        log_info "All $success_count rules processed successfully"
    fi

    # Report the total number of updates
    log_info "Total updates: $UPDATE_COUNT"
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
        -f|--force)
            FORCE=true
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

# Display final update count for any operation if changes were made
if [ "$UPDATE_COUNT" -gt 0 ] && [ "$OPERATION" != "sync" ]; then
    log_info "Total updates: $UPDATE_COUNT"
fi

exit 0

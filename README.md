# syncutil
File/Folder Synchronization Utility

- Copies files/folders from source to destination
- Only copies files that have changes
- Supports dry run, execution, and rule listing
- Offers quiet/verbose modes
- Reports when no changes are needed

## Dependencies
- rsync

## Setup
1. Save `syncutil.sh` in a directory in your PATH
2. Make it executable `chmod +x ~/bin/syncutil.sh`

## Examples
```bash
# Add sync rules
syncutil add ~/Documents/projects /mnt/backup/projects

# List all rules
syncutil list

# Dry run
syncutil -d sync

# Execution
syncutil sync

# Quite mode
syncutil -q sync

# Remove rule by list id
syncutil remove 1

```

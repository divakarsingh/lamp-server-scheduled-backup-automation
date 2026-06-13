#!/bin/bash
set -euo pipefail

BACKUP_DIR="/root/backup/webdav-backup"
USER_HOME_DIR="/home"
RCLONE_REMOTE="pcloud:backup"
MYSQL_USER="root"
MYSQL_PASS=""
ROTATE_COUNT=5
LOG_FILE="<BACKUP_DIR>/logs/webdav-backup.log"
LOG_MAX_SIZE=52428800  # 50 MB
DATE="$(date +%Y%m%d_%H%M%S)"
LOG_TAG="[webdav-backup]"

rotate_log() {
    if [[ -f "$LOG_FILE" ]]; then
        local size
        size=$(stat -c%s "$LOG_FILE" 2>/dev/null || echo 0)
        if [[ "$size" -gt "$LOG_MAX_SIZE" ]]; then
            local rotated="${LOG_FILE}.${DATE}"
            mv "$LOG_FILE" "$rotated"
            echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_TAG Log rotated to $rotated (size=${size})" >&2
        fi
    fi
}

rotate_log

exec >> "$LOG_FILE" 2>&1

log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') $LOG_TAG $*"
}

log "========================================"
log "Starting backup run"
log "DATE=$DATE"
log "BACKUP_DIR=$BACKUP_DIR"
log "RCLONE_REMOTE=$RCLONE_REMOTE"
log "ROTATE_COUNT=$ROTATE_COUNT"
log "LOG_FILE=$LOG_FILE"
log "========================================"

mkdir -p "$BACKUP_DIR"
log "Created backup directory: $BACKUP_DIR"

# Archive each user's home dir
log "Scanning user home directories in $USER_HOME_DIR"
user_count=0
mkdir -p "$BACKUP_DIR/$DATE/homes"
for homedir in "$USER_HOME_DIR"/*/; do
    username="$(basename "$homedir")"
    user_count=$((user_count + 1))
    tarfile="$BACKUP_DIR/$DATE/homes/${username}.tar.gz"
    log "Archiving home dir for user=$username -> tarfile=$tarfile"
    tar -czf "$tarfile" -C "$USER_HOME_DIR" "$username"
    log "Finished archiving user=$username"
done
log "Total users archived: $user_count"

# Dump each MySQL database
log "Fetching MySQL database list from host (user=$MYSQL_USER)"
dbs="$(mysql -u "$MYSQL_USER" ${MYSQL_PASS:+-p"$MYSQL_PASS"} -N -e 'SHOW DATABASES' | grep -Ev '^(information_schema|performance_schema|sys)$')"
db_count=0
mkdir -p "$BACKUP_DIR/$DATE/mysql"
for db in $dbs; do
    db_count=$((db_count + 1))
    dumpfile="$BACKUP_DIR/$DATE/mysql/${db}.sql.gz"
    log "Dumping database db=$db -> dumpfile=$dumpfile"
    mysqldump -u "$MYSQL_USER" ${MYSQL_PASS:+-p"$MYSQL_PASS"} --single-transaction --routines --triggers "$db" \
        | gzip > "$dumpfile"
    log "Finished dumping db=$db"
done
log "Total databases dumped: $db_count"

rotate_local() {
    local dir="$1"
    local count="$ROTATE_COUNT"
    local kept=0
    local dirs
    log "Starting local rotation for base=$dir keep=$count"
    mapfile -t dirs < <(find "$dir" -maxdepth 1 -mindepth 1 -type d -printf "%f\n" | sort -r)
    local total=${#dirs[@]}
    log "Found $total dated dirs in $dir"
    for d in "${dirs[@]}"; do
        if [[ $kept -ge $count ]]; then
            log "Purging old dated dir=$d from $dir"
            rm -rf "$dir/$d"
        else
            kept=$((kept + 1))
        fi
    done
    log "Finished local rotation for base=$dir"
}

rotate_remote() {
    local remote="$1"
    local count="$ROTATE_COUNT"
    log "Starting remote rotation for remote=$remote keep=$count"
    local dirs
    mapfile -t dirs < <(rclone lsf "$remote" -d --max-depth 1 2>/dev/null | sed 's:/$::' | sort -r)
    local kept=0
    for d in "${dirs[@]}"; do
        [[ -z "$d" ]] && continue
        if [[ $kept -ge $count ]]; then
            log "Purging old remote dir=$d"
            rclone purge "$remote/$d" || true
        else
            kept=$((kept + 1))
        fi
    done
    log "Finished remote rotation"
}

rotate_local "$BACKUP_DIR"

rotate_remote "$RCLONE_REMOTE"

log "Running rclone sync source=$BACKUP_DIR dest=$RCLONE_REMOTE"
rclone sync "$BACKUP_DIR" "$RCLONE_REMOTE"
log "Rclone sync completed"

log "========================================"
log "Backup run completed successfully"
log "========================================"

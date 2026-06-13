# LAMP Server Scheduled Backup to Any Storage (Google Drive, OneDrive, S3, Dropbox, WebDAV, pCloud, FTP, etc)

Back up **LAMP server content** — user home directories and MySQL databases — to any storage: **Google Drive, OneDrive, S3, Dropbox, WebDAV, pCloud, FTP**, or any rclone-supported backend. Fully automated cron-based rotation with zero cloud credentials in the script.

---

## Features

- Archives every user home directory under `$USER_HOME_DIR` into per-user `.tar.gz` files.
- Dumps every MySQL database (skipping system schemas) into per-database `.sql.gz` files.
- Groups each run into a **timestamped directory** (e.g., `20260613_055251/`) containing both `homes/` and `mysql/`.
- **Rotates** old runs locally and remotely, keeping only the newest `$ROTATE_COUNT` runs.
- Uploads via `rclone sync` so no cloud credentials are exposed.
- Self-contained **log rotation** — log file restarts after exceeding `$LOG_MAX_SIZE`.

---

## Prerequisites

- Linux server (Ubuntu/Debian)
- MySQL server with `mysql` and `mysqldump` client utilities
- `rclone` installed

---

## Install rclone

### Option A: Official install script (recommended)

```bash
curl https://rclone.org/install.sh | sudo bash
```

### Option B: Snap

```bash
sudo snap install rclone
```

### Option C: Download binary manually

```bash
curl -O https://downloads.rclone.org/rclone-current-linux-amd64.zip
unzip rclone-current-linux-amd64.zip
sudo cp rclone-*-linux-amd64/rclone /usr/local/bin/
```

Verify:

```bash
rclone version
```

---

## Setup with pCloud

No pre-registration is needed. Run:

```bash
rclone config
```

1. Press `n` for **new remote**.
2. Name it `pcloud` (or any name you prefer).
3. Select **pcloud** as the storage type.
4. Leave `client_id` and `client_secret` blank.
5. Say `n` to advanced config.
6. Say `y` to browser-based authentication (or `n` if headless).
7. Open the URL shown, log in to pCloud, and authorize rclone.
8. Confirm the remote is saved.

Example:

```text
n/s/q> n
name> pcloud
Storage> pcloud
client_id>
client_secret>
y/n> n
y/n> y
# Browser opens, you log in and authorize
y/e/d> y
```

Verify:

```bash
rclone lsd pcloud:
```

---

## Directory Layout

### Local backup root

```
<BACKUP_DIR>/
  20260613_055251/
    homes/
      user1.tar.gz
    mysql/
      wpdb.sql.gz
  logs/
    webdav-backup.log
    webdav-backup.log.20260613_055251
```

### Remote after sync

```
<REMOTE_PATH>/
  20260613_055251/
    homes/
      user1.tar.gz
    mysql/
      wpdb.sql.gz
  logs/
    webdav-backup.log
    webdav-backup.log.20260613_055251
```

---

## Installation

```bash
sudo cp backup.sh /usr/local/bin/backup.sh
sudo chmod +x /usr/local/bin/backup.sh
```

---

## Configuration

Edit the variables at the top of `backup.sh`.

| Variable | Default | Description |
|---|---|---|
| `BACKUP_DIR` | `/root/backup/webdav-backup` | Local backup root |
| `USER_HOME_DIR` | `/home` | Directory containing user home dirs |
| `RCLONE_REMOTE` | `pcloud:backup` | rclone remote name + path |
| `MYSQL_USER` | `root` | MySQL username |
| `MYSQL_PASS` | *(empty)* | MySQL password |
| `ROTATE_COUNT` | `5` | Number of dated runs to keep |
| `LOG_FILE` | `<BACKUP_DIR>/logs/webdav-backup.log` | Log file path |
| `LOG_MAX_SIZE` | `52428800` (50 MB) | Max log size before rotation |

> **Security:** Restrict script access so only root can read it:
> ```bash
> sudo chmod 700 /usr/local/bin/backup.sh
> ```

---

## How It Works

### 1. Create dated directory
Each run generates a timestamp like `20260613_055251`. Both home archives and database dumps are placed inside:

```
<BACKUP_DIR>/<DATE>/
  homes/
  mysql/
```

### 2. Archive home directories
For every subdirectory in `$USER_HOME_DIR`:
- Creates `<BACKUP_DIR>/<DATE>/homes/<username>.tar.gz`
- Uses `tar -czf` to compress the entire user folder

### 3. Dump MySQL databases
- Lists non-system databases via `SHOW DATABASES`
- Skips `information_schema`, `performance_schema`, `sys`
- Creates `<BACKUP_DIR>/<DATE>/mysql/<db>.sql.gz` using `mysqldump | gzip`
- Uses `--single-transaction --routines --triggers` for a consistent dump

### 4. Local rotation
Scans `$BACKUP_DIR` for dated subdirectories (sorted newest first). Keeps only `$ROTATE_COUNT` of the newest; purges older directories with `rm -rf`.

### 5. Remote rotation via rclone
Lists remote dated directories under `$RCLONE_REMOTE`, keeps newest `$ROTATE_COUNT`, and purges the rest using `rclone purge`.

### 6. Upload via rclone sync

```bash
rclone sync "$BACKUP_DIR" "$RCLONE_REMOTE"
```

This mirrors the local `$BACKUP_DIR` tree (including any rotation prunes) to the remote. Because `rclone sync` is source-of-truth, remote state exactly matches local state after each run.

---

## Setup Logging

The script redirects all stdout/stderr to `$LOG_FILE` via `exec >> "$LOG_FILE" 2>&1`.

Before each run, it checks if `$LOG_FILE` exceeds `$LOG_MAX_SIZE` and rotates it to `$LOG_FILE.<DATE>`.

No cron redirects needed.

---

## Cron Setup

Run every 3 days at 2:00 AM:

```bash
sudo crontab -e
```

Add:

```
0 2 */3 * * /usr/local/bin/backup.sh
```

Ensure `rclone` is on PATH for cron. Add to the top of the script if needed:

```bash
export PATH="/usr/local/bin:/usr/bin:/bin:$PATH"
```

---

## Using Other Cloud Providers

This script is **storage-agnostic** — it only relies on `rclone` for upload and remote rotation. Any backend supported by rclone works with minimal changes.

To switch providers, run `rclone config` for the new remote, then update `RCLONE_REMOTE` in the script. No other changes are needed.

### Popular remotes

| Provider | Remote name example | `RCLONE_REMOTE` value |
|---|---|---|
| **Google Drive** | `gdrive` | `gdrive:backups` |
| **Dropbox** | `dropbox` | `dropbox:/backups` |
| **Amazon S3** | `s3` | `s3:bucket-name/backups` |
| **OneDrive** | `onedrive` | `onedrive:backups` |
| **WebDAV** | `webdav` | `webdav:https://example.com/remote.php/webdav/backups` |
| **FTP** | `ftp` | `ftp://user:pass@host/path` |

### Provider requirements

- **Google Drive / OneDrive / Dropbox**: Run `rclone config`, select the matching storage type, and complete OAuth in your browser.
- **S3**: You'll need `access_key_id`, `secret_access_key`, `region`, and `endpoint` (if using S3-compatible storage like Wasabi or Backblaze B2).
- **WebDAV / FTP**: You'll need the URL, username, and password or token.

### Example: switching from pCloud to Google Drive

1. Configure the remote:

```bash
rclone config
# Create a new remote named "gdrive", type "drive"
```

2. Change one line in `backup.sh`:

```bash
RCLONE_REMOTE="gdrive:backups"
```

3. That's it — rotation, sync, and logging keep working identically.

---

## Verification

### Dry run locally

```bash
bash -x /usr/local/bin/backup.sh
```

### Check local output

```bash
ls -R <BACKUP_DIR>
```

### Check remote

```bash
rclone lsd <REMOTE_NAME>:<REMOTE_PATH>
rclone ls <REMOTE_NAME>:<REMOTE_PATH>/<DATE>/homes
```

### Inspect logs

```bash
tail -n 50 <BACKUP_DIR>/logs/webdav-backup.log
```

---

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| No files on remote | `rclone: command not found` in logs | Ensure rclone is installed and on PATH |
| No files on remote | rclone remote not configured | Run `rclone config` and re-authenticate |
| Log rotation not working | Log directory doesn't exist | `sudo mkdir -p <BACKUP_DIR>/logs` |
| MySQL dump fails | Wrong `MYSQL_PASS` or missing client | Verify `mysql -u root -p` works manually |
| Home archive empty | Wrong `USER_HOME_DIR` | Check `ls <USER_HOME_DIR>/` |

---

## Security Notes

- pCloud and most providers use **token-based OAuth** via `rclone config`. No plaintext password is stored in the script.
- MySQL credentials are stored as plain variables in the script. Restrict file access with `chmod 700`.
- Logs may contain directory paths and counts (no passwords leaked by default).

---

## Restore Examples

### Restore a home directory

```bash
tar -xzf <BACKUP_DIR>/<DATE>/homes/<username>.tar.gz -C <USER_HOME_DIR>/
```

### Restore a database

```bash
gunzip < <BACKUP_DIR>/<DATE>/mysql/<db>.sql.gz | mysql -u root -p <db>
```

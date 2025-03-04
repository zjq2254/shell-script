LOCAL_BACKUP_ROOT="/data/backups"       # 本地备份根目录
REMOTE_USER="root"	            	                     # 远程服务器用户名
REMOTE_HOST="192.168.239.112"          	    # 远程服务器IP或域名
REMOTE_BACKUP_DIR="/backups"          	    # 远程服务器备份目录
SOURCE_DIR=("/var/test1" "/opt/test2")      # 需要备份的目录列表
MAX_BACKUP=7                                              # 保留最近多少份备份
DATE=$(date +%Y%m%d-%H%M%S)          # 备份时间戳
LOG_FILE="/var/log/backup.log"                   # 日志文件路径
SSH_KEY="/root/.ssh/id_rsa"                          # SSH私钥路径

# --------------------- 初始化环境 ---------------------
mkdir -p "$LOCAL_BACKUP_ROOT"
echo "===== Incremental Backup started at $(date) =====" >> "$LOG_FILE"

# --------------------- 1. 本地增量备份 ---------------------
# 定义本次备份目录
CURRENT_BACKUP_DIR="$LOCAL_BACKUP_ROOT/backup-$DATE"
# 查找最近一次备份目录
LAST_BACKUP_DIR=$(ls -td "$LOCAL_BACKUP_ROOT"/backup-* 2>/dev/null | head -1)

# 使用 rsync 创建增量备份
mkdir -p "$CURRENT_BACKUP_DIR"
rsync -azvh --delete --link-dest="$LAST_BACKUP_DIR" "${SOURCE_DIR[@]}" \
  "$CURRENT_BACKUP_DIR" >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
  echo "[ERROR] Local incremental backup failed!" >> "$LOG_FILE"
  exit 1
else
  echo " Local incremental backup created: $CURRENT_BACKUP_DIR" >> "$LOG_FILE"
fi

# --------------------- 2. 同步到远程服务器 ---------------------
# 使用 rsync 同步整个备份根目录到远程（自动增量）
rsync -azvh --delete -e "ssh -i $SSH_KEY -o StrictHostKeyChecking=no" \
  "$LOCAL_BACKUP_ROOT/" \
  "$REMOTE_USER@$REMOTE_HOST:$REMOTE_BACKUP_DIR" >> "$LOG_FILE" 2>&1

if [ $? -ne 0 ]; then
  echo "[ERROR] Remote sync failed!" >> "$LOG_FILE"
  exit 1
else
  echo " Remote sync completed to $REMOTE_HOST:$REMOTE_BACKUP_DIR" >> "$LOG_FILE"
fi

# --------------------- 3. 清理旧备份 ---------------------
# 清理本地旧备份（保留最近 MAX_BACKUPS 份）
find "$LOCAL_BACKUP_ROOT" -maxdepth 1 -type d -name "backup-*" \
  | sort -r \
  | tail -n +$((MAX_BACKUP + 1)) \
  | xargs rm -rfv >> "$LOG_FILE" 2>&1

# 清理远程旧备份（通过 SSH 执行相同操作）
ssh -i "$SSH_KEY" "$REMOTE_USER@$REMOTE_HOST" \
  "find $REMOTE_BACKUP_DIR -maxdepth 1 -type d -name 'backup-*' \
  | sort -r \
  | tail -n +$((MAX_BACKUP + 1)) \
  | xargs rm -rfv" >> "$LOG_FILE" 2>&1

echo "===== Incremental Backup completed at $(date) =====" >> "$LOG_FILE"


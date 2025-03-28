#!/bin/bash

# 备份目录
BACKUP_DIR="/mnt/backup"

# 日志文件
LOG_FILE="$BACKUP_DIR/backup.log"

# 确保备份目录存在
mkdir -p "$BACKUP_DIR"

# 记录备份开始时间
echo "Backup started at $(date)" >> "$LOG_FILE"

# 定义要备份的文件和目录
declare -a BACKUP_FILES=(
    "/etc/pacman.conf"
    "/etc/mkinitcpio.conf"
    "/etc/fstab"
    "/etc/hostname"
    "/etc/hosts"
    "/etc/resolv.conf"
    "/etc/locale.conf"
    "/etc/vconsole.conf"
    "/etc/default/grub"
    "/etc/systemd/"
    "/etc/NetworkManager/"
    "/etc/netctl/"
    "/etc/X11/"
    "/etc/X11/xorg.conf.d/"
    "/etc/security/"
    "/etc/sudoers"
    "/etc/sudoers.d/"
    "/etc/ssh/"
    "/etc/ssh/sshd_config"
    "/etc/systemd/timesyncd.conf"
    "/etc/nginx/"
    "/etc/apache2/"
    "/etc/php/"
    "/etc/mysql/"
    "/etc/postgresql/"
)

# 备份文件和目录
for FILE in "${BACKUP_FILES[@]}"; do
    if [ -e "$FILE" ]; then
        # 使用 rsync 进行备份，保留权限和时间戳
        rsync -a --delete "$FILE" "$BACKUP_DIR"
        echo "Backed up $FILE" >> "$LOG_FILE"
    else
        echo "Warning: $FILE does not exist and was not backed up." >> "$LOG_FILE"
    fi
done

# 记录备份结束时间
echo "Backup completed at $(date)" >> "$LOG_FILE"
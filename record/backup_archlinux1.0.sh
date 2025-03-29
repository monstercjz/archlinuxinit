#!/bin/bash

#############################################################
# Arch Linux 自动备份脚本
# 根据 arch-back-list.md 中的建议创建
# 功能：备份系统配置、用户配置、软件包列表和系统日志
#############################################################

# 获取实际用户（处理sudo情况）
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME="/home/$SUDO_USER"
else
    REAL_USER=$(whoami)
    REAL_HOME="$HOME"
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 日期格式化
DATE_FORMAT=$(date +"%Y-%m-%d")
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# 默认配置
BACKUP_ROOT="/mnt/backup/arch-backup"
BACKUP_DIR="${BACKUP_ROOT}/${DATE_FORMAT}"
LOG_FILE="${BACKUP_ROOT}/backup_${TIMESTAMP}.log"
CONFIG_FILE="$REAL_HOME/.config/arch-backup.conf"

# 创建日志函数
log() {
    local level=$1
    local message=$2
    local color=$NC
    
    case $level in
        "INFO") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "ERROR") color=$RED ;;
        *) color=$BLUE ;;
    esac
    
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}${NC}" | tee -a "$LOG_FILE"
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1 || { log "ERROR" "命令 $1 未安装，请先安装该命令"; exit 1; }
}

# 检查必要的命令
check_dependencies() {
    log "INFO" "检查依赖..."
    check_command "rsync"
    check_command "pacman"
    check_command "journalctl"
}

# 创建备份目录
create_backup_dirs() {
    log "INFO" "创建备份目录: ${BACKUP_DIR}"
    mkdir -p "${BACKUP_DIR}/etc"
    mkdir -p "${BACKUP_DIR}/home"
    mkdir -p "${BACKUP_DIR}/packages"
    mkdir -p "${BACKUP_DIR}/logs"
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    touch "$LOG_FILE"
}

# 加载配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "INFO" "加载配置文件: $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log "WARN" "配置文件不存在，使用默认配置"
        # 创建默认配置文件
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" << EOF
# Arch Linux 备份配置文件

# 备份根目录
BACKUP_ROOT="/mnt/backup/arch-backup"

# 要排除的用户配置文件和目录（空格分隔）
EXCLUDE_USER_CONFIGS=".cache node_modules .npm .yarn .local/share/Trash"

# 要排除的系统配置目录（空格分隔）
EXCLUDE_SYSTEM_CONFIGS="/etc/pacman.d/gnupg"

# 是否备份系统配置 (true/false)
BACKUP_SYSTEM_CONFIG=true

# 是否备份用户配置 (true/false)
BACKUP_USER_CONFIG=true

# 是否备份软件包列表 (true/false)
BACKUP_PACKAGES=true

# 是否备份系统日志 (true/false)
BACKUP_LOGS=true

# 日志保留天数
LOG_RETENTION_DAYS=30

# 备份保留数量（保留最近几次备份）
BACKUP_RETENTION_COUNT=7
EOF
        log "INFO" "已创建默认配置文件: $CONFIG_FILE"
    fi
}

# 备份系统配置文件
backup_system_config() {
    if [ "$BACKUP_SYSTEM_CONFIG" != "true" ]; then
        log "INFO" "跳过系统配置备份"
        return 0
    fi
    
    log "INFO" "开始备份系统配置文件..."
    
    # 构建排除参数
    local exclude_params=""
    for item in $EXCLUDE_SYSTEM_CONFIGS; do
        exclude_params="$exclude_params --exclude=$item"
    done
    
    # 使用 rsync 备份 /etc 目录
    if sudo rsync -aAXv --delete $exclude_params /etc/ "${BACKUP_DIR}/etc/" >> "$LOG_FILE" 2>&1; then
        log "INFO" "系统配置文件备份完成"
    else
        log "ERROR" "系统配置文件备份失败"
        return 1
    fi
    
    return 0
}

# 备份用户配置文件
backup_user_config() {
    if [ "$BACKUP_USER_CONFIG" != "true" ]; then
        log "INFO" "跳过用户配置备份"
        return 0
    fi
    
    log "INFO" "开始备份用户配置文件..."
    log "INFO" "备份用户: $REAL_USER 的配置文件"
    
    # 构建排除参数
    local exclude_params=""
    for item in $EXCLUDE_USER_CONFIGS; do
        exclude_params="$exclude_params --exclude=$item"
    done
    
    # 备份重要的用户配置文件和目录
    local user_dirs=(
        ".bashrc" ".zshrc" ".config/fish/config.fish"
        ".profile" ".bash_profile" ".zprofile"
        ".config" ".local/share"
        ".themes" ".icons" ".fonts"
        ".ssh" ".gnupg"
        ".mozilla" ".config/chromium"
        ".vimrc" ".config/nvim"
        ".tmux.conf" ".gitconfig"
        ".xinitrc" ".xprofile"
    )
    
    for dir in "${user_dirs[@]}"; do
        local src_path="$REAL_HOME/$dir"
        local dest_path="${BACKUP_DIR}/home/$dir"
        
        if [ -e "$src_path" ]; then
            # 创建目标目录
            mkdir -p "$(dirname "$dest_path")"
            
            # 使用 rsync 备份
            if rsync -aAXv --delete $exclude_params "$src_path" "$dest_path" >> "$LOG_FILE" 2>&1; then
                log "INFO" "已备份: $dir"
            else
                log "WARN" "备份失败: $dir"
            fi
        fi
    done
    
    log "INFO" "用户配置文件备份完成"
    return 0
}

# 备份软件包列表
backup_packages() {
    if [ "$BACKUP_PACKAGES" != "true" ]; then
        log "INFO" "跳过软件包列表备份"
        return 0
    fi
    
    log "INFO" "开始备份软件包列表..."
    
    # 备份手动安装的软件包列表
    if pacman -Qe > "${BACKUP_DIR}/packages/manually-installed.txt" 2>> "$LOG_FILE"; then
        log "INFO" "手动安装的软件包列表备份完成"
    else
        log "ERROR" "手动安装的软件包列表备份失败"
    fi
    
    # 备份所有安装的软件包列表
    if pacman -Q > "${BACKUP_DIR}/packages/all-packages.txt" 2>> "$LOG_FILE"; then
        log "INFO" "所有软件包列表备份完成"
    else
        log "ERROR" "所有软件包列表备份失败"
    fi
    
    # 备份外部软件包列表（非官方仓库）
    if pacman -Qm > "${BACKUP_DIR}/packages/foreign-packages.txt" 2>> "$LOG_FILE"; then
        log "INFO" "外部软件包列表备份完成"
    else
        log "ERROR" "外部软件包列表备份失败"
    fi
    
    # 备份 pacman 日志
    if [ -f "/var/log/pacman.log" ]; then
        if sudo cp /var/log/pacman.log "${BACKUP_DIR}/packages/pacman.log" 2>> "$LOG_FILE"; then
            log "INFO" "Pacman 日志备份完成"
        else
            log "ERROR" "Pacman 日志备份失败"
        fi
    else
        log "WARN" "Pacman 日志文件不存在"
    fi
    
    return 0
}

# 备份系统日志
backup_logs() {
    if [ "$BACKUP_LOGS" != "true" ]; then
        log "INFO" "跳过系统日志备份"
        return 0
    fi
    
    log "INFO" "开始备份系统日志..."
    
    # 获取当前年份
    local current_year=$(date +"%Y")
    
    # 备份当年的系统日志
    if journalctl --since "${current_year}-01-01" --until "${current_year}-12-31" > "${BACKUP_DIR}/logs/system-log-${current_year}.txt" 2>> "$LOG_FILE"; then
        log "INFO" "系统日志备份完成"
    else
        log "ERROR" "系统日志备份失败"
    fi
    
    return 0
}

# 清理旧备份
cleanup_old_backups() {
    log "INFO" "清理旧备份..."
    
    # 获取所有备份目录并按日期排序
    local all_backups=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" | sort))
    local backup_count=${#all_backups[@]}
    
    # 如果备份数量超过保留数量，则删除最旧的备份
    if [ $backup_count -gt $BACKUP_RETENTION_COUNT ]; then
        local to_delete=$((backup_count - BACKUP_RETENTION_COUNT))
        log "INFO" "发现 $backup_count 个备份，保留 $BACKUP_RETENTION_COUNT 个，将删除 $to_delete 个最旧的备份"
        
        for ((i=0; i<$to_delete; i++)); do
            log "INFO" "删除旧备份: ${all_backups[$i]}"
            rm -rf "${all_backups[$i]}"
        done
    else
        log "INFO" "备份数量 ($backup_count) 未超过保留限制 ($BACKUP_RETENTION_COUNT)，无需清理"
    fi
    
    # 清理旧日志文件
    find "$BACKUP_ROOT" -name "backup_*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete
    log "INFO" "已清理超过 $LOG_RETENTION_DAYS 天的日志文件"
}

# 创建备份摘要
create_backup_summary() {
    log "INFO" "创建备份摘要..."
    
    local summary_file="${BACKUP_DIR}/backup-summary.txt"
    
    cat > "$summary_file" << EOF
# Arch Linux 备份摘要

备份时间: $(date '+%Y-%m-%d %H:%M:%S')
主机名: $(hostname)
用户: $REAL_USER

## 备份内容

$([ "$BACKUP_SYSTEM_CONFIG" == "true" ] && echo "- 系统配置文件 (/etc)" || echo "- 系统配置文件 (已跳过)")
$([ "$BACKUP_USER_CONFIG" == "true" ] && echo "- 用户配置文件 (~/.*)" || echo "- 用户配置文件 (已跳过)")
$([ "$BACKUP_PACKAGES" == "true" ] && echo "- 软件包列表" || echo "- 软件包列表 (已跳过)")
$([ "$BACKUP_LOGS" == "true" ] && echo "- 系统日志" || echo "- 系统日志 (已跳过)")

## 系统信息

- 内核版本: $(uname -r)
- Arch 版本: $(pacman -Q core/filesystem | cut -d' ' -f2)
- 已安装软件包数量: $(pacman -Q | wc -l)
- 手动安装软件包数量: $(pacman -Qe | wc -l)
- 外部软件包数量: $(pacman -Qm | wc -l)

## 备份配置

- 备份根目录: $BACKUP_ROOT
- 备份保留数量: $BACKUP_RETENTION_COUNT
- 日志保留天数: $LOG_RETENTION_DAYS
EOF
    
    log "INFO" "备份摘要已创建: $summary_file"
}

# 主函数
main() {
    log "INFO" "开始 Arch Linux 备份 (${TIMESTAMP})"
    
    # 检查是否为 root 用户
    if [ "$(id -u)" -ne 0 ]; then
        log "WARN" "脚本未以 root 用户运行，某些系统文件可能无法备份"
    fi
    
    # 检查依赖
    check_dependencies
    
    # 加载配置
    load_config
    
    # 创建备份目录
    create_backup_dirs
    
    # 执行备份
    backup_system_config
    backup_user_config
    backup_packages
    backup_logs
    
    # 创建备份摘要
    create_backup_summary
    
    # 清理旧备份
    cleanup_old_backups
    
    log "INFO" "备份完成！备份目录: ${BACKUP_DIR}"
    log "INFO" "日志文件: ${LOG_FILE}"
}

# 执行主函数
main
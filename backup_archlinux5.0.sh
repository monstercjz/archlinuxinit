#!/bin/bash

#############################################################
# Arch Linux 自动备份脚本
# 根据 arch-back-list.md 中的建议创建
# 功能：备份系统配置、用户配置、自定义路径、软件包列表和系统日志
# 支持压缩备份、差异备份和备份验证
# 可配置的备份目录结构
# 可自定义的用户配置文件列表
# 可自定义的备份路径
# 灵活的备份选项
# 日志优化显示排除项
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
COMPRESS_BACKUP=false
COMPRESS_METHOD="gzip" # 可选: gzip, bzip2, xz
DIFF_BACKUP=false
VERIFY_BACKUP=false
LAST_BACKUP_DIR=""

# 默认备份目录结构
BACKUP_DIRS="etc home custom packages logs"

# 默认用户配置文件列表
USER_CONFIG_FILES=".bashrc .zshrc .config/fish/config.fish .profile .bash_profile .zprofile .config .local/share .themes .icons .fonts .ssh .gnupg .mozilla .config/chromium .vimrc .config/nvim .tmux.conf .gitconfig .xinitrc .xprofile"

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
    
    # 如果启用了压缩，检查相应的压缩命令
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        case "$COMPRESS_METHOD" in
            "gzip")
                check_command "gzip"
                ;;
            "bzip2")
                check_command "bzip2"
                ;;
            "xz")
                check_command "xz"
                ;;
            *)
                log "WARN" "未知的压缩方法: $COMPRESS_METHOD，将使用 gzip"
                COMPRESS_METHOD="gzip"
                check_command "gzip"
                ;;
        esac
    fi
}

# 创建备份目录
create_backup_dirs() {
    log "INFO" "创建备份目录: ${BACKUP_DIR}"
    
    # 使用配置文件中定义的备份目录结构
    for dir in ${BACKUP_DIRS}; do
        mkdir -p "${BACKUP_DIR}/${dir}"
        log "INFO" "创建目录: ${BACKUP_DIR}/${dir}"
    done
    
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

# 备份目录结构（空格分隔）
BACKUP_DIRS="etc home packages logs"

# 要备份的用户配置文件和目录（空格分隔）
USER_CONFIG_FILES=".bashrc .zshrc .config/fish/config.fish .profile .bash_profile .zprofile .config .local/share .themes .icons .fonts .ssh .gnupg .mozilla .config/chromium .vimrc .config/nvim .tmux.conf .gitconfig .xinitrc .xprofile"

# 要排除的用户配置文件和目录（空格分隔）
EXCLUDE_USER_CONFIGS=".cache node_modules .npm .yarn .local/share/Trash"

# 要排除的系统配置目录（空格分隔）
EXCLUDE_SYSTEM_CONFIGS="/etc/pacman.d/gnupg"

# 自定义备份路径（空格分隔）
CUSTOM_PATHS="/opt/myapp /var/www /srv/data"

# 要排除的自定义路径（空格分隔）
EXCLUDE_CUSTOM_PATHS="*/temp */cache */logs"

# 是否备份系统配置 (true/false)
BACKUP_SYSTEM_CONFIG=true

# 是否备份用户配置 (true/false)
BACKUP_USER_CONFIG=true

# 是否备份自定义路径 (true/false)
BACKUP_CUSTOM_PATHS=true

# 是否备份软件包列表 (true/false)
BACKUP_PACKAGES=true

# 是否备份系统日志 (true/false)
BACKUP_LOGS=true

# 是否压缩备份 (true/false)
COMPRESS_BACKUP=false

# 压缩方法 (gzip, bzip2, xz)
COMPRESS_METHOD="gzip"

# 是否进行差异备份 (true/false)
# 差异备份只备份自上次备份以来变化的文件
DIFF_BACKUP=false

# 是否验证备份 (true/false)
# 验证备份会检查备份文件的完整性
VERIFY_BACKUP=false

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
        log "INFO" "跳过系统配置排除项: $item"
    done
    
    # 差异备份参数
    local diff_params=""
    if [ "$DIFF_BACKUP" = "true" ] && [ -n "$LAST_BACKUP_DIR" ] && [ -d "$LAST_BACKUP_DIR/etc" ]; then
        log "INFO" "使用差异备份模式，参考上次备份: $LAST_BACKUP_DIR"
        diff_params="--link-dest=$LAST_BACKUP_DIR/etc"
    fi
    
    # 使用 rsync 备份 /etc 目录
    if sudo rsync -aAXv --delete $exclude_params $diff_params /etc/ "${BACKUP_DIR}/etc/" >> "$LOG_FILE" 2>&1; then
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
    
    # 差异备份参数
    local diff_params=""
    if [ "$DIFF_BACKUP" = "true" ] && [ -n "$LAST_BACKUP_DIR" ] && [ -d "$LAST_BACKUP_DIR/home" ]; then
        log "INFO" "使用差异备份模式，参考上次备份: $LAST_BACKUP_DIR"
        diff_params="--link-dest=$LAST_BACKUP_DIR/home"
    fi
    
    # 备份重要的用户配置文件和目录
    # 从配置文件中读取用户配置文件列表
    IFS=' ' read -r -a user_dirs <<< "$USER_CONFIG_FILES"
    
    for dir in "${user_dirs[@]}"; do
        local src_path="$REAL_HOME/$dir"
        local dest_path="${BACKUP_DIR}/home/$dir"
        
        if [ -e "$src_path" ]; then
            # 检查是否在排除列表中
            local is_excluded=false
            for exclude_item in $EXCLUDE_USER_CONFIGS; do
                if [[ "$dir" == "$exclude_item"* ]]; then
                    is_excluded=true
                    log "INFO" "跳过排除项: $dir"
                    break
                fi
            done
            
            # 如果不在排除列表中，则进行备份
            if [ "$is_excluded" = false ]; then
                # 创建目标目录
                mkdir -p "$(dirname "$dest_path")"
                
                # 使用 rsync 备份
                if rsync -aAXv --delete $exclude_params $diff_params "$src_path" "$dest_path" >> "$LOG_FILE" 2>&1; then
                    log "INFO" "已备份: $dir"
                else
                    log "WARN" "备份失败: $dir"
                fi
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

# 备份自定义路径
backup_custom_paths() {
    if [ "$BACKUP_CUSTOM_PATHS" != "true" ]; then
        log "INFO" "跳过自定义路径备份"
        return 0
    fi
    
    log "INFO" "开始备份自定义路径..."
    
    # 创建自定义路径备份目录
    mkdir -p "${BACKUP_DIR}/custom"
    
    # 构建排除参数
    local exclude_params=""
    for item in $EXCLUDE_CUSTOM_PATHS; do
        exclude_params="$exclude_params --exclude=$item"
        log "INFO" "跳过自定义路径排除项: $item"
    done
    
    # 差异备份参数
    local diff_params=""
    if [ "$DIFF_BACKUP" = "true" ] && [ -n "$LAST_BACKUP_DIR" ] && [ -d "$LAST_BACKUP_DIR/custom" ]; then
        log "INFO" "使用差异备份模式，参考上次备份: $LAST_BACKUP_DIR"
        diff_params="--link-dest=$LAST_BACKUP_DIR/custom"
    fi
    
    # 从配置文件中读取自定义路径列表
    IFS=' ' read -r -a custom_paths <<< "$CUSTOM_PATHS"
    
    for path in "${custom_paths[@]}"; do
        if [ -e "$path" ]; then
            # 获取路径的基本名称（去除前导斜杠）
            local base_name=$(basename "$path")
            local dest_path="${BACKUP_DIR}/custom/$base_name"
            
            log "INFO" "备份自定义路径: $path"
            
            # 使用 rsync 备份自定义路径
            if sudo rsync -aAXv --delete $exclude_params $diff_params "$path" "$dest_path" >> "$LOG_FILE" 2>&1; then
                log "INFO" "自定义路径备份完成: $path"
            else
                log "ERROR" "自定义路径备份失败: $path"
            fi
        else
            log "WARN" "自定义路径不存在，跳过: $path"
        fi
    done
    
    log "INFO" "自定义路径备份完成"
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
$([ "$BACKUP_CUSTOM_PATHS" == "true" ] && echo "- 自定义路径备份" || echo "- 自定义路径备份 (已跳过)")
$([ "$BACKUP_PACKAGES" == "true" ] && echo "- 软件包列表" || echo "- 软件包列表 (已跳过)")
$([ "$BACKUP_LOGS" == "true" ] && echo "- 系统日志" || echo "- 系统日志 (已跳过)")
$([ "$COMPRESS_BACKUP" == "true" ] && echo "- 备份已压缩 (使用 $COMPRESS_METHOD)" || echo "- 备份未压缩")
$([ "$DIFF_BACKUP" == "true" ] && echo "- 差异备份模式" || echo "- 完整备份模式")
$([ "$VERIFY_BACKUP" == "true" ] && echo "- 备份已验证" || echo "- 备份未验证")

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
    
    # 添加自定义路径备份信息
    if [ "$BACKUP_CUSTOM_PATHS" == "true" ] && [ -n "$CUSTOM_PATHS" ]; then
        echo -e "\n## 已备份的自定义路径\n" >> "$summary_file"
        
        IFS=' ' read -r -a custom_paths <<< "$CUSTOM_PATHS"
        for path in "${custom_paths[@]}"; do
            if [ -e "$path" ]; then
                local base_name=$(basename "$path")
                local dest_path="${BACKUP_DIR}/custom/$base_name"
                
                if [ -e "$dest_path" ]; then
                    echo "- $path (成功)" >> "$summary_file"
                else
                    echo "- $path (失败)" >> "$summary_file"
                fi
            else
                echo "- $path (路径不存在)" >> "$summary_file"
            fi
        done
    fi
}

# 查找最近的备份目录
find_last_backup() {
    if [ "$DIFF_BACKUP" != "true" ]; then
        return 0
    fi
    
    log "INFO" "查找最近的备份目录..."
    
    # 获取所有备份目录并按日期排序（最新的在最后）
    local all_backups=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" | sort))
    local backup_count=${#all_backups[@]}
    
    if [ $backup_count -gt 0 ]; then
        # 获取最新的备份目录
        LAST_BACKUP_DIR="${all_backups[$((backup_count-1))]}"
        log "INFO" "找到最近的备份目录: $LAST_BACKUP_DIR"
    else
        log "INFO" "没有找到以前的备份，将进行完整备份"
    fi
}

# 压缩备份
compress_backup() {
    if [ "$COMPRESS_BACKUP" != "true" ]; then
        log "INFO" "跳过备份压缩"
        return 0
    fi
    
    log "INFO" "开始压缩备份 (使用 $COMPRESS_METHOD)..."
    
    local compress_cmd=""
    local ext=""
    
    case "$COMPRESS_METHOD" in
        "gzip")
            compress_cmd="gzip"
            ext=".gz"
            ;;
        "bzip2")
            compress_cmd="bzip2"
            ext=".bz2"
            ;;
        "xz")
            compress_cmd="xz"
            ext=".xz"
            ;;
        *)
            log "ERROR" "未知的压缩方法: $COMPRESS_METHOD，跳过压缩"
            return 1
            ;;
    esac
    
    # 检查压缩命令是否存在
    if ! command -v "$compress_cmd" >/dev/null 2>&1; then
        log "ERROR" "压缩命令 $compress_cmd 未安装，跳过压缩"
        return 1
    fi
    
    # 创建压缩文件
    log "INFO" "创建备份压缩文件..."
    
    # 创建压缩文件名
    local archive_file="${BACKUP_ROOT}/${DATE_FORMAT}_backup.tar"
    
    # 创建 tar 归档
    if tar -cf "$archive_file" -C "$BACKUP_ROOT" "${DATE_FORMAT}" >> "$LOG_FILE" 2>&1; then
        log "INFO" "备份归档创建成功: $archive_file"
        
        # 压缩归档
        if "$compress_cmd" "$archive_file" >> "$LOG_FILE" 2>&1; then
            log "INFO" "备份压缩成功: ${archive_file}${ext}"
            
            # 如果压缩成功，删除原始备份目录
            rm -rf "$BACKUP_DIR"
            log "INFO" "已删除原始备份目录: $BACKUP_DIR"
        else
            log "ERROR" "备份压缩失败"
            return 1
        fi
    else
        log "ERROR" "创建备份归档失败"
        return 1
    fi
    
    return 0
}

# 验证备份
verify_backup() {
    if [ "$VERIFY_BACKUP" != "true" ]; then
        log "INFO" "跳过备份验证"
        return 0
    fi
    
    log "INFO" "开始验证备份..."
    
    local verify_status=0
    
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        # 验证压缩文件
        local archive_file="${BACKUP_ROOT}/${DATE_FORMAT}_backup.tar"
        local ext=""
        
        case "$COMPRESS_METHOD" in
            "gzip") ext=".gz" ;;
            "bzip2") ext=".bz2" ;;
            "xz") ext=".xz" ;;
        esac
        
        log "INFO" "验证压缩文件: ${archive_file}${ext}"
        
        case "$COMPRESS_METHOD" in
            "gzip")
                gzip -t "${archive_file}${ext}" >> "$LOG_FILE" 2>&1 || verify_status=1
                ;;
            "bzip2")
                bzip2 -t "${archive_file}${ext}" >> "$LOG_FILE" 2>&1 || verify_status=1
                ;;
            "xz")
                xz -t "${archive_file}${ext}" >> "$LOG_FILE" 2>&1 || verify_status=1
                ;;
        esac
        
        if [ $verify_status -eq 0 ]; then
            log "INFO" "压缩文件验证成功"
        else
            log "ERROR" "压缩文件验证失败"
            return 1
        fi
    else
        # 验证未压缩的备份
        log "INFO" "验证备份目录: $BACKUP_DIR"
        
        # 检查关键目录是否存在
        for dir in ${BACKUP_DIRS}; do
            if [ ! -d "${BACKUP_DIR}/${dir}" ]; then
                log "ERROR" "验证失败: ${dir}目录不存在"
                verify_status=1
            fi
        done
        
        # 检查备份摘要文件
        if [ ! -f "${BACKUP_DIR}/backup-summary.txt" ]; then
            log "ERROR" "验证失败: 备份摘要文件不存在"
            verify_status=1
        fi
        
        if [ $verify_status -eq 0 ]; then
            log "INFO" "备份目录验证成功"
        else
            log "ERROR" "备份目录验证失败"
            return 1
        fi
    fi
    
    return $verify_status
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
    
    # 查找最近的备份目录（用于差异备份）
    find_last_backup
    
    # 创建备份目录
    create_backup_dirs
    
    # 执行备份
    backup_system_config
    backup_user_config
    backup_custom_paths
    backup_packages
    backup_logs
    
    # 创建备份摘要
    create_backup_summary
    
    # 压缩备份
    compress_backup
    
    # 验证备份
    verify_backup
    
    # 清理旧备份
    cleanup_old_backups
    
    log "INFO" "备份完成！备份目录: ${BACKUP_DIR}"
    log "INFO" "日志文件: ${LOG_FILE}"
}

# 执行主函数
main
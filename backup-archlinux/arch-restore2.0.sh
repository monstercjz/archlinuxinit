#!/bin/bash

#############################################################
# Arch Linux 自动恢复脚本
# 配套 arch-backup.sh 使用
# 功能：从备份中恢复系统配置、用户配置、自定义路径、软件包列表
# 支持选择性恢复、交互式恢复界面、完整性验证和冲突处理
# 1.0 版本：基础恢复功能
#   - 选择性恢复（允许用户选择恢复特定内容）
#   - 交互式恢复界面
#   - 完整性验证
#   - 冲突处理机制
# 2.0 版本：添加注释
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
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# 默认配置
BACKUP_ROOT="/mnt/backup/arch-backup"
LOG_FILE="${BACKUP_ROOT}/restore_${TIMESTAMP}.log"
CONFIG_FILE="$REAL_HOME/.config/arch-backup.conf"
TEST_MODE=false
FORCE_RESTORE=false
INTERACTIVE=true
DRY_RUN=false

# 创建日志函数
# 功能：记录不同级别的日志信息到日志文件并显示在终端上
# 参数：
#   $1 - 日志级别（INFO, WARN, ERROR, FATAL, DEBUG）
#   $2 - 日志消息内容
# 返回值：
#   无返回值，但如果日志级别为FATAL，则会终止脚本执行
# 错误处理：
#   FATAL级别的日志会导致脚本立即退出（exit 1）
#   其他级别的日志不会中断脚本执行
# 颜色编码：
#   INFO - 绿色
#   WARN - 黄色
#   ERROR - 红色
#   FATAL - 红色
#   DEBUG - 蓝色
# 使用示例：
#   log "INFO" "开始恢复操作"
#   log "ERROR" "文件不存在"
#   log "FATAL" "无法访问备份目录"
log() {
    local level=$1
    local message=$2
    local color=$NC
    
    case $level in
        "INFO") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "FATAL") color=$RED ;;
        "DEBUG") color=$BLUE ;;
        *) color=$BLUE ;;
    esac
    
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}${NC}" | tee -a "$LOG_FILE"
    
    # 如果是致命错误，退出脚本
    if [ "$level" == "FATAL" ]; then
        echo -e "${RED}恢复过程中遇到致命错误，退出脚本${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# 检查命令是否存在
# 功能：检查指定的命令是否存在于系统中
# 参数：
#   $1 - 要检查的命令名称
# 返回值：
#   0 - 命令存在
#   非0 - 命令不存在（同时会记录错误并退出脚本）
# 错误处理：
#   如果命令不存在，会记录错误并立即退出脚本
# 使用示例：
#   check_command "rsync"
#   check_command "tar"
check_command() {
    command -v "$1" >/dev/null 2>&1 || { log "ERROR" "命令 $1 未安装，请先安装该命令"; exit 1; }
}

# 检查必要的命令
# 功能：检查脚本运行所需的所有依赖工具是否已安装
# 参数：无
# 返回值：
#   0 - 所有必要依赖都已安装
#   1 - 有必要依赖缺失
# 错误处理：
#   记录缺失的依赖并提供安装建议
#   对于非核心依赖，仅发出警告
# 使用示例：
#   if ! check_dependencies; then
#       log "FATAL" "缺少必要依赖，无法继续执行"
#   fi
check_dependencies() {
    log "INFO" "检查依赖..."
    local missing_deps=0
    
    # 核心依赖检查 - 这些是必须的
    log "INFO" "检查核心依赖..."
    local core_deps=("rsync" "tar" "find" "grep" "awk" "sed" "diff" "cmp")
    local core_desc=("远程同步工具" "归档工具" "文件查找工具" "文本搜索工具" "文本处理工具" "流编辑器" "文件比较工具" "字节比较工具")
    
    for i in "${!core_deps[@]}"; do
        if ! command -v "${core_deps[$i]}" >/dev/null 2>&1; then
            log "ERROR" "核心依赖 ${core_deps[$i]} (${core_desc[$i]}) 未安装"
            log "INFO" "请使用以下命令安装: sudo pacman -S ${core_deps[$i]}"
            missing_deps=$((missing_deps + 1))
        else
            log "INFO" "核心依赖 ${core_deps[$i]} 已安装"
        fi
    done
    
    # 压缩工具依赖检查
    log "INFO" "检查压缩工具依赖..."
    local compression_tools=("gzip" "bzip2" "xz")
    local compression_desc=("gzip压缩工具" "bzip2压缩工具" "xz压缩工具")
    
    for i in "${!compression_tools[@]}"; do
        if ! command -v "${compression_tools[$i]}" >/dev/null 2>&1; then
            log "WARN" "压缩工具 ${compression_tools[$i]} 未安装，如需恢复该格式的备份请先安装"
        else
            log "DEBUG" "压缩工具 ${compression_tools[$i]} 已安装"
        fi
    done
    
    # 依赖检查结果汇总
    if [ $missing_deps -gt 0 ]; then
        log "ERROR" "检测到 $missing_deps 个必要依赖缺失，请安装后再运行脚本"
        return 1
    else
        log "INFO" "所有必要依赖检查通过"
        return 0
    fi
}

# 加载配置文件
# 功能：加载配置文件，如果不存在则创建默认配置文件
# 参数：无，但使用全局变量 CONFIG_FILE
# 返回值：无
# 注意事项：
#   - 如果配置文件不存在，会创建包含默认配置的文件
#   - 配置文件中的变量会覆盖脚本中的默认值
# 使用示例：
#   load_config
#   log "INFO" "配置加载完成"
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
EOF
        log "INFO" "已创建默认配置文件: $CONFIG_FILE"
    fi
}

# 列出可用的备份
# 功能：查找并列出备份根目录中的所有可用备份
# 参数：无，但使用全局变量 BACKUP_ROOT
# 返回值：
#   0 - 成功找到并列出备份
#   1 - 未找到可用备份或备份根目录不存在
# 使用示例：
#   if ! list_available_backups; then
#       log "ERROR" "未找到可用的备份"
#       exit 1
#   fi
list_available_backups() {
    log "INFO" "列出可用的备份..."
    
    # 检查备份根目录是否存在
    if [ ! -d "$BACKUP_ROOT" ]; then
        log "ERROR" "备份根目录不存在: $BACKUP_ROOT"
        return 1
    fi
    
    # 查找备份目录
    local backup_dirs=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" | sort -r))
    local compressed_backups=($(find "$BACKUP_ROOT" -maxdepth 1 -type f -name "????-??-??_backup.tar*" | sort -r))
    
    if [ ${#backup_dirs[@]} -eq 0 ] && [ ${#compressed_backups[@]} -eq 0 ]; then
        log "ERROR" "未找到可用的备份"
        return 1
    fi
    
    echo -e "\n可用的备份:"
    
    # 列出未压缩的备份
    if [ ${#backup_dirs[@]} -gt 0 ]; then
        echo -e "\n未压缩备份:"
        for i in "${!backup_dirs[@]}"; do
            local dir="${backup_dirs[$i]}"
            local date=$(basename "$dir")
            local size=$(du -sh "$dir" 2>/dev/null | cut -f1)
            echo "$((i+1)). $date (大小: $size)"
        done
    fi
    
    # 列出压缩的备份
    if [ ${#compressed_backups[@]} -gt 0 ]; then
        echo -e "\n压缩备份:"
        local offset=${#backup_dirs[@]}
        for i in "${!compressed_backups[@]}"; do
            local file="${compressed_backups[$i]}"
            local name=$(basename "$file")
            local size=$(du -h "$file" 2>/dev/null | cut -f1)
            echo "$((i+offset+1)). $name (大小: $size)"
        done
    fi
    
    echo ""
    return 0
}

# 选择备份
# 功能：列出可用的备份并让用户选择要恢复的备份
# 参数：无
# 返回值：
#   0 - 成功选择备份
#   1 - 选择失败或用户取消
# 使用示例：
#   if ! select_backup; then
#       log "FATAL" "无法选择备份，退出脚本"
#   fi
select_backup() {
    # 列出可用的备份
    if ! list_available_backups; then
        return 1
    fi
    
    # 查找备份目录和压缩备份
    local backup_dirs=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" | sort -r))
    local compressed_backups=($(find "$BACKUP_ROOT" -maxdepth 1 -type f -name "????-??-??_backup.tar*" | sort -r))
    local total_backups=$((${#backup_dirs[@]} + ${#compressed_backups[@]}))
    
    # 选择备份
    local choice
    read -p "选择要恢复的备份 (1-$total_backups): " choice
    
    if [[ ! $choice =~ ^[0-9]+$ ]] || [ $choice -lt 1 ] || [ $choice -gt $total_backups ]; then
        log "ERROR" "无效的选择"
        return 1
    fi
    
    # 确定选择的是未压缩备份还是压缩备份
    if [ $choice -le ${#backup_dirs[@]} ]; then
        # 选择的是未压缩备份
        SELECTED_BACKUP="${backup_dirs[$((choice-1))]}"
        BACKUP_TYPE="directory"
        log "INFO" "已选择未压缩备份: $(basename "$SELECTED_BACKUP")"
    else
        # 选择的是压缩备份
        local compressed_index=$((choice - ${#backup_dirs[@]} - 1))
        SELECTED_BACKUP="${compressed_backups[$compressed_index]}"
        BACKUP_TYPE="compressed"
        log "INFO" "已选择压缩备份: $(basename "$SELECTED_BACKUP")"
    fi
    
    return 0
}

# 解压备份
# 功能：如果选择的备份是压缩文件，则解压到临时目录
# 参数：无，但使用全局变量 SELECTED_BACKUP 和 BACKUP_TYPE
# 返回值：
#   0 - 解压成功或不需要解压
#   1 - 解压失败
# 使用示例：
#   if ! extract_backup; then
#       log "ERROR" "备份解压失败"
#       cleanup
#       exit 1
#   fi
extract_backup() {
    if [ "$BACKUP_TYPE" != "compressed" ]; then
        # 不需要解压
        return 0
    fi
    
    log "INFO" "解压备份文件: $(basename "$SELECTED_BACKUP")"
    
    # 创建临时解压目录
    local temp_extract_dir="${BACKUP_ROOT}/temp_extract_${TIMESTAMP}"
    mkdir -p "$temp_extract_dir"
    
    # 确定压缩格式
    local decompress_cmd=""
    if [[ "$SELECTED_BACKUP" == *.tar.gz ]]; then
        decompress_cmd="tar -xzf"
    elif [[ "$SELECTED_BACKUP" == *.tar.bz2 ]]; then
        decompress_cmd="tar -xjf"
    elif [[ "$SELECTED_BACKUP" == *.tar.xz ]]; then
        decompress_cmd="tar -xJf"
    else
        log "ERROR" "未知的压缩格式: $(basename "$SELECTED_BACKUP")"
        rm -rf "$temp_extract_dir"
        return 1
    fi
    
    # 解压备份文件
    log "INFO" "解压备份文件到临时目录: $temp_extract_dir"
    if $decompress_cmd "$SELECTED_BACKUP" -C "$temp_extract_dir" > /dev/null 2>&1; then
        log "INFO" "备份文件解压成功"
        
        # 查找解压后的备份目录
        local extracted_dir=$(find "$temp_extract_dir" -maxdepth 1 -type d -name "????-??-??" | head -1)
        
        if [ -z "$extracted_dir" ]; then
            log "ERROR" "解压后未找到有效的备份目录"
            rm -rf "$temp_extract_dir"
            return 1
        fi
        
        # 更新选择的备份目录
        SELECTED_BACKUP="$extracted_dir"
        BACKUP_TYPE="directory"
        TEMP_EXTRACT_DIR="$temp_extract_dir"
        
        log "INFO" "已设置解压后的备份目录: $(basename "$SELECTED_BACKUP")"
        return 0
    else
        log "ERROR" "备份文件解压失败"
        rm -rf "$temp_extract_dir"
        return 1
    fi
}

# 检查备份完整性
# 功能：检查选定备份的完整性，确保关键目录存在
# 参数：无，但使用全局变量 SELECTED_BACKUP 和 BACKUP_TYPE
# 返回值：
#   0 - 备份完整或用户确认继续
#   1 - 备份不完整且用户取消恢复
# 使用示例：
#   if ! check_backup_integrity; then
#       log "ERROR" "备份完整性检查失败"
#       cleanup
#       exit 1
#   fi
check_backup_integrity() {
    log "INFO" "检查备份完整性..."
    
    if [ "$BACKUP_TYPE" != "directory" ]; then
        log "ERROR" "无法检查完整性: 备份类型不是目录"
        return 1
    fi
    
    # 检查关键目录是否存在
    local required_dirs=("etc" "home" "packages")
    local missing_dirs=0
    
    for dir in "${required_dirs[@]}"; do
        if [ ! -d "${SELECTED_BACKUP}/${dir}" ]; then
            log "WARN" "备份中缺少关键目录: ${dir}"
            missing_dirs=$((missing_dirs + 1))
        fi
    done
    
    if [ $missing_dirs -eq ${#required_dirs[@]} ]; then
        log "ERROR" "备份不完整: 所有关键目录都缺失"
        return 1
    elif [ $missing_dirs -gt 0 ]; then
        log "WARN" "备份部分不完整: 有 $missing_dirs 个关键目录缺失"
        if [ "$FORCE_RESTORE" != "true" ]; then
            read -p "备份不完整，是否继续恢复? (y/n): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                log "INFO" "用户取消了恢复操作"
                return 1
            fi
        fi
    else
        log "INFO" "备份完整性检查通过"
    fi
    
    return 0
}

# 选择要恢复的内容
# 功能：让用户选择要恢复的内容（系统配置、用户配置、自定义路径、软件包列表）
# 参数：无，但会设置全局变量 RESTORE_SYSTEM_CONFIG, RESTORE_USER_CONFIG, RESTORE_CUSTOM_PATHS, RESTORE_PACKAGES
# 返回值：
#   0 - 成功选择恢复内容
#   1 - 选择失败或用户取消
# 使用示例：
#   if ! select_restore_content; then
#       log "INFO" "用户取消了恢复操作"
#       cleanup
#       exit 0
#   fi
select_restore_content() {
    if [ "$INTERACTIVE" != "true" ]; then
        # 非交互模式，恢复所有内容
        RESTORE_SYSTEM_CONFIG=true
        RESTORE_USER_CONFIG=true
        RESTORE_CUSTOM_PATHS=true
        RESTORE_PACKAGES=true
        log "INFO" "非交互模式: 将恢复所有内容"
        return 0
    fi
    
    log "INFO" "选择要恢复的内容..."
    
    # 检查可恢复的内容
    local can_restore_system=false
    local can_restore_user=false
    local can_restore_custom=false
    local can_restore_packages=false
    
    if [ -d "${SELECTED_BACKUP}/etc" ]; then
        can_restore_system=true
    fi
    
    if [ -d "${SELECTED_BACKUP}/home" ]; then
        can_restore_user=true
    fi
    
    if [ -d "${SELECTED_BACKUP}/custom" ]; then
        can_restore_custom=true
    fi
    
    if [ -d "${SELECTED_BACKUP}/packages" ] || [ -f "${SELECTED_BACKUP}/packages/pacman-packages.txt" ]; then
        can_restore_packages=true
    fi
    
    # 显示可恢复的内容
    echo -e "\n可恢复的内容:"
    echo "1. 系统配置 (/etc) $([ "$can_restore_system" == "true" ] && echo "[可用]" || echo "[不可用]")"
    echo "2. 用户配置 (${REAL_USER} 的配置文件) $([ "$can_restore_user" == "true" ] && echo "[可用]" || echo "[不可用]")"
    echo "3. 自定义路径 $([ "$can_restore_custom" == "true" ] && echo "[可用]" || echo "[不可用]")"
    echo "4. 软件包列表 $([ "$can_restore_packages" == "true" ] && echo "[可用]" || echo "[不可用]")"
    echo "5. 全部恢复"
    echo "0. 取消恢复"
    echo ""
    
    # 选择要恢复的内容
    local choice
    read -p "选择要恢复的内容 (0-5): " choice
    
    case $choice in
        0)
            log "INFO" "用户取消了恢复操作"
            return 1
            ;;
        1)
            if [ "$can_restore_system" == "true" ]; then
                RESTORE_SYSTEM_CONFIG=true
                RESTORE_USER_CONFIG=false
                RESTORE_CUSTOM_PATHS=false
                RESTORE_PACKAGES=false
                log "INFO" "将恢复系统配置"
            else
                log "ERROR" "备份中不包含系统配置"
                return 1
            fi
            ;;
        2)
            if [ "$can_restore_user" == "true" ]; then
                RESTORE_SYSTEM_CONFIG=false
                RESTORE_USER_CONFIG=true
                RESTORE_CUSTOM_PATHS=false
                RESTORE_PACKAGES=false
                log "INFO" "将恢复用户配置"
            else
                log "ERROR" "备份中不包含用户配置"
                return 1
            fi
            ;;
        3)
            if [ "$can_restore_custom" == "true" ]; then
                RESTORE_SYSTEM_CONFIG=false
                RESTORE_USER_CONFIG=false
                RESTORE_CUSTOM_PATHS=true
                RESTORE_PACKAGES=false
                log "INFO" "将恢复自定义路径"
            else
                log "ERROR" "备份中不包含自定义路径"
                return 1
            fi
            ;;
        4)
            if [ "$can_restore_packages" == "true" ]; then
                RESTORE_SYSTEM_CONFIG=false
                RESTORE_USER_CONFIG=false
                RESTORE_CUSTOM_PATHS=false
                RESTORE_PACKAGES=true
                log "INFO" "将恢复软件包列表"
            else
                log "ERROR" "备份中不包含软件包列表"
                return 1
            fi
            ;;
        5)
            RESTORE_SYSTEM_CONFIG=$can_restore_system
            RESTORE_USER_CONFIG=$can_restore_user
            RESTORE_CUSTOM_PATHS=$can_restore_custom
            RESTORE_PACKAGES=$can_restore_packages
            log "INFO" "将恢复所有可用内容"
            ;;
        *)
            log "ERROR" "无效的选择"
            return 1
            ;;
    esac
    
    return 0
}

# 确认恢复操作
# 功能：显示恢复操作的摘要并请求用户确认
# 参数：无，但使用多个全局变量来显示恢复信息
# 返回值：
#   0 - 用户确认恢复
#   1 - 用户取消恢复
# 使用示例：
#   if ! confirm_restore; then
#       log "INFO" "用户取消了恢复操作"
#       cleanup
#       exit 0
#   fi
confirm_restore() {
    if [ "$FORCE_RESTORE" == "true" ]; then
        log "INFO" "强制恢复模式: 跳过确认"
        return 0
    fi
    
    echo -e "\n恢复操作确认:"
    echo "备份源: $(basename "$SELECTED_BACKUP")"
    echo "将恢复以下内容:"
    [ "$RESTORE_SYSTEM_CONFIG" == "true" ] && echo "- 系统配置 (/etc)"
    [ "$RESTORE_USER_CONFIG" == "true" ] && echo "- 用户配置 (${REAL_USER} 的配置文件)"
    [ "$RESTORE_CUSTOM_PATHS" == "true" ] && echo "- 自定义路径"
    [ "$RESTORE_PACKAGES" == "true" ] && echo "- 软件包列表"
    
    if [ "$DRY_RUN" == "true" ]; then
        echo "模式: 仅测试 (不会实际恢复文件)"
    else
        echo "模式: 实际恢复"
        echo -e "${RED}警告: 此操作将覆盖现有文件!${NC}"
    fi
    
    echo ""
    read -p "确认执行恢复操作? (y/n): " confirm
    
    if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
        log "INFO" "用户取消了恢复操作"
        return 1
    fi
    
    return 0
}

# 恢复系统配置
# 功能：从备份中恢复系统配置（/etc目录）
# 参数：无，但使用全局变量 SELECTED_BACKUP 和 RESTORE_SYSTEM_CONFIG
# 返回值：
#   0 - 系统配置恢复成功或跳过
#   1 - 系统配置恢复失败
# 注意事项：
#   - 需要root权限
#   - 会先备份当前系统配置到临时目录
#   - 在测试模式下不会实际修改系统
# 使用示例：
#   if ! restore_system_config; then
#       log "ERROR" "系统配置恢复失败"
#   fi
restore_system_config() {
    if [ "$RESTORE_SYSTEM_CONFIG" != "true" ]; then
        log "INFO" "跳过系统配置恢复"
        return 0
    fi
    
    log "INFO" "开始恢复系统配置..."
    
    # 检查系统配置备份是否存在
    if [ ! -d "${SELECTED_BACKUP}/etc" ]; then
        log "ERROR" "系统配置备份不存在: ${SELECTED_BACKUP}/etc"
        return 1
    fi
    
    # 检查是否有root权限
    if [ "$(id -u)" != "0" ]; then
        log "ERROR" "恢复系统配置需要root权限"
        return 1
    fi
    
    # 如果是测试模式，创建临时目录
    local target_dir="/etc"
    if [ "$DRY_RUN" == "true" ]; then
        target_dir="/tmp/arch-restore-test/etc"
        mkdir -p "$target_dir"
        log "INFO" "测试模式: 将恢复到 $target_dir"
    fi
    
    # 备份当前系统配置
    if [ "$DRY_RUN" != "true" ]; then
        local etc_backup_dir="/tmp/etc_backup_${TIMESTAMP}"
        log "INFO" "备份当前系统配置到: $etc_backup_dir"
        mkdir -p "$etc_backup_dir"
        rsync -aAX /etc/ "$etc_backup_dir/" > /dev/null 2>&1 || {
            log "ERROR" "备份当前系统配置失败"
            return 1
        }
    fi
    
    # 恢复系统配置
    log "INFO" "恢复系统配置到: $target_dir"
    
    # 使用rsync恢复，保留权限和所有权
    if [ "$DRY_RUN" == "true" ]; then
        # 测试模式，使用--dry-run选项
        rsync -aAXv --dry-run "${SELECTED_BACKUP}/etc/" "$target_dir/" | tee -a "$LOG_FILE"
        log "INFO" "测试模式: 系统配置恢复模拟完成"
    else
        # 实际恢复
        rsync -aAX "${SELECTED_BACKUP}/etc/" "$target_dir/" > /dev/null 2>&1 || {
            log "ERROR" "系统配置恢复失败"
            return 1
        }
        log "INFO" "系统配置恢复完成"
    fi
    
    return 0
}

# 恢复用户配置
# 功能：从备份中恢复用户配置文件（家目录下的配置文件）
# 参数：无，但使用全局变量 SELECTED_BACKUP 和 RESTORE_USER_CONFIG
# 返回值：
#   0 - 用户配置恢复成功或跳过
#   1 - 用户配置恢复部分失败
# 注意事项：
#   - 会处理文件冲突，提供多种冲突解决选项
#   - 在测试模式下不会实际修改用户文件
# 使用示例：
#   if ! restore_user_config; then
#       log "WARN" "用户配置恢复部分失败"
#   fi
restore_user_config() {
    if [ "$RESTORE_USER_CONFIG" != "true" ]; then
        log "INFO" "跳过用户配置恢复"
        return 0
    fi
    
    log "INFO" "开始恢复用户配置..."
    
    # 检查用户配置备份是否存在
    if [ ! -d "${SELECTED_BACKUP}/home" ]; then
        log "ERROR" "用户配置备份不存在: ${SELECTED_BACKUP}/home"
        return 1
    fi
    
    # 如果是测试模式，创建临时目录
    local target_dir="$REAL_HOME"
    if [ "$DRY_RUN" == "true" ]; then
        target_dir="/tmp/arch-restore-test/home"
        mkdir -p "$target_dir"
        log "INFO" "测试模式: 将恢复到 $target_dir"
    fi
    
    # 备份当前用户配置
    if [ "$DRY_RUN" != "true" ] && [ "$INTERACTIVE" == "true" ]; then
        local home_backup_dir="/tmp/home_backup_${TIMESTAMP}"
        log "INFO" "备份当前用户配置到: $home_backup_dir"
        mkdir -p "$home_backup_dir"
        
        # 从配置文件中读取用户配置文件列表
        IFS=' ' read -r -a user_dirs <<< "$USER_CONFIG_FILES"
        
        for dir in "${user_dirs[@]}"; do
            local src_path="$REAL_HOME/$dir"
            local dest_path="$home_backup_dir/$dir"
            
            if [ -e "$src_path" ]; then
                mkdir -p "$(dirname "$dest_path")"
                cp -a "$src_path" "$dest_path" 2>/dev/null || log "WARN" "无法备份: $src_path"
            fi
        done
    fi
    
    # 恢复用户配置
    log "INFO" "恢复用户配置到: $target_dir"
    
    # 从备份中恢复用户配置文件
    local restore_errors=0
    
    # 遍历备份中的用户配置文件
    find "${SELECTED_BACKUP}/home" -type f | while read -r file; do
        # 获取相对路径
        local rel_path=${file#${SELECTED_BACKUP}/home/}
        local target_file="$target_dir/$rel_path"
        
        # 创建目标目录
        mkdir -p "$(dirname "$target_file")"
        
        # 检查是否存在冲突
        local conflict=false
        if [ -f "$target_file" ] && [ "$INTERACTIVE" == "true" ] && [ "$FORCE_RESTORE" != "true" ] && [ "$DRY_RUN" != "true" ]; then
            if ! diff -q "$file" "$target_file" > /dev/null 2>&1; then
                conflict=true
                echo -e "\n文件冲突: $rel_path"
                echo "1. 使用备份文件覆盖"
                echo "2. 保留当前文件"
                echo "3. 查看差异"
                echo "4. 对所有冲突使用备份文件"
                echo "5. 对所有冲突保留当前文件"
                
                local choice
                read -p "选择操作 (1-5): " choice
                
                case $choice in
                    1)
                        # 使用备份文件覆盖
                        log "INFO" "使用备份文件覆盖: $rel_path"
                        ;;
                    2)
                        # 保留当前文件
                        log "INFO" "保留当前文件: $rel_path"
                        continue
                        ;;
                    3)
                        # 查看差异
                        echo -e "\n文件差异:"
                        diff -u "$target_file" "$file" | less
                        
                        echo -e "\n1. 使用备份文件覆盖"
                        echo "2. 保留当前文件"
                        
                        read -p "选择操作 (1-2): " subchoice
                        
                        if [ "$subchoice" == "2" ]; then
                            log "INFO" "保留当前文件: $rel_path"
                            continue
                        fi
                        ;;
                    4)
                        # 对所有冲突使用备份文件
                        log "INFO" "对所有冲突使用备份文件"
                        FORCE_RESTORE=true
                        ;;
                    5)
                        # 对所有冲突保留当前文件
                        log "INFO" "对所有冲突保留当前文件"
                        SKIP_ALL_CONFLICTS=true
                        continue
                        ;;
                    *)
                        log "WARN" "无效的选择，使用备份文件覆盖"
                        ;;
                esac
            fi
        fi
        
        # 如果设置了跳过所有冲突
        if [ "$SKIP_ALL_CONFLICTS" == "true" ] && [ "$conflict" == "true" ]; then
            continue
        fi
        
        # 复制文件
        if [ "$DRY_RUN" == "true" ]; then
            log "INFO" "测试模式: 将恢复文件 $rel_path"
        else
            if cp -a "$file" "$target_file" 2>/dev/null; then
                log "DEBUG" "恢复文件成功: $rel_path"
            else
                log "ERROR" "恢复文件失败: $rel_path"
                restore_errors=$((restore_errors + 1))
            fi
        fi
    done
    
    if [ $restore_errors -eq 0 ]; then
        log "INFO" "用户配置恢复完成"
        return 0
    else
        log "WARN" "用户配置恢复部分失败，有 $restore_errors 个错误"
        return 1
    fi
}

# 恢复自定义路径
# 功能：从备份中恢复自定义路径（如/opt, /var/www等）
# 参数：无，但使用全局变量 SELECTED_BACKUP 和 RESTORE_CUSTOM_PATHS
# 返回值：
#   0 - 自定义路径恢复成功或跳过
#   1 - 自定义路径恢复部分失败
# 注意事项：
#   - 可能需要root权限（取决于恢复路径）
#   - 会处理路径冲突，提供多种冲突解决选项
#   - 在测试模式下不会实际修改文件系统
# 使用示例：
#   if ! restore_custom_paths; then
#       log "WARN" "自定义路径恢复部分失败"
#   fi
restore_custom_paths() {
    if [ "$RESTORE_CUSTOM_PATHS" != "true" ]; then
        log "INFO" "跳过自定义路径恢复"
        return 0
    fi
    
    log "INFO" "开始恢复自定义路径..."
    
    # 检查自定义路径备份是否存在
    if [ ! -d "${SELECTED_BACKUP}/custom" ]; then
        log "ERROR" "自定义路径备份不存在: ${SELECTED_BACKUP}/custom"
        return 1
    fi
    
    # 检查是否有root权限（可能需要恢复到系统目录）
    if [ "$(id -u)" != "0" ] && [ "$DRY_RUN" != "true" ]; then
        log "WARN" "恢复自定义路径可能需要root权限"
    fi
    
    # 从配置文件中读取自定义路径列表
    IFS=' ' read -r -a custom_paths <<< "$CUSTOM_PATHS"
    
    if [ ${#custom_paths[@]} -eq 0 ]; then
        log "WARN" "未配置自定义路径，但备份中存在自定义路径数据"
        
        # 列出备份中的自定义路径
        echo -e "\n备份中的自定义路径:"
        ls -la "${SELECTED_BACKUP}/custom/"
        
        if [ "$INTERACTIVE" == "true" ]; then
            read -p "是否恢复所有自定义路径? (y/n): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                log "INFO" "用户取消了自定义路径恢复"
                return 0
            fi
        fi
    fi
    
    # 恢复自定义路径
    local restore_errors=0
    local restored_count=0
    
    # 遍历备份中的自定义路径
    for item in "${SELECTED_BACKUP}/custom"/*; do
        if [ ! -e "$item" ]; then
            continue
        fi
        
        local base_name=$(basename "$item")
        local original_path=""
        
        # 查找对应的原始路径
        for path in "${custom_paths[@]}"; do
            if [ "$(basename "$path")" == "$base_name" ]; then
                original_path="$path"
                break
            fi
        done
        
        # 如果找不到对应的原始路径，使用默认路径
        if [ -z "$original_path" ]; then
            if [ "$INTERACTIVE" == "true" ] && [ "$FORCE_RESTORE" != "true" ]; then
                echo -e "\n未找到自定义路径 '$base_name' 的原始路径"
                echo "请输入要恢复到的路径 (留空跳过):"
                read -p "> " custom_path
                
                if [ -z "$custom_path" ]; then
                    log "INFO" "跳过恢复: $base_name"
                    continue
                fi
                
                original_path="$custom_path"
            else
                # 默认恢复到原始位置
                if [[ "$base_name" == /* ]]; then
                    # 如果是绝对路径（去除了前导斜杠）
                    original_path="$base_name"
                else
                    # 默认恢复到/opt目录
                    original_path="/opt/$base_name"
                fi
            fi
        fi
        
        log "INFO" "恢复自定义路径: $base_name -> $original_path"
        
        # 如果是测试模式，创建临时目录
        local target_dir="$original_path"
        if [ "$DRY_RUN" == "true" ]; then
            target_dir="/tmp/arch-restore-test/custom/$base_name"
            mkdir -p "$(dirname "$target_dir")"
            log "INFO" "测试模式: 将恢复到 $target_dir"
        else
            # 检查目标路径是否存在
            if [ -e "$target_dir" ]; then
                # 如果目标是目录且备份也是目录，不需要创建
                if [ -d "$target_dir" ] && [ -d "$item" ]; then
                    :  # 不做任何操作
                else
                    # 如果存在冲突
                    if [ "$INTERACTIVE" == "true" ] && [ "$FORCE_RESTORE" != "true" ]; then
                        echo -e "\n路径冲突: $original_path 已存在"
                        echo "1. 覆盖现有路径"
                        echo "2. 跳过此路径"
                        echo "3. 恢复到其他位置"
                        
                        local choice
                        read -p "选择操作 (1-3): " choice
                        
                        case $choice in
                            1)
                                # 覆盖现有路径
                                log "INFO" "覆盖现有路径: $original_path"
                                # 备份现有路径
                                local path_backup="/tmp/custom_backup_${TIMESTAMP}_$base_name"
                                log "INFO" "备份现有路径到: $path_backup"
                                mkdir -p "$(dirname "$path_backup")"
                                cp -a "$target_dir" "$path_backup" 2>/dev/null || log "WARN" "无法备份: $target_dir"
                                ;;
                            2)
                                # 跳过此路径
                                log "INFO" "跳过恢复: $base_name"
                                continue
                                ;;
                            3)
                                # 恢复到其他位置
                                echo "请输入要恢复到的新路径:"
                                read -p "> " new_path
                                
                                if [ -z "$new_path" ]; then
                                    log "INFO" "跳过恢复: $base_name"
                                    continue
                                fi
                                
                                target_dir="$new_path"
                                log "INFO" "将恢复到新路径: $target_dir"
                                ;;
                            *)
                                log "WARN" "无效的选择，跳过恢复"
                                continue
                                ;;
                        esac
                    else
                        # 非交互模式或强制恢复，备份现有路径
                        local path_backup="/tmp/custom_backup_${TIMESTAMP}_$base_name"
                        log "INFO" "备份现有路径到: $path_backup"
                        mkdir -p "$(dirname "$path_backup")"
                        cp -a "$target_dir" "$path_backup" 2>/dev/null || log "WARN" "无法备份: $target_dir"
                    fi
                fi
            fi
            
            # 创建目标目录的父目录
            mkdir -p "$(dirname "$target_dir")"
        fi
        
        # 恢复文件或目录
        if [ "$DRY_RUN" == "true" ]; then
            log "INFO" "测试模式: 将恢复 $base_name 到 $target_dir"
        else
            if [ -d "$item" ]; then
                # 如果是目录，使用rsync恢复
                if rsync -aAX "$item/" "$target_dir/" > /dev/null 2>&1; then
                    log "INFO" "恢复目录成功: $base_name -> $target_dir"
                    restored_count=$((restored_count + 1))
                else
                    log "ERROR" "恢复目录失败: $base_name -> $target_dir"
                    restore_errors=$((restore_errors + 1))
                fi
            else
                # 如果是文件，直接复制
                if cp -a "$item" "$target_dir" > /dev/null 2>&1; then
                    log "INFO" "恢复文件成功: $base_name -> $target_dir"
                    restored_count=$((restored_count + 1))
                else
                    log "ERROR" "恢复文件失败: $base_name -> $target_dir"
                    restore_errors=$((restore_errors + 1))
                fi
            fi
        fi
    done
    
    if [ $restored_count -eq 0 ]; then
        log "WARN" "未恢复任何自定义路径"
        return 0
    elif [ $restore_errors -eq 0 ]; then
        log "INFO" "自定义路径恢复完成，共恢复 $restored_count 个路径"
        return 0
    else
        log "WARN" "自定义路径恢复部分失败，恢复 $restored_count 个路径，有 $restore_errors 个错误"
        return 1
    fi
}

# 恢复软件包列表
# 功能：从备份中恢复软件包列表（官方仓库和AUR）
# 参数：无，但使用全局变量 SELECTED_BACKUP 和 RESTORE_PACKAGES
# 返回值：
#   0 - 软件包列表恢复成功或跳过
#   1 - 软件包列表恢复失败
# 注意事项：
#   - 需要root权限
#   - 恢复AUR软件包需要AUR助手（yay, paru或pamac）
#   - 在测试模式下不会实际安装软件包
# 使用示例：
#   if ! restore_packages; then
#       log "ERROR" "软件包列表恢复失败"
#   fi
restore_packages() {
    if [ "$RESTORE_PACKAGES" != "true" ]; then
        log "INFO" "跳过软件包列表恢复"
        return 0
    fi
    
    log "INFO" "开始恢复软件包列表..."
    
    # 检查软件包列表备份是否存在
    if [ ! -d "${SELECTED_BACKUP}/packages" ] && [ ! -f "${SELECTED_BACKUP}/packages/pacman-packages.txt" ]; then
        log "ERROR" "软件包列表备份不存在: ${SELECTED_BACKUP}/packages/pacman-packages.txt"
        return 1
    fi
    
    # 检查是否有root权限
    if [ "$(id -u)" != "0" ] && [ "$DRY_RUN" != "true" ]; then
        log "ERROR" "恢复软件包列表需要root权限"
        return 1
    fi
    
    # 检查pacman命令是否存在
    if ! command -v pacman >/dev/null 2>&1 && [ "$DRY_RUN" != "true" ]; then
        log "ERROR" "未找到pacman命令，无法恢复软件包列表"
        return 1
    fi
    
    # 恢复官方软件包列表
    local pacman_packages_file="${SELECTED_BACKUP}/packages/pacman-packages.txt"
    if [ -f "$pacman_packages_file" ]; then
        log "INFO" "恢复官方软件包列表..."
        
        # 读取软件包列表
        local packages=$(cat "$pacman_packages_file")
        local package_count=$(echo "$packages" | wc -l)
        
        log "INFO" "备份中包含 $package_count 个官方软件包"
        
        if [ "$INTERACTIVE" == "true" ]; then
            echo -e "\n备份中的官方软件包列表:"
            echo "$packages" | head -n 10
            [ $package_count -gt 10 ] && echo "... 等 $package_count 个软件包"
            
            read -p "是否恢复官方软件包列表? (y/n): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                log "INFO" "用户取消了官方软件包列表恢复"
                return 0
            fi
        fi
        
        if [ "$DRY_RUN" == "true" ]; then
            log "INFO" "测试模式: 将恢复 $package_count 个官方软件包"
        else
            # 恢复软件包
            log "INFO" "开始恢复官方软件包，这可能需要一些时间..."
            
            # 使用pacman安装软件包
            if pacman -S --needed --noconfirm $(cat "$pacman_packages_file") > /dev/null 2>&1; then
                log "INFO" "官方软件包恢复成功"
            else
                log "WARN" "官方软件包恢复部分失败，请检查pacman输出"
            fi
        fi
    else
        log "WARN" "未找到官方软件包列表: $pacman_packages_file"
    fi
    
    # 恢复AUR软件包列表
    local aur_packages_file="${SELECTED_BACKUP}/packages/aur-packages.txt"
    if [ -f "$aur_packages_file" ]; then
        log "INFO" "恢复AUR软件包列表..."
        
        # 读取软件包列表
        local aur_packages=$(cat "$aur_packages_file")
        local aur_package_count=$(echo "$aur_packages" | wc -l)
        
        log "INFO" "备份中包含 $aur_package_count 个AUR软件包"
        
        if [ "$INTERACTIVE" == "true" ]; then
            echo -e "\n备份中的AUR软件包列表:"
            echo "$aur_packages" | head -n 10
            [ $aur_package_count -gt 10 ] && echo "... 等 $aur_package_count 个软件包"
            
            read -p "是否恢复AUR软件包列表? (y/n): " confirm
            if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
                log "INFO" "用户取消了AUR软件包列表恢复"
                return 0
            fi
            
            # 检查AUR助手
            local aur_helper=""
            for helper in yay paru pamac; do
                if command -v $helper >/dev/null 2>&1; then
                    aur_helper=$helper
                    break
                fi
            done
            
            if [ -z "$aur_helper" ]; then
                echo -e "\n未检测到AUR助手 (yay, paru, pamac)"
                echo "请输入要使用的AUR助手名称 (留空跳过AUR软件包恢复):"
                read -p "> " aur_helper
                
                if [ -z "$aur_helper" ]; then
                    log "INFO" "跳过AUR软件包恢复"
                    return 0
                fi
                
                if ! command -v $aur_helper >/dev/null 2>&1; then
                    log "ERROR" "未找到AUR助手: $aur_helper"
                    return 1
                fi
            fi
        else
            # 非交互模式，自动检测AUR助手
            for helper in yay paru pamac; do
                if command -v $helper >/dev/null 2>&1; then
                    aur_helper=$helper
                    break
                fi
            done
            
            if [ -z "$aur_helper" ]; then
                log "WARN" "未检测到AUR助手，跳过AUR软件包恢复"
                return 0
            fi
        fi
        
        if [ "$DRY_RUN" == "true" ]; then
            log "INFO" "测试模式: 将使用 $aur_helper 恢复 $aur_package_count 个AUR软件包"
        else
            # 恢复AUR软件包
            log "INFO" "开始使用 $aur_helper 恢复AUR软件包，这可能需要一些时间..."
            
            # 使用AUR助手安装软件包
            case $aur_helper in
                yay)
                    if yay -S --needed --noconfirm $(cat "$aur_packages_file") > /dev/null 2>&1; then
                        log "INFO" "AUR软件包恢复成功"
                    else
                        log "WARN" "AUR软件包恢复部分失败，请检查yay输出"
                    fi
                    ;;
                paru)
                    if paru -S --needed --noconfirm $(cat "$aur_packages_file") > /dev/null 2>&1; then
                        log "INFO" "AUR软件包恢复成功"
                    else
                        log "WARN" "AUR软件包恢复部分失败，请检查paru输出"
                    fi
                    ;;
                pamac)
                    if pamac install --no-confirm $(cat "$aur_packages_file") > /dev/null 2>&1; then
                        log "INFO" "AUR软件包恢复成功"
                    else
                        log "WARN" "AUR软件包恢复部分失败，请检查pamac输出"
                    fi
                    ;;
                *)
                    log "ERROR" "不支持的AUR助手: $aur_helper"
                    return 1
                    ;;
            esac
        fi
    else
        log "INFO" "未找到AUR软件包列表: $aur_packages_file"
    fi
    
    log "INFO" "软件包列表恢复完成"
    return 0
}

# 清理临时文件
# 功能：清理恢复过程中创建的临时文件和目录
# 参数：无，但使用全局变量 TEMP_EXTRACT_DIR 和 DRY_RUN
# 返回值：无
# 注意事项：
#   - 应在脚本结束前调用，无论恢复成功与否
#   - 会删除临时解压目录和测试模式的临时目录
# 使用示例：
#   cleanup
#   exit 0
cleanup() {
    log "INFO" "清理临时文件..."
    
    # 清理临时解压目录
    if [ -n "$TEMP_EXTRACT_DIR" ] && [ -d "$TEMP_EXTRACT_DIR" ]; then
        log "INFO" "删除临时解压目录: $TEMP_EXTRACT_DIR"
        rm -rf "$TEMP_EXTRACT_DIR"
    fi
    
    # 清理测试模式的临时目录
    if [ "$DRY_RUN" == "true" ] && [ -d "/tmp/arch-restore-test" ]; then
        log "INFO" "删除测试模式临时目录: /tmp/arch-restore-test"
        rm -rf "/tmp/arch-restore-test"
    fi
    
    log "INFO" "清理完成"
}

# 显示帮助信息
# 功能：显示脚本的使用方法和可用选项
# 参数：无
# 返回值：无
# 使用示例：
#   show_help
#   exit 0
show_help() {
    echo "Arch Linux 自动恢复脚本"
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  -h, --help              显示此帮助信息"
    echo "  -b, --backup-dir DIR     指定备份目录 (默认: $BACKUP_ROOT)"
    echo "  -s, --selected-backup DIR 直接指定要恢复的备份"
    echo "  -c, --config FILE        指定配置文件 (默认: $CONFIG_FILE)"
    echo "  -n, --non-interactive    非交互模式 (自动恢复所有内容)"
    echo "  -f, --force              强制恢复 (不询问确认)"
    echo "  -d, --dry-run            测试模式 (不实际恢复文件)"
    echo "  --system-only            仅恢复系统配置"
    echo "  --user-only              仅恢复用户配置"
    echo "  --custom-only            仅恢复自定义路径"
    echo "  --packages-only          仅恢复软件包列表"
    echo ""
    echo "示例:"
    echo "  $0 -b /mnt/backup/arch-backup -n -f  # 从指定目录非交互式强制恢复"
    echo "  $0 --dry-run                        # 测试模式，不实际恢复文件"
    echo "  $0 --system-only                    # 仅恢复系统配置"
}

# 主函数
# 功能：脚本的主要执行流程，处理命令行参数并调用其他函数
# 参数：
#   $@ - 命令行参数
# 返回值：
#   0 - 恢复成功
#   非0 - 恢复失败
# 使用示例：
#   main "$@"
#   exit $?
main() {
    # 检查是否有参数
    if [ $# -eq 0 ]; then
        # 无参数，使用默认配置
        log "INFO" "使用默认配置启动恢复脚本"
    fi
    
    # 解析命令行参数
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -b|--backup-dir)
                BACKUP_ROOT="$2"
                shift 2
                ;;
            -s|--selected-backup)
                SELECTED_BACKUP="$2"
                shift 2
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -n|--non-interactive)
                INTERACTIVE=false
                shift
                ;;
            -f|--force)
                FORCE_RESTORE=true
                shift
                ;;
            -d|--dry-run)
                DRY_RUN=true
                shift
                ;;
            --system-only)
                RESTORE_SYSTEM_CONFIG=true
                RESTORE_USER_CONFIG=false
                RESTORE_CUSTOM_PATHS=false
                RESTORE_PACKAGES=false
                shift
                ;;
            --user-only)
                RESTORE_SYSTEM_CONFIG=false
                RESTORE_USER_CONFIG=true
                RESTORE_CUSTOM_PATHS=false
                RESTORE_PACKAGES=false
                shift
                ;;
            --custom-only)
                RESTORE_SYSTEM_CONFIG=false
                RESTORE_USER_CONFIG=false
                RESTORE_CUSTOM_PATHS=true
                RESTORE_PACKAGES=false
                shift
                ;;
            --packages-only)
                RESTORE_SYSTEM_CONFIG=false
                RESTORE_USER_CONFIG=false
                RESTORE_CUSTOM_PATHS=false
                RESTORE_PACKAGES=true
                shift
                ;;
            *)
                log "ERROR" "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 创建日志目录
    mkdir -p "$(dirname "$LOG_FILE")"
    
    # 显示欢迎信息
    echo -e "${GREEN}=== Arch Linux 自动恢复脚本 ===${NC}"
    echo -e "${BLUE}开始时间: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    echo -e "${BLUE}日志文件: $LOG_FILE${NC}"
    echo ""
    
    # 检查依赖
    if ! check_dependencies; then
        log "FATAL" "依赖检查失败，请安装必要的依赖后重试"
        exit 1
    fi
    
    # 加载配置文件
    load_config
    
    # 如果没有直接指定备份，则选择备份
    if [ -z "$SELECTED_BACKUP" ]; then
        if ! select_backup; then
            log "FATAL" "备份选择失败，退出脚本"
            exit 1
        fi
    else
        # 检查指定的备份是否存在
        if [ ! -d "$SELECTED_BACKUP" ] && [ ! -f "$SELECTED_BACKUP" ]; then
            log "FATAL" "指定的备份不存在: $SELECTED_BACKUP"
            exit 1
        fi
        
        # 确定备份类型
        if [ -d "$SELECTED_BACKUP" ]; then
            BACKUP_TYPE="directory"
            log "INFO" "使用指定的备份目录: $SELECTED_BACKUP"
        else
            BACKUP_TYPE="compressed"
            log "INFO" "使用指定的压缩备份: $SELECTED_BACKUP"
        fi
    fi
    
    # 如果是压缩备份，解压
    if [ "$BACKUP_TYPE" == "compressed" ]; then
        if ! extract_backup; then
            log "FATAL" "备份解压失败，退出脚本"
            exit 1
        fi
    fi
    
    # 检查备份完整性
    if ! check_backup_integrity; then
        log "FATAL" "备份完整性检查失败，退出脚本"
        exit 1
    fi
    
    # 如果没有指定恢复内容，则选择要恢复的内容
    if [ -z "$RESTORE_SYSTEM_CONFIG" ] && [ -z "$RESTORE_USER_CONFIG" ] && 
       [ -z "$RESTORE_CUSTOM_PATHS" ] && [ -z "$RESTORE_PACKAGES" ]; then
        if ! select_restore_content; then
            log "FATAL" "恢复内容选择失败，退出脚本"
            exit 1
        fi
    fi
    
    # 确认恢复操作
    if ! confirm_restore; then
        log "INFO" "用户取消了恢复操作，退出脚本"
        exit 0
    fi
    
    # 执行恢复操作
    local restore_errors=0
    
    # 恢复系统配置
    if ! restore_system_config; then
        restore_errors=$((restore_errors + 1))
    fi
    
    # 恢复用户配置
    if ! restore_user_config; then
        restore_errors=$((restore_errors + 1))
    fi
    
    # 恢复自定义路径
    if ! restore_custom_paths; then
        restore_errors=$((restore_errors + 1))
    fi
    
    # 恢复软件包列表
    if ! restore_packages; then
        restore_errors=$((restore_errors + 1))
    fi
    
    # 清理临时文件
    cleanup
    
    # 显示恢复结果
    echo -e "\n${GREEN}=== 恢复操作完成 ===${NC}"
    echo -e "${BLUE}结束时间: $(date '+%Y-%m-%d %H:%M:%S')${NC}"
    
    if [ $restore_errors -eq 0 ]; then
        log "INFO" "所有恢复操作成功完成"
        echo -e "${GREEN}恢复状态: 成功${NC}"
    else
        log "WARN" "部分恢复操作失败，共有 $restore_errors 个错误"
        echo -e "${YELLOW}恢复状态: 部分成功 (有 $restore_errors 个错误)${NC}"
    fi
    
    echo -e "${BLUE}详细日志: $LOG_FILE${NC}"
    
    # 如果是测试模式，显示提示
    if [ "$DRY_RUN" == "true" ]; then
        echo -e "\n${YELLOW}注意: 这是测试模式，没有实际恢复任何文件${NC}"
        echo -e "${YELLOW}测试结果保存在: /tmp/arch-restore-test/${NC}"
    fi
    
    return $restore_errors
}

# 执行主函数
main "$@"
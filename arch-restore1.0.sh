#!/bin/bash

#############################################################
# Arch Linux 自动恢复脚本
# 配套 arch-backup.sh 使用
# 功能：从备份中恢复系统配置、用户配置、自定义路径、软件包列表
# 支持选择性恢复、权限处理和恢复后验证
# 1.0 版本：基础恢复功能
#   - 支持从备份目录或压缩文件恢复
#   - 支持选择性恢复（系统配置、用户配置、自定义路径、软件包）
#   - 支持恢复前验证和恢复后验证
#   - 详细的恢复日志和错误处理
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
RESTORE_DIR="/tmp/arch-restore_${TIMESTAMP}"

# 恢复选项
RESTORE_SYSTEM_CONFIG=false
RESTORE_USER_CONFIG=false
RESTORE_CUSTOM_PATHS=false
RESTORE_PACKAGES=false
FORCE_RESTORE=false
VERIFY_RESTORE=true
INTERACTIVE_MODE=true

# 创建日志函数
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
check_command() {
    command -v "$1" >/dev/null 2>&1 || { log "ERROR" "命令 $1 未安装，请先安装该命令"; exit 1; }
}

# 检查必要的命令
check_dependencies() {
    log "INFO" "检查依赖..."
    local missing_deps=0
    
    # 核心依赖检查 - 这些是必须的
    log "INFO" "检查核心依赖..."
    local core_deps=("rsync" "pacman" "tar" "find" "grep" "awk" "sed" "diff")
    local core_desc=("远程同步工具" "包管理器" "归档工具" "文件查找工具" "文本搜索工具" "文本处理工具" "流编辑器" "文件比较工具")
    
    for i in "${!core_deps[@]}"; do
        if ! command -v "${core_deps[$i]}" >/dev/null 2>&1; then
            log "ERROR" "核心依赖 ${core_deps[$i]} (${core_desc[$i]}) 未安装"
            log "INFO" "请使用以下命令安装: sudo pacman -S ${core_deps[$i]}"
            missing_deps=$((missing_deps + 1))
        else
            log "INFO" "核心依赖 ${core_deps[$i]} 已安装"
        fi
    done
    
    # 解压工具依赖检查
    log "INFO" "检查解压工具依赖..."
    local compression_tools=("gzip" "bzip2" "xz")
    local compression_desc=("gzip解压工具" "bzip2解压工具" "xz解压工具")
    
    for i in "${!compression_tools[@]}"; do
        if ! command -v "${compression_tools[$i]}" >/dev/null 2>&1; then
            log "WARN" "解压工具 ${compression_tools[$i]} 未安装，如需恢复该格式的备份请先安装"
        else
            log "DEBUG" "解压工具 ${compression_tools[$i]} 已安装"
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
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "INFO" "加载配置文件: $CONFIG_FILE"
        source "$CONFIG_FILE"
    else
        log "WARN" "配置文件不存在，使用默认配置"
    fi
}

# 带重试功能的执行命令
exec_with_retry() {
    local cmd=$1
    local desc=$2
    local max_retries=${3:-3}
    local retry_delay=${4:-5}
    local retry_count=0
    local exit_code=0
    
    log "DEBUG" "执行命令: $cmd"
    
    while [ $retry_count -lt $max_retries ]; do
        eval $cmd
        exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            if [ $retry_count -gt 0 ]; then
                log "INFO" "$desc 在第 $retry_count 次重试后成功"
            fi
            return 0
        else
            retry_count=$((retry_count + 1))
            if [ $retry_count -lt $max_retries ]; then
                log "WARN" "$desc 失败 (退出码: $exit_code)，$retry_delay 秒后进行第 $retry_count 次重试..."
                sleep $retry_delay
            else
                log "ERROR" "$desc 在 $max_retries 次尝试后仍然失败"
            fi
        fi
    done
    
    return $exit_code
}

# 检查文件完整性
check_file_integrity() {
    local file_path=$1
    local desc=$2
    
    if [ ! -e "$file_path" ]; then
        log "ERROR" "完整性检查失败: $desc 文件不存在: $file_path"
        return 1
    fi
    
    if [ -f "$file_path" ] && [ ! -s "$file_path" ]; then
        log "ERROR" "完整性检查失败: $desc 文件大小为零: $file_path"
        return 1
    fi
    
    log "DEBUG" "完整性检查通过: $desc"
    return 0
}

# 列出可用的备份
list_available_backups() {
    log "INFO" "列出可用的备份..."
    
    # 检查备份根目录是否存在
    if [ ! -d "$BACKUP_ROOT" ]; then
        log "ERROR" "备份根目录不存在: $BACKUP_ROOT"
        return 1
    fi
    
    # 获取所有备份目录和压缩文件
    local backup_dirs=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" | sort))
    local backup_archives=($(find "$BACKUP_ROOT" -maxdepth 1 -type f -name "????-??-??_backup.tar*" | sort))
    
    # 显示可用的备份目录
    if [ ${#backup_dirs[@]} -gt 0 ]; then
        echo -e "\n可用的备份目录:"
        for i in "${!backup_dirs[@]}"; do
            local dir=${backup_dirs[$i]}
            local date_str=$(basename "$dir")
            local summary_file="$dir/backup-summary.txt"
            
            echo "$((i+1)). $date_str"
            if [ -f "$summary_file" ]; then
                echo "   摘要: $(grep '备份时间' "$summary_file" | head -1)"
                grep -E '- 系统配置文件|- 用户配置文件|- 自定义路径备份|- 软件包列表|- 系统日志' "$summary_file" | sed 's/^/   /'
            else
                echo "   (无摘要信息)"
            fi
            echo ""
        done
    else
        echo "没有找到可用的备份目录"
    fi
    
    # 显示可用的备份压缩文件
    if [ ${#backup_archives[@]} -gt 0 ]; then
        echo -e "\n可用的备份压缩文件:"
        for i in "${!backup_archives[@]}"; do
            local archive=${backup_archives[$i]}
            local date_str=$(basename "$archive" | sed 's/_backup.tar.*//')
            local size=$(du -h "$archive" | cut -f1)
            
            echo "$((i+1+${#backup_dirs[@]})). $date_str (${size})"
            echo "   文件: $(basename "$archive")"
            echo ""
        done
    else
        echo "没有找到可用的备份压缩文件"
    fi
    
    return 0
}

# 选择备份
select_backup() {
    log "INFO" "选择要恢复的备份..."
    
    # 获取所有备份目录和压缩文件
    local backup_dirs=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" | sort))
    local backup_archives=($(find "$BACKUP_ROOT" -maxdepth 1 -type f -name "????-??-??_backup.tar*" | sort))
    
    local total_backups=$((${#backup_dirs[@]} + ${#backup_archives[@]}))
    
    if [ $total_backups -eq 0 ]; then
        log "ERROR" "没有找到可用的备份"
        return 1
    fi
    
    # 如果只有一个备份且非交互模式，自动选择
    if [ $total_backups -eq 1 ] && [ "$INTERACTIVE_MODE" != "true" ]; then
        if [ ${#backup_dirs[@]} -eq 1 ]; then
            SELECTED_BACKUP=${backup_dirs[0]}
            BACKUP_TYPE="directory"
        else
            SELECTED_BACKUP=${backup_archives[0]}
            BACKUP_TYPE="archive"
        fi
        log "INFO" "自动选择唯一可用的备份: $SELECTED_BACKUP"
        return 0
    fi
    
    # 交互式选择备份
    if [ "$INTERACTIVE_MODE" == "true" ]; then
        list_available_backups
        
        echo -e "\n请选择要恢复的备份 (1-$total_backups):"
        read -p "> " backup_choice
        
        # 验证输入
        if ! [[ "$backup_choice" =~ ^[0-9]+$ ]] || [ "$backup_choice" -lt 1 ] || [ "$backup_choice" -gt $total_backups ]; then
            log "ERROR" "无效的选择: $backup_choice"
            return 1
        fi
        
        # 确定选择的是目录还是压缩文件
        if [ "$backup_choice" -le ${#backup_dirs[@]} ]; then
            SELECTED_BACKUP=${backup_dirs[$((backup_choice-1))]}
            BACKUP_TYPE="directory"
        else
            SELECTED_BACKUP=${backup_archives[$((backup_choice-1-${#backup_dirs[@]}))]}
            BACKUP_TYPE="archive"
        fi
        
        log "INFO" "已选择备份: $SELECTED_BACKUP (类型: $BACKUP_TYPE)"
    else
        # 非交互模式，使用最新的备份
        if [ ${#backup_dirs[@]} -gt 0 ]; then
            SELECTED_BACKUP=${backup_dirs[${#backup_dirs[@]}-1]}
            BACKUP_TYPE="directory"
        else
            SELECTED_BACKUP=${backup_archives[${#backup_archives[@]}-1]}
            BACKUP_TYPE="archive"
        fi
        log "INFO" "非交互模式，自动选择最新的备份: $SELECTED_BACKUP"
    fi
    
    return 0
}

# 准备恢复环境
prepare_restore_environment() {
    log "INFO" "准备恢复环境..."
    
    # 创建临时恢复目录
    if [ -d "$RESTORE_DIR" ]; then
        log "INFO" "清理旧的恢复目录: $RESTORE_DIR"
        rm -rf "$RESTORE_DIR"
    fi
    
    mkdir -p "$RESTORE_DIR"
    log "INFO" "创建临时恢复目录: $RESTORE_DIR"
    
    # 如果是压缩文件，需要先解压
    if [ "$BACKUP_TYPE" == "archive" ]; then
        log "INFO" "解压备份文件: $SELECTED_BACKUP"
        
        # 确定压缩格式
        if [[ "$SELECTED_BACKUP" == *.tar.gz ]]; then
            extract_cmd="tar -xzf"
        elif [[ "$SELECTED_BACKUP" == *.tar.bz2 ]]; then
            extract_cmd="tar -xjf"
        elif [[ "$SELECTED_BACKUP" == *.tar.xz ]]; then
            extract_cmd="tar -xJf"
        else
            log "ERROR" "不支持的压缩格式: $SELECTED_BACKUP"
            return 1
        fi
        
        # 解压备份文件
        if exec_with_retry "$extract_cmd \"$SELECTED_BACKUP\" -C \"$RESTORE_DIR\" >> \"$LOG_FILE\" 2>&1" "解压备份文件"; then
            log "INFO" "备份文件解压成功"
            
            # 查找解压后的备份目录
            local extracted_dir=$(find "$RESTORE_DIR" -maxdepth 1 -type d -name "????-??-??" | head -1)
            
            if [ -n "$extracted_dir" ]; then
                BACKUP_DIR="$extracted_dir"
                log "INFO" "找到解压后的备份目录: $BACKUP_DIR"
            else
                log "ERROR" "无法找到解压后的备份目录"
                return 1
            fi
        else
            log "ERROR" "备份文件解压失败"
            return 1
        fi
    else
        # 直接使用备份目录
        BACKUP_DIR="$SELECTED_BACKUP"
    fi
    
    # 验证备份目录结构
    if [ ! -d "$BACKUP_DIR" ]; then
        log "ERROR" "备份目录不存在: $BACKUP_DIR"
        return 1
    fi
    
    # 检查备份摘要文件
    if [ -f "$BACKUP_DIR/backup-summary.txt" ]; then
        log "INFO" "找到备份摘要文件"
        cat "$BACKUP_DIR/backup-summary.txt" >> "$LOG_FILE"
    else
        log "WARN" "未找到备份摘要文件，无法获取详细信息"
    fi
    
    return 0
}

# 选择恢复选项
select_restore_options() {
    log "INFO" "选择恢复选项..."
    
    # 检查备份中包含哪些内容
    local has_system_config=false
    local has_user_config=false
    local has_custom_paths=false
    local has_packages=false
    
    [ -d "$BACKUP_DIR/etc" ] && has_system_config=true
    [ -d "$BACKUP_DIR/home" ] && has_user_config=true
    [ -d "$BACKUP_DIR/custom" ] && has_custom_paths=true
    [ -d "$BACKUP_DIR/packages" ] && has_packages=true
    
    # 如果是交互模式，让用户选择要恢复的内容
    if [ "$INTERACTIVE_MODE" == "true" ]; then
        echo -e "\n请选择要恢复的内容:"
        
        if [ "$has_system_config" == "true" ]; then
            read -p "恢复系统配置 (/etc)? [y/N] " choice
            [ "${choice,,}" == "y" ] && RESTORE_SYSTEM_CONFIG=true
        else
            echo "备份中不包含系统配置"
        fi
        
        if [ "$has_user_config" == "true" ]; then
            read -p "恢复用户配置 (~/.*) [y/N] " choice
            [ "${choice,,}" == "y" ] && RESTORE_USER_CONFIG=true
        else
            echo "备份中不包含用户配置"
        fi
        
        if [ "$has_custom_paths" == "true" ]; then
            read -p "恢复自定义路径? [y/N] " choice
            [ "${choice,,}" == "y" ] && RESTORE_CUSTOM_PATHS=true
        else
            echo "备份中不包含自定义路径"
        fi
        
        if [ "$has_packages" == "true" ]; then
            read -p "恢复软件包列表? [y/N] " choice
            [ "${choice,,}" == "y" ] && RESTORE_PACKAGES=true
        else
            echo "备份中不包含软件包列表"
        fi
        
        read -p "是否强制恢复 (覆盖现有文件)? [y/N] " choice
        [ "${choice,,}" == "y" ] && FORCE_RESTORE=true
        
        read -p "是否验证恢复结果? [Y/n] " choice
        [ "${choice,,}" == "n" ] && VERIFY_RESTORE=false
    else
        # 非交互模式，根据命令行参数或配置文件设置恢复选项
        # 如果没有指定，默认恢复所有可用内容
        [ "$has_system_config" == "true" ] && RESTORE_SYSTEM_CONFIG=true
        [ "$has_user_config" == "true" ] && RESTORE_USER_CONFIG=true
        [ "$has_custom_paths" == "true" ] && RESTORE_CUSTOM_PATHS=true
        [ "$has_packages" == "true" ] && RESTORE_PACKAGES=true
    fi
    
    # 显示选择的恢复选项
    log "INFO" "恢复选项:"
    log "INFO" "- 系统配置: $([ "$RESTORE_SYSTEM_CONFIG" == "true" ] && echo "是" || echo "否")"
    log "INFO" "- 用户配置: $([ "$RESTORE_USER_CONFIG" == "true" ] && echo "是" || echo "否")"
    log "INFO" "- 自定义路径: $([ "$RESTORE_CUSTOM_PATHS" == "true" ] && echo "是" || echo "否")"
    log "INFO" "- 软件包列表: $([ "$RESTORE_PACKAGES" == "true" ] && echo "是" || echo "否")"
    log "INFO" "- 强制恢复: $([ "$FORCE_RESTORE" == "true" ] && echo "是" || echo "否")"
    log "INFO" "- 验证恢复: $([ "$VERIFY_RESTORE" == "true" ] && echo "是" || echo "否")"
    
    # 确认是否继续
    if [ "$INTERACTIVE_MODE" == "true" ]; then
        read -p "确认以上选项并开始恢复? [y/N] " choice
        if [ "${choice,,}" != "y" ]; then
            log "INFO" "用户取消恢复操作"
            return 1
        fi
    fi
    
    return 0
}

# 恢复系统配置
restore_system_config() {
    if [ "$RESTORE_SYSTEM_CONFIG" != "true" ]; then
        log "INFO" "跳过系统配置恢复"
        return 0
    fi
    
    log "INFO" "开始恢复系统配置..."
    
    # 检查备份中是否包含系统配置
    if [ ! -d "$BACKUP_DIR/etc" ]; then
        log "ERROR" "备份中不包含系统配置"
        return 1
    fi
    
    # 检查是否有root权限
    if [ "$(id -u)" != "0" ]; then
        log "ERROR" "恢复系统配置需要root权限，请使用sudo运行此脚本"
        return 1
    fi
    
    # 询问用户是否要选择性恢复
    local selective_restore=false
    local selected_configs=()
    
    if [ "$INTERACTIVE_MODE" == "true" ]; then
        read -p "是否要选择性恢复系统配置 (而不是恢复全部)? [y/N] " choice
        if [ "${choice,,}" == "y" ]; then
            selective_restore=true
            
            # 列出重要的系统配置文件供选择
            echo -e "\n重要的系统配置文件:"
            local important_configs=("fstab" "passwd" "group" "shadow" "hosts" "hostname" "locale.conf" "mkinitcpio.conf" "pacman.conf")
            
            for i in "${!important_configs[@]}"; do
                local config=${important_configs[$i]}
                if [ -f "$BACKUP_DIR/etc/$config" ]; then
                    echo "$((i+1)). $config"
                fi
            done
            
            echo -e "\n请输入要恢复的配置文件编号 (用空格分隔，输入 'all' 恢复所有列出的文件):"
            read -p "> " config_choices
            
            if [ "$config_choices" == "all" ]; then
                for config in "${important_configs[@]}"; do
                    if [ -f "$BACKUP_DIR/etc/$config" ]; then
                        selected_configs+=("$config")
                    fi
                done
            else
                for choice in $config_choices; do
                    if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#important_configs[@]} ]; then
                        selected_configs+=("${important_configs[$((choice-1))]}")
                    fi
                done
            fi
            
            # 允许用户输入其他配置文件
            echo -e "\n请输入其他要恢复的配置文件或目录 (相对于 /etc，用空格分隔，直接回车跳过):"
            read -p "> " other_configs
            
            for config in $other_configs; do
                if [ -e "$BACKUP_DIR/etc/$config" ]; then
                    selected_configs+=("$config")
                else
                    log "WARN" "备份中不存在配置: $config"
                fi
            done
        fi
    fi
    
    # 构建rsync参数
    local rsync_opts="-aAX"
    [ "$FORCE_RESTORE" == "true" ] && rsync_opts="$rsync_opts --delete"
    
    # 执行恢复
    local success_count=0
    local fail_count=0
    
    if [ "$selective_restore" == "true" ] && [ ${#selected_configs[@]} -gt 0 ]; then
        log "INFO" "选择性恢复系统配置..."
        
        for config in "${selected_configs[@]}"; do
            log "INFO" "恢复系统配置: $config"
            
            # 创建目标目录
            mkdir -p "/etc/$(dirname "$config")"
            
            # 使用rsync恢复配置
            if exec_with_retry "rsync $rsync_opts \"$BACKUP_DIR/etc/$config\" \"/etc/$(dirname "$config")/\" >> \"$LOG_FILE\" 2>&1" "恢复系统配置: $config"; then
                log "INFO" "系统配置恢复成功: $config"
                success_count=$((success_count + 1))
                
                # 验证恢复
                if [ "$VERIFY_RESTORE" == "true" ]; then
                    if diff -r "$BACKUP_DIR/etc/$config" "/etc/$config" >> "$LOG_FILE" 2>&1; then
                        log "INFO" "系统配置验证成功: $config"
                    else
                        log "WARN" "系统配置验证失败: $config，文件可能已被修改"
                    fi
                fi
            else
                log "ERROR" "系统配置恢复失败: $config"
                fail_count=$((fail_count + 1))
            fi
        done
    else
        log "INFO" "恢复所有系统配置..."
        
        # 使用rsync恢复整个etc目录
        if exec_with_retry "rsync $rsync_opts \"$BACKUP_DIR/etc/\" \"/etc/\" >> \"$LOG_FILE\" 2>&1" "恢复所有系统配置"; then
            log "INFO" "所有系统配置恢复成功"
            success_count=1
            
            # 验证恢复
            if [ "$VERIFY_RESTORE" == "true" ]; then
                # 选择几个关键文件进行验证
                local key_files=("passwd" "group" "hosts" "fstab")
                local verify_success=true
                
                for file in "${key_files[@]}"; do
                    if [ -f "$BACKUP_DIR/etc/$file" ] && [ -f "/etc/$file" ]; then
                        if ! diff "$BACKUP_DIR/etc/$file" "/etc/$file" >> "$LOG_FILE" 2>&1; then
                            log "WARN" "系统配置验证失败: $file，文件可能已被修改"
                            verify_success=false
                        fi
                    fi
                done
                
                if [ "$verify_success" == "true" ]; then
                    log "INFO" "系统配置验证成功"
                fi
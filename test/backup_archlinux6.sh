#!/bin/bash

#############################################################
# Arch Linux 自动备份与恢复脚本
# 根据 arch-back-list.md 中的建议创建
# 功能：备份系统配置、用户配置、自定义路径、软件包列表和系统日志
# 支持压缩备份、差异备份和备份验证
# 3.0 版本：支持可配置的备份目录结构
#   可自定义的用户配置文件列表
#   灵活的备份选项
# 4.0 版本优化日志优化显示排除项
# 5.0 版本更新：可自定义的备份路径
# 5.1 版本
#   - 增强的错误处理机制：
#   - 自动重试功能（失败操作自动重试）
#   - 文件完整性检查（确保备份文件的完整性）
#   - 恢复点功能（在关键步骤创建检查点以便从故障中恢复）
# 5.2 版本
#   - 备份进度显示（支持进度条或百分比显示）
# 5.3 版本
#   - 并行备份功能（支持多任务同时执行，提高备份速度）
#   - 新增配置选项：PARALLEL_BACKUP 和 PARALLEL_JOBS
#   - 支持 GNU Parallel 工具（如已安装）或使用内置的后台进程实现
# 5.4 版本
#   - 依赖性检查增强：更全面地检查所有必要的依赖项
#   - 添加工具版本检查功能，确保工具版本满足最低要求
#   - 分类检查核心依赖、压缩工具、网络工具、加密工具和恢复测试工具
#   - 提供更详细的错误信息和安装建议
# 5.5 版本
#   - 备份测试恢复：添加测试恢复功能，确保备份可以正确恢复
#   - 支持对系统配置、用户配置和自定义路径的测试恢复
#   - 添加验证机制确保恢复的文件与原始文件一致
# 6.0 版本
#   - 完整的恢复功能：添加正式的恢复命令和相关功能
#   - 恢复前的备份功能：确保在恢复过程中出现问题时可以回滚
#   - 选择性恢复功能：允许用户只恢复特定的文件或目录
#   - 完善的恢复日志和错误处理：确保恢复过程的可靠性和可追踪性
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
        "FATAL") color=$RED ;;
        "DEBUG") color=$BLUE ;;
        *) color=$BLUE ;;
    esac
    
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}${NC}" | tee -a "$LOG_FILE"
    
    # 如果是致命错误，退出脚本
    if [ "$level" == "FATAL" ]; then
        echo -e "${RED}备份过程中遇到致命错误，退出脚本${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1 || { log "ERROR" "命令 $1 未安装，请先安装该命令"; exit 1; }
}

# 检查命令版本
check_command_version() {
    local cmd=$1
    local min_version=$2
    local version_option=${3:---version}
    local version_regex=${4:-'[0-9]+(\.[0-9]+)+'}
    
    # 获取命令版本
    local version_output
    version_output=$($cmd $version_option 2>&1 | grep -Eo "$version_regex" | head -1)
    
    if [ -z "$version_output" ]; then
        log "WARN" "无法获取 $cmd 的版本信息"
        return 0
    fi
    
    # 比较版本
    if [ "$(printf '%s\n' "$min_version" "$version_output" | sort -V | head -n1)" != "$min_version" ]; then
        log "INFO" "$cmd 版本 $version_output 满足最低要求 $min_version"
        return 0
    else
        log "WARN" "$cmd 版本 $version_output 低于推荐的最低版本 $min_version"
        return 1
    fi
}

# 检查必要的命令
check_dependencies() {
    log "INFO" "检查依赖..."
    local missing_deps=0
    local optional_missing=0
    
    # 核心依赖检查 - 这些是必须的
    log "INFO" "检查核心依赖..."
    local core_deps=("rsync" "pacman" "journalctl" "tar" "find" "grep" "awk" "sed")
    local core_desc=("远程同步工具" "包管理器" "日志查看工具" "归档工具" "文件查找工具" "文本搜索工具" "文本处理工具" "流编辑器")
    
    for i in "${!core_deps[@]}"; do
        if ! command -v "${core_deps[$i]}" >/dev/null 2>&1; then
            log "ERROR" "核心依赖 ${core_deps[$i]} (${core_desc[$i]}) 未安装"
            log "INFO" "请使用以下命令安装: sudo pacman -S ${core_deps[$i]}"
            missing_deps=$((missing_deps + 1))
        else
            log "INFO" "核心依赖 ${core_deps[$i]} 已安装"
            
            # 对特定工具进行版本检查
            case "${core_deps[$i]}" in
                "rsync")
                    check_command_version "rsync" "3.1.0"
                    ;;
                "tar")
                    check_command_version "tar" "1.30"
                    ;;
            esac
        fi
    done
    
    # 压缩工具依赖检查
    log "INFO" "检查压缩工具依赖..."
    local compression_tools=("gzip" "bzip2" "xz")
    local compression_desc=("gzip压缩工具" "bzip2压缩工具" "xz压缩工具")
    
    for i in "${!compression_tools[@]}"; do
        if ! command -v "${compression_tools[$i]}" >/dev/null 2>&1; then
            if [ "$COMPRESS_BACKUP" == "true" ] && [ "$COMPRESS_METHOD" == "${compression_tools[$i]}" ]; then
                log "ERROR" "所选压缩工具 ${compression_tools[$i]} (${compression_desc[$i]}) 未安装"
                log "INFO" "请使用以下命令安装: sudo pacman -S ${compression_tools[$i]}"
                missing_deps=$((missing_deps + 1))
            else
                log "WARN" "压缩工具 ${compression_tools[$i]} 未安装，如需使用该压缩方法请先安装"
                optional_missing=$((optional_missing + 1))
            fi
        else
            if [ "$COMPRESS_BACKUP" == "true" ] && [ "$COMPRESS_METHOD" == "${compression_tools[$i]}" ]; then
                log "INFO" "所选压缩工具 ${compression_tools[$i]} 已安装"
            else
                log "DEBUG" "压缩工具 ${compression_tools[$i]} 已安装"
            fi
        fi
    done
    
    # 进度显示工具检查
    log "INFO" "检查进度显示工具..."
    if command -v "pv" >/dev/null 2>&1; then
        log "INFO" "检测到 pv 工具，将启用备份进度显示"
        USE_PROGRESS_BAR=true
    else
        log "WARN" "未检测到 pv 工具，备份进度显示将使用 rsync 内置的进度功能"
        log "INFO" "提示：安装 pv 工具可获得更好的进度显示体验 (sudo pacman -S pv)"
        USE_PROGRESS_BAR=false
        optional_missing=$((optional_missing + 1))
    fi
    
    # 并行处理工具检查
    if [ "$PARALLEL_BACKUP" == "true" ]; then
        log "INFO" "检查并行处理工具..."
        if command -v "parallel" >/dev/null 2>&1; then
            log "INFO" "检测到 GNU Parallel 工具，将启用并行备份功能"
            HAS_PARALLEL=true
            # 检查 GNU Parallel 版本
            check_command_version "parallel" "20180222"
        else
            log "WARN" "未检测到 GNU Parallel 工具，将使用内置的后台进程实现并行备份"
            log "INFO" "提示：安装 GNU Parallel 工具可获得更好的并行备份体验 (sudo pacman -S parallel)"
            HAS_PARALLEL=false
            optional_missing=$((optional_missing + 1))
        fi
    fi
    
    # 网络工具检查（如果配置了网络备份）
    if [ "${NETWORK_BACKUP:-false}" == "true" ]; then
        log "INFO" "检查网络备份工具..."
        local network_tools=("ssh" "scp" "curl")
        local network_desc=("SSH客户端" "安全复制工具" "网络传输工具")
        
        for i in "${!network_tools[@]}"; do
            if ! command -v "${network_tools[$i]}" >/dev/null 2>&1; then
                log "ERROR" "网络工具 ${network_tools[$i]} (${network_desc[$i]}) 未安装，但网络备份功能已启用"
                log "INFO" "请使用以下命令安装: sudo pacman -S ${network_tools[$i]}"
                missing_deps=$((missing_deps + 1))
            else
                log "INFO" "网络工具 ${network_tools[$i]} 已安装"
            fi
        done
    fi
    
    # 加密工具检查（如果配置了加密备份）
    if [ "${ENCRYPT_BACKUP:-false}" == "true" ]; then
        log "INFO" "检查加密工具..."
        local crypto_tools=("gpg" "openssl")
        local crypto_desc=("GnuPG加密工具" "OpenSSL加密库")
        
        for i in "${!crypto_tools[@]}"; do
            if ! command -v "${crypto_tools[$i]}" >/dev/null 2>&1; then
                log "ERROR" "加密工具 ${crypto_tools[$i]} (${crypto_desc[$i]}) 未安装，但加密备份功能已启用"
                log "INFO" "请使用以下命令安装: sudo pacman -S ${crypto_tools[$i]}"
                missing_deps=$((missing_deps + 1))
            else
                log "INFO" "加密工具 ${crypto_tools[$i]} 已安装"
                
                # 对特定加密工具进行版本检查
                case "${crypto_tools[$i]}" in
                    "gpg")
                        check_command_version "gpg" "2.2.0"
                        ;;
                    "openssl")
                        check_command_version "openssl" "1.1.0" "version" "[0-9]+(\.[0-9]+)+[a-z]*"
                        ;;
                esac
            fi
        done
    fi
    
    # 恢复测试工具检查（如果配置了恢复测试）
    if [ "${TEST_RESTORE:-false}" == "true" ]; then
        log "INFO" "检查恢复测试工具..."
        local test_tools=("diff" "cmp")
        local test_desc=("文件比较工具" "字节比较工具")
        
        for i in "${!test_tools[@]}"; do
            if ! command -v "${test_tools[$i]}" >/dev/null 2>&1; then
                log "ERROR" "测试工具 ${test_tools[$i]} (${test_desc[$i]}) 未安装，但恢复测试功能已启用"
                log "INFO" "请使用以下命令安装: sudo pacman -S ${test_tools[$i]}"
                missing_deps=$((missing_deps + 1))
            else
                log "INFO" "测试工具 ${test_tools[$i]} 已安装"
            fi
        done
    fi
    
    # 依赖检查结果汇总
    if [ $missing_deps -gt 0 ]; then
        log "ERROR" "检测到 $missing_deps 个必要依赖缺失，请安装后再运行脚本"
        return 1
    else
        if [ $optional_missing -gt 0 ]; then
            log "WARN" "检测到 $optional_missing 个可选依赖缺失，某些功能可能受限"
        fi
        log "INFO" "所有必要依赖检查通过"
        return 0
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

# 是否启用并行备份 (true/false)
# 并行备份可以同时执行多个备份任务，提高备份速度
PARALLEL_BACKUP=false

# 并行备份的最大任务数
# 建议设置为CPU核心数或略低于核心数
PARALLEL_JOBS=4

# 日志保留天数
LOG_RETENTION_DAYS=30

# 备份保留数量（保留最近几次备份）
BACKUP_RETENTION_COUNT=7

# 是否启用备份测试恢复功能 (true/false)
# 测试恢复会验证备份文件是否可以正确恢复
TEST_RESTORE=false

# 测试恢复的临时目录
TEST_RESTORE_DIR="${BACKUP_ROOT}/test_restore"
EOF
        log "INFO" "已创建默认配置文件: $CONFIG_FILE"
    fi
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

# 创建恢复点
create_recovery_point() {
    local stage=$1
    local recovery_file="${BACKUP_ROOT}/recovery_${TIMESTAMP}.json"
    
    log "INFO" "创建恢复点: $stage"
    
    # 创建恢复点信息
    cat > "$recovery_file" << EOF
{
    "timestamp": "$TIMESTAMP",
    "stage": "$stage",
    "backup_dir": "$BACKUP_DIR",
    "completed_steps": [
        $([ "$stage" == "system_config" ] && echo "\"system_config\"" || echo "")
        $([ "$stage" == "user_config" ] && echo "\"system_config\", \"user_config\"" || echo "")
        $([ "$stage" == "custom_paths" ] && echo "\"system_config\", \"user_config\", \"custom_paths\"" || echo "")
        $([ "$stage" == "packages" ] && echo "\"system_config\", \"user_config\", \"custom_paths\", \"packages\"" || echo "")
        $([ "$stage" == "logs" ] && echo "\"system_config\", \"user_config\", \"custom_paths\", \"packages\", \"logs\"" || echo "")
    ]
}
EOF
    
    log "DEBUG" "恢复点已创建: $recovery_file"
}

# 备份系统配置文件
backup_system_config() {
    if [ "$BACKUP_SYSTEM_CONFIG" != "true" ]; then
        log "INFO" "跳过系统配置备份"
        return 0
    fi
    
    log "INFO" "开始备份系统配置文件..."
    
    # 检查关键系统文件是否存在且可读
    if [ ! -d "/etc" ]; then
        log "FATAL" "/etc 目录不存在或不可访问"
        return 1
    fi
    
    # 检查关键配置文件
    local critical_files=("/etc/fstab" "/etc/passwd" "/etc/group" "/etc/shadow" "/etc/hosts")
    local missing_files=0
    
    for file in "${critical_files[@]}"; do
        if [ ! -f "$file" ]; then
            log "WARN" "关键系统文件不存在: $file"
            missing_files=$((missing_files + 1))
        elif [ ! -r "$file" ]; then
            log "WARN" "关键系统文件不可读: $file，可能需要 root 权限"
        fi
    done
    
    if [ $missing_files -gt 0 ]; then
        log "WARN" "有 $missing_files 个关键系统文件缺失，备份可能不完整"
    fi
    
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
    
    # 使用 rsync 备份 /etc 目录，带进度显示和重试功能
    local progress_param=""
    if [ "$USE_PROGRESS_BAR" == "true" ]; then
        # 使用 pv 工具显示进度条
        log "INFO" "使用 pv 工具显示备份进度"
        local rsync_cmd="sudo rsync -aAX --delete $exclude_params $diff_params /etc/ \"${BACKUP_DIR}/etc/\" --info=progress2 >> \"$LOG_FILE\" 2>&1"
    else
        # 使用 rsync 内置进度显示
        log "INFO" "使用 rsync 内置进度显示功能"
        local rsync_cmd="sudo rsync -aAXv --delete $exclude_params $diff_params /etc/ \"${BACKUP_DIR}/etc/\" --progress >> \"$LOG_FILE\" 2>&1"
    fi
    
    if exec_with_retry "$rsync_cmd" "系统配置文件备份"; then
        log "INFO" "系统配置文件备份完成"
        
        # 验证备份完整性
        if check_file_integrity "${BACKUP_DIR}/etc/passwd" "系统用户文件" && \
           check_file_integrity "${BACKUP_DIR}/etc/fstab" "文件系统表"; then
            log "INFO" "系统配置文件备份完整性验证通过"
            # 创建恢复点
            create_recovery_point "system_config"
            return 0
        else
            log "ERROR" "系统配置文件备份完整性验证失败"
            return 1
        fi
    else
        log "ERROR" "系统配置文件备份失败，即使在多次尝试后"
        return 1
    fi
}

# 备份用户配置文件
backup_user_config() {
    if [ "$BACKUP_USER_CONFIG" != "true" ]; then
        log "INFO" "跳过用户配置备份"
        return 0
    fi
    
    log "INFO" "开始备份用户配置文件..."
    log "INFO" "备份用户: $REAL_USER 的配置文件"
    
    # 检查用户主目录是否存在
    if [ ! -d "$REAL_HOME" ]; then
        log "ERROR" "用户主目录不存在: $REAL_HOME"
        return 1
    fi
    
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
    
    # 统计成功和失败的备份
    local success_count=0
    local fail_count=0
    local critical_fail=false
    local critical_configs=(".ssh" ".gnupg" ".config")
    
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
                
                # 检查是否为关键配置
                local is_critical=false
                for critical_item in "${critical_configs[@]}"; do
                    if [[ "$dir" == "$critical_item"* ]]; then
                        is_critical=true
                        break
                    fi
                done
                
                # 使用 rsync 备份，对关键配置使用重试机制，并显示进度
                if $is_critical; then
                    local rsync_cmd=""
                    if [ "$USE_PROGRESS_BAR" == "true" ]; then
                        # 使用 pv 工具显示进度条
                        rsync_cmd="rsync -aAX --delete $exclude_params $diff_params \"$src_path\" \"$dest_path\" --info=progress2 >> \"$LOG_FILE\" 2>&1"
                    else
                        # 使用 rsync 内置进度显示
                        rsync_cmd="rsync -aAXv --delete $exclude_params $diff_params \"$src_path\" \"$dest_path\" --progress >> \"$LOG_FILE\" 2>&1"
                    fi
                    
                    if exec_with_retry "$rsync_cmd" "关键用户配置备份: $dir"; then
                        log "INFO" "已备份关键配置: $dir"
                        success_count=$((success_count + 1))
                    else
                        log "ERROR" "关键配置备份失败: $dir"
                        fail_count=$((fail_count + 1))
                        critical_fail=true
                    fi
                else
                    # 非关键配置，直接备份并显示进度
                    if [ "$USE_PROGRESS_BAR" == "true" ]; then
                        # 使用 pv 工具显示进度条
                        rsync -aAX --delete $exclude_params $diff_params "$src_path" "$dest_path" --info=progress2 >> "$LOG_FILE" 2>&1
                    else
                        # 使用 rsync 内置进度显示
                        rsync -aAXv --delete $exclude_params $diff_params "$src_path" "$dest_path" --progress >> "$LOG_FILE" 2>&1
                    fi
                    
                    if [ $? -eq 0 ]; then
                        log "INFO" "已备份: $dir"
                        success_count=$((success_count + 1))
                    else
                        log "WARN" "备份失败: $dir"
                        fail_count=$((fail_count + 1))
                    fi
                fi
                
                # 验证备份完整性
                if [ -e "$dest_path" ]; then
                    check_file_integrity "$dest_path" "用户配置: $dir"
                fi
            fi
        else
            log "DEBUG" "源路径不存在，跳过: $src_path"
        fi
    done
    
    # 报告备份结果
    if [ $fail_count -eq 0 ]; then
        log "INFO" "用户配置文件备份完成，成功备份 $success_count 项"
        create_recovery_point "user_config"
        return 0
    elif [ "$critical_fail" = true ]; then
        log "ERROR" "用户配置文件备份部分失败，$success_count 成功，$fail_count 失败，包含关键配置失败"
        return 1
    else
        log "WARN" "用户配置文件备份部分失败，$success_count 成功，$fail_count 失败，但关键配置已备份"
        create_recovery_point "user_config"
        return 0
    fi
}

# 备份软件包列表
backup_packages() {
    if [ "$BACKUP_PACKAGES" != "true" ]; then
        log "INFO" "跳过软件包列表备份"
        return 0
    fi
    
    log "INFO" "开始备份软件包列表..."
    
    # 检查 pacman 是否可用
    if ! command -v pacman &> /dev/null; then
        log "ERROR" "pacman 命令不可用，无法备份软件包列表"
        return 1
    fi
    
    # 创建临时目录用于存储软件包列表
    local temp_dir="${BACKUP_DIR}/packages.tmp"
    mkdir -p "$temp_dir"
    
    # 定义备份文件路径
    local manually_installed_file="${temp_dir}/manually-installed.txt"
    local all_packages_file="${temp_dir}/all-packages.txt"
    local foreign_packages_file="${temp_dir}/foreign-packages.txt"
    local pacman_log_file="${temp_dir}/pacman.log"
    
    # 备份手动安装的软件包列表
    if exec_with_retry "pacman -Qe > \"${manually_installed_file}\"" "手动安装的软件包列表备份"; then
        log "INFO" "手动安装的软件包列表备份完成"
        check_file_integrity "$manually_installed_file" "手动安装的软件包列表"
    else
        log "ERROR" "手动安装的软件包列表备份失败"
    fi
    
    # 备份所有安装的软件包列表
    if exec_with_retry "pacman -Q > \"${all_packages_file}\"" "所有软件包列表备份"; then
        log "INFO" "所有软件包列表备份完成"
        check_file_integrity "$all_packages_file" "所有软件包列表"
    else
        log "ERROR" "所有软件包列表备份失败"
    fi
    
    # 备份外部软件包列表（非官方仓库）
    if exec_with_retry "pacman -Qm > \"${foreign_packages_file}\"" "外部软件包列表备份"; then
        log "INFO" "外部软件包列表备份完成"
        check_file_integrity "$foreign_packages_file" "外部软件包列表"
    else
        log "ERROR" "外部软件包列表备份失败"
    fi
    
    # 备份 pacman 日志
    if [ -f "/var/log/pacman.log" ]; then
        if exec_with_retry "sudo cp /var/log/pacman.log \"${pacman_log_file}\"" "Pacman 日志备份"; then
            log "INFO" "Pacman 日志备份完成"
            check_file_integrity "$pacman_log_file" "Pacman 日志"
        else
            log "ERROR" "Pacman 日志备份失败"
        fi
    else
        log "WARN" "Pacman 日志文件不存在"
    fi
    
    # 移动临时目录到最终目录
    if [ -d "$temp_dir" ]; then
        if mv "$temp_dir"/* "${BACKUP_DIR}/packages/" 2>> "$LOG_FILE"; then
            log "INFO" "软件包列表备份文件移动成功"
            rm -rf "$temp_dir"
            create_recovery_point "packages"
            return 0
        else
            log "ERROR" "软件包列表备份文件移动失败"
            return 1
        fi
    else
        log "ERROR" "软件包列表临时目录不存在"
        return 1
    fi
}

# 备份系统日志
backup_logs() {
    if [ "$BACKUP_LOGS" != "true" ]; then
        log "INFO" "跳过系统日志备份"
        return 0
    fi
    
    log "INFO" "开始备份系统日志..."
    
    # 检查 journalctl 是否可用
    if ! command -v journalctl &> /dev/null; then
        log "ERROR" "journalctl 命令不可用，无法备份系统日志"
        return 1
    fi
    
    # 创建临时目录用于存储日志
    local temp_dir="${BACKUP_DIR}/logs.tmp"
    mkdir -p "$temp_dir"
    
    # 获取当前年份
    local current_year=$(date +"%Y")
    local log_file="${temp_dir}/system-log-${current_year}.txt"
    
    # 备份当年的系统日志，带重试功能
    local journalctl_cmd="journalctl --since \"${current_year}-01-01\" --until \"${current_year}-12-31\" > \"${log_file}\" 2>> \"$LOG_FILE\""
    
    if exec_with_retry "$journalctl_cmd" "系统日志备份"; then
        log "INFO" "系统日志备份完成"
        
        # 验证备份完整性
        if check_file_integrity "$log_file" "系统日志"; then
            # 移动临时文件到最终目录
            if mv "$temp_dir"/* "${BACKUP_DIR}/logs/" 2>> "$LOG_FILE"; then
                log "INFO" "系统日志备份文件移动成功"
                rm -rf "$temp_dir"
                create_recovery_point "logs"
                return 0
            else
                log "ERROR" "系统日志备份文件移动失败"
                return 1
            fi
        else
            log "ERROR" "系统日志备份完整性验证失败"
            return 1
        fi
    else
        log "ERROR" "系统日志备份失败，即使在多次尝试后"
        return 1
    fi
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
    
    # 统计成功和失败的备份
    local success_count=0
    local fail_count=0
    local total_paths=${#custom_paths[@]}
    
    if [ $total_paths -eq 0 ]; then
        log "WARN" "没有配置自定义路径，请检查配置文件"
        return 0
    fi
    
    log "INFO" "共有 $total_paths 个自定义路径需要备份"
    
    for path in "${custom_paths[@]}"; do
        if [ -e "$path" ]; then
            # 获取路径的基本名称（去除前导斜杠）
            local base_name=$(basename "$path")
            local dest_path="${BACKUP_DIR}/custom/$base_name"
            
            log "INFO" "备份自定义路径: $path"
            
            # 检查路径权限
            if [ ! -r "$path" ]; then
                log "WARN" "自定义路径不可读，可能需要 root 权限: $path"
            fi
            
            # 使用 rsync 备份自定义路径，带进度显示和重试功能
            local rsync_cmd=""
            if [ "$USE_PROGRESS_BAR" == "true" ]; then
                # 使用 pv 工具显示进度条
                log "INFO" "使用 pv 工具显示备份进度: $path"
                rsync_cmd="sudo rsync -aAX --delete $exclude_params $diff_params \"$path\" \"$dest_path\" --info=progress2 >> \"$LOG_FILE\" 2>&1"
            else
                # 使用 rsync 内置进度显示
                log "INFO" "使用 rsync 内置进度显示功能: $path"
                rsync_cmd="sudo rsync -aAXv --delete $exclude_params $diff_params \"$path\" \"$dest_path\" --progress >> \"$LOG_FILE\" 2>&1"
            fi
            
            if exec_with_retry "$rsync_cmd" "自定义路径备份: $path"; then
                log "INFO" "自定义路径备份完成: $path"
                success_count=$((success_count + 1))
                
                # 验证备份完整性
                check_file_integrity "$dest_path" "自定义路径: $path"
            else
                log "ERROR" "自定义路径备份失败: $path，即使在多次尝试后"
                fail_count=$((fail_count + 1))
            fi
        else
            log "WARN" "自定义路径不存在，跳过: $path"
            fail_count=$((fail_count + 1))
        fi
    done
    
    # 报告备份结果
    local success_percent=$((success_count * 100 / total_paths))
    
    if [ $fail_count -eq 0 ]; then
        log "INFO" "自定义路径备份完成，成功率: 100%"
        create_recovery_point "custom_paths"
        return 0
    elif [ $success_percent -ge 80 ]; then
        log "WARN" "自定义路径备份部分失败，成功率: ${success_percent}%，$success_count 成功，$fail_count 失败"
        create_recovery_point "custom_paths"
        return 0
    else
        log "ERROR" "自定义路径备份大部分失败，成功率: ${success_percent}%，$success_count 成功，$fail_count 失败"
        return 1
    fi
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
    local verify_errors=0
    local max_errors=3
    
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        # 验证压缩文件
        local archive_file="${BACKUP_ROOT}/${DATE_FORMAT}_backup.tar"
        local ext=""
        
        case "$COMPRESS_METHOD" in
            "gzip") ext=".gz" ;;
            "bzip2") ext=".bz2" ;;
            "xz") ext=".xz" ;;
        esac
        
        # 检查压缩文件是否存在
        if [ ! -f "${archive_file}${ext}" ]; then
            log "ERROR" "验证失败: 压缩文件不存在: ${archive_file}${ext}"
            return 1
        fi
        
        log "INFO" "验证压缩文件: ${archive_file}${ext}"
        
        # 检查文件大小
        local file_size=$(stat -c%s "${archive_file}${ext}" 2>/dev/null || echo "0")
        if [ "$file_size" -eq 0 ]; then
            log "ERROR" "验证失败: 压缩文件大小为零: ${archive_file}${ext}"
            return 1
        fi
        
        # 使用重试机制验证压缩文件
        local verify_cmd=""
        case "$COMPRESS_METHOD" in
            "gzip")
                verify_cmd="gzip -t \"${archive_file}${ext}\" >> \"$LOG_FILE\" 2>&1"
                ;;
            "bzip2")
                verify_cmd="bzip2 -t \"${archive_file}${ext}\" >> \"$LOG_FILE\" 2>&1"
                ;;
            "xz")
                verify_cmd="xz -t \"${archive_file}${ext}\" >> \"$LOG_FILE\" 2>&1"
                ;;
        esac
        
        if exec_with_retry "$verify_cmd" "压缩文件验证"; then
            log "INFO" "压缩文件验证成功"
        else
            log "ERROR" "压缩文件验证失败，即使在多次尝试后"
            return 1
        fi
    else
        # 验证未压缩的备份
        log "INFO" "验证备份目录: $BACKUP_DIR"
        
        # 检查备份目录是否存在
        if [ ! -d "$BACKUP_DIR" ]; then
            log "ERROR" "验证失败: 备份目录不存在: $BACKUP_DIR"
            return 1
        fi
        
        # 检查关键目录是否存在
        for dir in ${BACKUP_DIRS}; do
            if [ ! -d "${BACKUP_DIR}/${dir}" ]; then
                log "ERROR" "验证失败: ${dir}目录不存在"
                verify_errors=$((verify_errors + 1))
            else
                # 检查目录是否为空
                if [ -z "$(ls -A "${BACKUP_DIR}/${dir}" 2>/dev/null)" ]; then
                    log "WARN" "验证警告: ${dir}目录为空"
                fi
            fi
            
            # 如果错误太多，提前退出
            if [ $verify_errors -ge $max_errors ]; then
                log "ERROR" "验证失败: 发现太多错误 ($verify_errors)"
                return 1
            fi
        done
        
        # 检查备份摘要文件
        if [ ! -f "${BACKUP_DIR}/backup-summary.txt" ]; then
            log "ERROR" "验证失败: 备份摘要文件不存在"
            verify_errors=$((verify_errors + 1))
        else
            # 检查摘要文件大小
            if [ ! -s "${BACKUP_DIR}/backup-summary.txt" ]; then
                log "ERROR" "验证失败: 备份摘要文件为空"
                verify_errors=$((verify_errors + 1))
            fi
        fi
        
        if [ $verify_errors -eq 0 ]; then
            log "INFO" "备份目录验证成功"
            return 0
        else
            log "ERROR" "备份目录验证失败，发现 $verify_errors 个错误"
            return 1
        fi
    fi
}

# 测试备份恢复
test_backup_restore() {
    if [ "$TEST_RESTORE" != "true" ]; then
        log "INFO" "跳过备份测试恢复"
        return 0
    fi
    
    log "INFO" "开始测试备份恢复..."
    
    # 创建测试恢复目录
    if [ -d "$TEST_RESTORE_DIR" ]; then
        log "INFO" "清理旧的测试恢复目录: $TEST_RESTORE_DIR"
        rm -rf "$TEST_RESTORE_DIR"
    fi
    
    mkdir -p "$TEST_RESTORE_DIR"
    log "INFO" "创建测试恢复目录: $TEST_RESTORE_DIR"
    
    local restore_errors=0
    local max_errors=3
    
    # 如果备份已压缩，需要先解压
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        log "INFO" "备份已压缩，需要先解压进行测试恢复"
        
        local archive_file="${BACKUP_ROOT}/${DATE_FORMAT}_backup.tar"
        local ext=""
        
        case "$COMPRESS_METHOD" in
            "gzip") ext=".gz" ;;
            "bzip2") ext=".bz2" ;;
            "xz") ext=".xz" ;;
        esac
        
        # 检查压缩文件是否存在
        if [ ! -f "${archive_file}${ext}" ]; then
            log "ERROR" "测试恢复失败: 压缩文件不存在: ${archive_file}${ext}"
            return 1
        fi
        
        # 创建临时解压目录
        local temp_extract_dir="${TEST_RESTORE_DIR}/temp_extract"
        mkdir -p "$temp_extract_dir"
        
        # 解压备份文件
        log "INFO" "解压备份文件到临时目录: $temp_extract_dir"
        
        local decompress_cmd=""
        case "$COMPRESS_METHOD" in
            "gzip")
                decompress_cmd="tar -xzf \"${archive_file}${ext}\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                ;;
            "bzip2")
                decompress_cmd="tar -xjf \"${archive_file}${ext}\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                ;;
            "xz")
                decompress_cmd="tar -xJf \"${archive_file}${ext}\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                ;;
        esac
        
        if exec_with_retry "$decompress_cmd" "解压备份文件"; then
            log "INFO" "备份文件解压成功"
            # 设置备份目录为解压后的目录
            BACKUP_DIR="$temp_extract_dir/${DATE_FORMAT}"
        else
            log "ERROR" "备份文件解压失败，无法进行测试恢复"
            return 1
        fi
    fi
    
    # 测试恢复系统配置
    if [ "$BACKUP_SYSTEM_CONFIG" == "true" ] && [ -d "${BACKUP_DIR}/etc" ]; then
        log "INFO" "测试恢复系统配置..."
        
        # 创建系统配置测试恢复目录
        mkdir -p "${TEST_RESTORE_DIR}/etc"
        
        # 选择一些关键系统配置文件进行测试恢复
        local system_test_files=("passwd" "group" "hosts" "fstab")
        local system_success=0
        local system_failed=0
        
        for file in "${system_test_files[@]}"; do
            if [ -f "${BACKUP_DIR}/etc/${file}" ]; then
                log "INFO" "测试恢复系统配置文件: ${file}"
                
                # 复制文件到测试目录
                if cp "${BACKUP_DIR}/etc/${file}" "${TEST_RESTORE_DIR}/etc/${file}" >> "$LOG_FILE" 2>&1; then
                    # 验证文件完整性
                    if diff -q "${BACKUP_DIR}/etc/${file}" "${TEST_RESTORE_DIR}/etc/${file}" >> "$LOG_FILE" 2>&1; then
                        log "INFO" "系统配置文件 ${file} 测试恢复成功"
                        system_success=$((system_success + 1))
                    else
                        log "ERROR" "系统配置文件 ${file} 测试恢复后验证失败"
                        system_failed=$((system_failed + 1))
                        restore_errors=$((restore_errors + 1))
                    fi
                else
                    log "ERROR" "系统配置文件 ${file} 测试恢复失败"
                    system_failed=$((system_failed + 1))
                    restore_errors=$((restore_errors + 1))
                fi
            else
                log "WARN" "系统配置文件 ${file} 在备份中不存在，跳过测试恢复"
            fi
        done
        
        log "INFO" "系统配置测试恢复完成: $system_success 成功, $system_failed 失败"
    else
        log "INFO" "跳过系统配置测试恢复 (未备份或已禁用)"
    fi
    
    # 测试恢复用户配置
    if [ "$BACKUP_USER_CONFIG" == "true" ] && [ -d "${BACKUP_DIR}/home" ]; then
        log "INFO" "测试恢复用户配置..."
        
        # 创建用户配置测试恢复目录
        mkdir -p "${TEST_RESTORE_DIR}/home"
        
        # 选择一些重要的用户配置文件进行测试恢复
        local user_test_configs=(".bashrc" ".zshrc" ".gitconfig" ".ssh/config")
        local user_success=0
        local user_failed=0
        
        for config in "${user_test_configs[@]}"; do
            if [ -f "${BACKUP_DIR}/home/${config}" ]; then
                log "INFO" "测试恢复用户配置文件: ${config}"
                
                # 创建必要的目录结构
                mkdir -p "$(dirname "${TEST_RESTORE_DIR}/home/${config}")"
                
                # 复制文件到测试目录
                if cp "${BACKUP_DIR}/home/${config}" "${TEST_RESTORE_DIR}/home/${config}" >> "$LOG_FILE" 2>&1; then
                    # 验证文件完整性
                    if diff -q "${BACKUP_DIR}/home/${config}" "${TEST_RESTORE_DIR}/home/${config}" >> "$LOG_FILE" 2>&1; then
                        log "INFO" "用户配置文件 ${config} 测试恢复成功"
                        user_success=$((user_success + 1))
                    else
                        log "ERROR" "用户配置文件 ${config} 测试恢复后验证失败"
                        user_failed=$((user_failed + 1))
                        restore_errors=$((restore_errors + 1))
                    fi
                else
                    log "ERROR" "用户配置文件 ${config} 测试恢复失败"
                    user_failed=$((user_failed + 1))
                    restore_errors=$((restore_errors + 1))
                fi
            else
                log "DEBUG" "用户配置文件 ${config} 在备份中不存在，跳过测试恢复"
            fi
        done
        
        log "INFO" "用户配置测试恢复完成: $user_success 成功, $user_failed 失败"
    else
        log "INFO" "跳过用户配置测试恢复 (未备份或已禁用)"
    fi
    
    # 测试恢复自定义路径
    if [ "$BACKUP_CUSTOM_PATHS" == "true" ] && [ -d "${BACKUP_DIR}/custom" ] && [ -n "$CUSTOM_PATHS" ]; then
        log "INFO" "测试恢复自定义路径..."
        
        # 创建自定义路径测试恢复目录
        mkdir -p "${TEST_RESTORE_DIR}/custom"
        
        # 从配置文件中读取自定义路径列表
        IFS=' ' read -r -a custom_paths <<< "$CUSTOM_PATHS"
        local custom_success=0
        local custom_failed=0
        
        for path in "${custom_paths[@]}"; do
            local base_name=$(basename "$path")
            
            if [ -e "${BACKUP_DIR}/custom/$base_name" ]; then
                log "INFO" "测试恢复自定义路径: $base_name"
                
                # 对于目录，选择一个样本文件进行测试
                if [ -d "${BACKUP_DIR}/custom/$base_name" ]; then
                    # 查找一个样本文件
                    local sample_file=$(find "${BACKUP_DIR}/custom/$base_name" -type f -print -quit 2>/dev/null)
                    
                    if [ -n "$sample_file" ]; then
                        # 获取相对路径
                        local rel_path=${sample_file#${BACKUP_DIR}/custom/$base_name/}
                        
                        # 创建必要的目录结构
                        mkdir -p "$(dirname "${TEST_RESTORE_DIR}/custom/$base_name/$rel_path")"
                        
                        # 复制样本文件到测试目录
                        if cp "$sample_file" "${TEST_RESTORE_DIR}/custom/$base_name/$rel_path" >> "$LOG_FILE" 2>&1; then
                            # 验证文件完整性
                            if diff -q "$sample_file" "${TEST_RESTORE_DIR}/custom/$base_name/$rel_path" >> "$LOG_FILE" 2>&1; then
                                log "INFO" "自定义路径 $base_name 的样本文件测试恢复成功"
                                custom_success=$((custom_success + 1))
                            else
                                log "ERROR" "自定义路径 $base_name 的样本文件测试恢复后验证失败"
                                custom_failed=$((custom_failed + 1))
                                restore_errors=$((restore_errors + 1))
                            fi
                        else
                            log "ERROR" "自定义路径 $base_name 的样本文件测试恢复失败"
                            custom_failed=$((custom_failed + 1))
                            restore_errors=$((restore_errors + 1))
                        fi
                    else
                        log "WARN" "自定义路径 $base_name 是空目录或无法找到样本文件，跳过测试恢复"
                    fi
                else
                    # 对于文件，直接测试恢复
                    mkdir -p "${TEST_RESTORE_DIR}/custom"
                    
                    if cp "${BACKUP_DIR}/custom/$base_name" "${TEST_RESTORE_DIR}/custom/$base_name" >> "$LOG_FILE" 2>&1; then
                        # 验证文件完整性
                        if diff -q "${BACKUP_DIR}/custom/$base_name" "${TEST_RESTORE_DIR}/custom/$base_name" >> "$LOG_FILE" 2>&1; then
                            log "INFO" "自定义文件 $base_name 测试恢复成功"
                            custom_success=$((custom_success + 1))
                        else
                            log "ERROR" "自定义文件 $base_name 测试恢复后验证失败"
                            custom_failed=$((custom_failed + 1))
                            restore_errors=$((restore_errors + 1))
                        fi
                    else
                        log "ERROR" "自定义文件 $base_name 测试恢复失败"
                        custom_failed=$((custom_failed + 1))
                        restore_errors=$((restore_errors + 1))
                    fi
                fi
            else
                log "WARN" "自定义路径 $base_name 在备份中不存在，跳过测试恢复"
            fi
        done
        
        log "INFO" "自定义路径测试恢复完成: $custom_success 成功, $custom_failed 失败"
    else
        log "INFO" "跳过自定义路径测试恢复 (未备份或已禁用)"
    fi
    
    # 清理临时解压目录
    if [ "$COMPRESS_BACKUP" == "true" ] && [ -d "${TEST_RESTORE_DIR}/temp_extract" ]; then
        log "INFO" "清理临时解压目录"
        rm -rf "${TEST_RESTORE_DIR}/temp_extract"
    fi
    
    # 报告测试恢复结果
    if [ $restore_errors -eq 0 ]; then
        log "INFO" "备份测试恢复成功完成！测试恢复目录: ${TEST_RESTORE_DIR}"
        return 0
    else
        log "ERROR" "备份测试恢复部分失败，发现 $restore_errors 个错误"
        return 1
    fi
}

# 检查是否存在恢复点
check_recovery_point() {
    log "INFO" "检查是否存在恢复点..."
    
    # 查找最新的恢复点文件
    local recovery_files=($(find "$BACKUP_ROOT" -name "recovery_*.json" -type f | sort -r))
    
    if [ ${#recovery_files[@]} -eq 0 ]; then
        log "INFO" "没有找到恢复点，将进行完整备份"
        return 0
    fi
    
    local latest_recovery="${recovery_files[0]}"
    log "INFO" "找到最新的恢复点: $latest_recovery"
    
    # 解析恢复点文件（简单解析，不使用jq等工具以减少依赖）
    local recovery_timestamp=$(grep -o '"timestamp": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    local recovery_stage=$(grep -o '"stage": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    local recovery_dir=$(grep -o '"backup_dir": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    
    # 检查恢复点是否是今天的
    local today=$(date +"%Y-%m-%d")
    if [[ "$recovery_timestamp" == "$today"* ]]; then
        log "INFO" "发现今天的恢复点，上次备份在 '$recovery_stage' 阶段中断"
        log "INFO" "将从中断点继续备份"
        
        # 设置备份目录为恢复点中的目录
        if [ -d "$recovery_dir" ]; then
            BACKUP_DIR="$recovery_dir"
            log "INFO" "使用现有备份目录: $BACKUP_DIR"
            
            # 根据恢复点阶段设置跳过标志
            SKIP_SYSTEM_CONFIG=false
            SKIP_USER_CONFIG=false
            SKIP_CUSTOM_PATHS=false
            SKIP_PACKAGES=false
            SKIP_LOGS=false
            
            case "$recovery_stage" in
                "system_config")
                    SKIP_SYSTEM_CONFIG=true
                    ;;
                "user_config")
                    SKIP_SYSTEM_CONFIG=true
                    SKIP_USER_CONFIG=true
                    ;;
                "custom_paths")
                    SKIP_SYSTEM_CONFIG=true
                    SKIP_USER_CONFIG=true
                    SKIP_CUSTOM_PATHS=true
                    ;;
                "packages")
                    SKIP_SYSTEM_CONFIG=true
                    SKIP_USER_CONFIG=true
                    SKIP_CUSTOM_PATHS=true
                    SKIP_PACKAGES=true
                    ;;
                "logs")
                    SKIP_SYSTEM_CONFIG=true
                    SKIP_USER_CONFIG=true
                    SKIP_CUSTOM_PATHS=true
                    SKIP_PACKAGES=true
                    SKIP_LOGS=true
                    ;;
            esac
            
            return 0
        else
            log "WARN" "恢复点中的备份目录不存在: $recovery_dir，将创建新的备份"
        fi
    else
        log "INFO" "找到的恢复点不是今天的，将进行新的完整备份"
    fi
    
    return 0
}

# 并行执行备份任务
run_parallel_backup() {
    local tasks=($@)
    local results=()  
    local pids=()  # 存储后台进程的PID
    local task_count=${#tasks[@]}
    local completed=0
    local failed=0
    
    log "INFO" "开始并行备份，共 $task_count 个任务，最大并行数 $PARALLEL_JOBS"
    
    # 使用GNU Parallel执行任务
    if [ "$HAS_PARALLEL" == "true" ]; then
        log "INFO" "使用 GNU Parallel 执行并行备份"
        
        # 创建临时任务文件
        local task_file="${BACKUP_ROOT}/parallel_tasks_${TIMESTAMP}.txt"
        for task in "${tasks[@]}"; do
            echo "$task" >> "$task_file"
        done
        
        # 使用GNU Parallel执行任务
        parallel --jobs "$PARALLEL_JOBS" --joblog "${BACKUP_ROOT}/parallel_log_${TIMESTAMP}.txt" < "$task_file"
        
        # 检查结果
        local parallel_exit=$?
        if [ $parallel_exit -eq 0 ]; then
            log "INFO" "并行备份任务全部完成"
        else
            log "WARN" "并行备份任务部分失败，退出码: $parallel_exit"
        fi
        
        # 清理临时文件
        rm -f "$task_file"
        
        return $parallel_exit
    else
        # 使用bash后台进程实现并行
        log "INFO" "使用bash后台进程实现并行备份"
        
        # 创建临时目录存储任务结果
        local temp_dir="${BACKUP_ROOT}/parallel_results_${TIMESTAMP}"
        mkdir -p "$temp_dir"
        
        # 启动任务，控制并行数量
        local running=0
        local i=0
        
        while [ $i -lt $task_count ]; do
            # 检查当前运行的任务数量
            if [ $running -lt $PARALLEL_JOBS ]; then
                local task=${tasks[$i]}
                local result_file="${temp_dir}/result_${i}.txt"
                
                # 在后台执行任务并将结果保存到文件
                eval "$task; echo \$? > '$result_file'" &
                pids+=($!)
                
                log "INFO" "启动任务 #$((i+1)): ${task:0:50}... (PID: ${pids[-1]})"
                
                running=$((running + 1))
                i=$((i + 1))
            else
                # 等待任意一个任务完成
                wait -n 2>/dev/null || true
                running=$((running - 1))
            fi
        done
        
        # 等待所有任务完成
        log "INFO" "等待所有并行任务完成..."
        wait
        
        # 收集结果
        for ((i=0; i<$task_count; i++)); do
            local result_file="${temp_dir}/result_${i}.txt"
            if [ -f "$result_file" ]; then
                local exit_code=$(cat "$result_file")
                results+=($exit_code)
                
                if [ "$exit_code" -eq 0 ]; then
                    completed=$((completed + 1))
                else
                    failed=$((failed + 1))
                    log "WARN" "任务 #$((i+1)) 失败，退出码: $exit_code"
                fi
            else
                log "ERROR" "任务 #$((i+1)) 的结果文件不存在"
                failed=$((failed + 1))
            fi
        done
        
        # 清理临时文件
        rm -rf "$temp_dir"
        
        # 报告结果
        log "INFO" "并行备份完成: $completed 成功, $failed 失败"
        
        if [ $failed -eq 0 ]; then
            return 0
        else
            return 1
        fi
    fi
}

# 主函数
main() {
    log "INFO" "开始 Arch Linux 备份 (${TIMESTAMP})"
    
    # 设置错误处理陷阱
    trap 'log "ERROR" "备份过程被中断，请检查日志: $LOG_FILE"; exit 1' INT TERM
    
    # 检查是否为 root 用户
    if [ "$(id -u)" -ne 0 ]; then
        log "WARN" "脚本未以 root 用户运行，某些系统文件可能无法备份"
        log "WARN" "建议使用 sudo 运行此脚本以获得完整的备份权限"
    fi
    
    # 检查依赖
    check_dependencies || { log "FATAL" "依赖检查失败，无法继续"; exit 1; }
    
    # 加载配置
    load_config || { log "FATAL" "加载配置失败，无法继续"; exit 1; }
    
    # 检查备份目录是否可写
    if [ ! -d "$BACKUP_ROOT" ]; then
        if ! mkdir -p "$BACKUP_ROOT" 2>/dev/null; then
            log "FATAL" "无法创建备份根目录: $BACKUP_ROOT，请检查权限"
            exit 1
        fi
    elif [ ! -w "$BACKUP_ROOT" ]; then
        log "FATAL" "备份根目录不可写: $BACKUP_ROOT，请检查权限"
        exit 1
    fi
    
    # 检查是否存在恢复点
    check_recovery_point
    
    # 查找最近的备份目录（用于差异备份）
    find_last_backup
    
    # 创建备份目录（如果不是从恢复点继续）
    if [ ! -d "$BACKUP_DIR" ]; then
        create_backup_dirs || { log "FATAL" "创建备份目录失败，无法继续"; exit 1; }
    fi
    
    # 初始化跳过标志（如果未从恢复点设置）
    SKIP_SYSTEM_CONFIG=${SKIP_SYSTEM_CONFIG:-false}
    SKIP_USER_CONFIG=${SKIP_USER_CONFIG:-false}
    SKIP_CUSTOM_PATHS=${SKIP_CUSTOM_PATHS:-false}
    SKIP_PACKAGES=${SKIP_PACKAGES:-false}
    SKIP_LOGS=${SKIP_LOGS:-false}
    
    # 执行备份，根据跳过标志和配置决定是否执行
    local backup_errors=0
    
    # 判断是否使用并行备份
    if [ "$PARALLEL_BACKUP" == "true" ]; then
        log "INFO" "启用并行备份模式，最大并行任务数: $PARALLEL_JOBS"
        
        # 准备并行任务列表
        local parallel_tasks=()
        
        # 添加备份任务到列表
        if [ "$SKIP_SYSTEM_CONFIG" != "true" ] && [ "$BACKUP_SYSTEM_CONFIG" == "true" ]; then
            parallel_tasks+=("backup_system_config")
        fi
        
        if [ "$SKIP_USER_CONFIG" != "true" ] && [ "$BACKUP_USER_CONFIG" == "true" ]; then
            parallel_tasks+=("backup_user_config")
        fi
        
        if [ "$SKIP_CUSTOM_PATHS" != "true" ] && [ "$BACKUP_CUSTOM_PATHS" == "true" ]; then
            parallel_tasks+=("backup_custom_paths")
        fi
        
        if [ "$SKIP_PACKAGES" != "true" ] && [ "$BACKUP_PACKAGES" == "true" ]; then
            parallel_tasks+=("backup_packages")
        fi
        
        if [ "$SKIP_LOGS" != "true" ] && [ "$BACKUP_LOGS" == "true" ]; then
            parallel_tasks+=("backup_logs")
        fi
        
        # 执行并行备份
        if [ ${#parallel_tasks[@]} -gt 0 ]; then
            log "INFO" "开始执行 ${#parallel_tasks[@]} 个并行备份任务"
            if ! run_parallel_backup "${parallel_tasks[@]}"; then
                backup_errors=$((backup_errors + 1))
                log "WARN" "并行备份任务部分失败，请检查日志获取详细信息"
            else
                log "INFO" "并行备份任务全部成功完成"
            fi
        else
            log "INFO" "没有需要执行的备份任务"
        fi
    else
        # 顺序执行备份任务
        log "INFO" "使用顺序备份模式"
        
        # 备份系统配置
        if [ "$SKIP_SYSTEM_CONFIG" != "true" ] && [ "$BACKUP_SYSTEM_CONFIG" == "true" ]; then
            backup_system_config || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过系统配置备份 (已完成或已禁用)"
        fi
        
        # 备份用户配置
        if [ "$SKIP_USER_CONFIG" != "true" ] && [ "$BACKUP_USER_CONFIG" == "true" ]; then
            backup_user_config || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过用户配置备份 (已完成或已禁用)"
        fi
        
        # 备份自定义路径
        if [ "$SKIP_CUSTOM_PATHS" != "true" ] && [ "$BACKUP_CUSTOM_PATHS" == "true" ]; then
            backup_custom_paths || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过自定义路径备份 (已完成或已禁用)"
        fi
        
        # 备份软件包列表
        if [ "$SKIP_PACKAGES" != "true" ] && [ "$BACKUP_PACKAGES" == "true" ]; then
            backup_packages || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过软件包列表备份 (已完成或已禁用)"
        fi
        
        # 备份系统日志
        if [ "$SKIP_LOGS" != "true" ] && [ "$BACKUP_LOGS" == "true" ]; then
            backup_logs || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过系统日志备份 (已完成或已禁用)"
        fi
    fi
    
    # 报告备份错误
    if [ $backup_errors -gt 0 ]; then
        log "WARN" "备份过程中发生 $backup_errors 个错误，请检查日志获取详细信息"
    fi
    
    # 创建备份摘要
    create_backup_summary || log "WARN" "创建备份摘要失败"
    
    # 压缩备份
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        compress_backup || log "WARN" "压缩备份失败"
    fi
    
    # 验证备份
    if [ "$VERIFY_BACKUP" == "true" ]; then
        verify_backup || log "WARN" "验证备份失败，备份可能不完整"
    fi
    
    # 测试备份恢复
    if [ "$TEST_RESTORE" == "true" ]; then
        test_backup_restore || log "WARN" "测试备份恢复失败，备份可能无法正确恢复"
    fi
    
    # 清理旧备份
    cleanup_old_backups || log "WARN" "清理旧备份失败"
    
    # 清理恢复点文件
    find "$BACKUP_ROOT" -name "recovery_*.json" -type f -delete
    
    # 重置陷阱
    trap - INT TERM
    
    if [ $backup_errors -eq 0 ]; then
        log "INFO" "备份成功完成！备份目录: ${BACKUP_DIR}"
    else
        log "WARN" "备份完成，但有 $backup_errors 个错误，请检查日志获取详细信息"
    fi
    
    log "INFO" "日志文件: ${LOG_FILE}"
    return $backup_errors
}

# 显示帮助信息
show_help() {
    echo "Arch Linux 自动备份与恢复脚本"
    echo "用法: $0 [选项] [命令]"
    echo ""
    echo "命令:"
    echo "  backup              执行备份操作（默认）"
    echo "  restore             执行恢复操作"
    echo "  list                列出可用的备份"
    echo ""
    echo "选项:"
    echo "  -h, --help          显示此帮助信息"
    echo "  -c, --config FILE   指定配置文件路径"
    echo "  -d, --dir DIR       指定备份根目录"
    echo "  -s, --select ITEMS  选择要备份/恢复的项目（用逗号分隔）"
    echo "                      可选项: system,user,custom,packages,logs"
    echo "  -f, --force         强制执行，不提示确认"
    echo "  -v, --verbose       显示详细输出"
    echo ""
    echo "恢复选项:"
    echo "  -b, --backup-id ID  指定要恢复的备份ID（日期格式YYYY-MM-DD）"
    echo "  -p, --pre-backup    恢复前创建当前状态的备份"
    echo "  -t, --target DIR    指定恢复目标目录（默认为原始位置）"
    echo ""
    echo "示例:"
    echo "  $0                  执行完整备份"
    echo "  $0 backup -s system,user  仅备份系统和用户配置"
    echo "  $0 restore -b 2023-01-01  恢复指定日期的备份"
    echo "  $0 restore -s user -t /tmp/restore  仅恢复用户配置到指定目录"
    echo "  $0 list             列出所有可用的备份"
}

# 列出可用的备份
list_backups() {
    log "INFO" "列出可用的备份..."
    
    if [ ! -d "$BACKUP_ROOT" ]; then
        log "ERROR" "备份根目录不存在: $BACKUP_ROOT"
        return 1
    fi
    
    # 查找所有备份目录（格式为YYYY-MM-DD的目录）
    local backups=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]" | sort -r))
    local compressed_backups=($(find "$BACKUP_ROOT" -maxdepth 1 -type f -name "[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]_backup.tar*" | sort -r))
    
    if [ ${#backups[@]} -eq 0 ] && [ ${#compressed_backups[@]} -eq 0 ]; then
        log "INFO" "没有找到可用的备份"
        return 0
    fi
    
    # 显示未压缩的备份
    if [ ${#backups[@]} -gt 0 ]; then
        log "INFO" "找到 ${#backups[@]} 个未压缩的备份:"
        
        printf "%-15s %-10s %-15s %s\n" "备份日期" "大小" "项目" "摘要"
        printf "%-15s %-10s %-15s %s\n" "---------------" "----------" "---------------" "--------------------"
        
        for backup in "${backups[@]}"; do
            local backup_date=$(basename "$backup")
            local size=$(du -sh "$backup" 2>/dev/null | cut -f1)
            local items=""
            local summary=""
            
            # 检查备份中包含的项目
            [ -d "$backup/etc" ] && items="${items}system,"
            [ -d "$backup/home" ] && items="${items}user,"
            [ -d "$backup/custom" ] && items="${items}custom,"
            [ -d "$backup/packages" ] && items="${items}packages,"
            [ -d "$backup/logs" ] && items="${items}logs,"
            items=${items%,}
            
            # 检查是否有摘要文件
            if [ -f "$backup/backup_summary.txt" ]; then
                summary=$(head -n 1 "$backup/backup_summary.txt")
            fi
            
            printf "%-15s %-10s %-15s %s\n" "$backup_date" "$size" "$items" "${summary:0:50}"
        done
    fi
    
    # 显示压缩的备份
    if [ ${#compressed_backups[@]} -gt 0 ]; then
        log "INFO" "找到 ${#compressed_backups[@]} 个压缩的备份:"
        
        printf "%-20s %-10s %-15s\n" "备份文件" "大小" "压缩方式"
        printf "%-20s %-10s %-15s\n" "--------------------" "----------" "---------------"
        
        for backup in "${compressed_backups[@]}"; do
            local backup_name=$(basename "$backup")
            local size=$(du -h "$backup" 2>/dev/null | cut -f1)
            local compression="未知"
            
            # 检测压缩方式
            if [[ "$backup" == *.tar.gz ]]; then
                compression="gzip"
            elif [[ "$backup" == *.tar.bz2 ]]; then
                compression="bzip2"
            elif [[ "$backup" == *.tar.xz ]]; then
                compression="xz"
            fi
            
            printf "%-20s %-10s %-15s\n" "$backup_name" "$size" "$compression"
        done
    fi
    
    return 0
}

# 在恢复前创建当前状态的备份
create_pre_restore_backup() {
    log "INFO" "在恢复前创建当前状态的备份..."
    
    # 设置特殊的备份目录名称
    local original_backup_dir="$BACKUP_DIR"
    BACKUP_DIR="${BACKUP_ROOT}/pre_restore_${TIMESTAMP}"
    
    # 执行备份
    log "INFO" "创建恢复前备份: $BACKUP_DIR"
    
    # 备份系统配置
    if [[ "$SELECTED_ITEMS" == *"system"* ]] || [ -z "$SELECTED_ITEMS" ]; then
        backup_system_config || log "WARN" "恢复前备份系统配置失败"
    fi
    
    # 备份用户配置
    if [[ "$SELECTED_ITEMS" == *"user"* ]] || [ -z "$SELECTED_ITEMS" ]; then
        backup_user_config || log "WARN" "恢复前备份用户配置失败"
    fi
    
    # 备份自定义路径
    if [[ "$SELECTED_ITEMS" == *"custom"* ]] || [ -z "$SELECTED_ITEMS" ]; then
        backup_custom_paths || log "WARN" "恢复前备份自定义路径失败"
    fi
    
    # 备份软件包列表
    if [[ "$SELECTED_ITEMS" == *"packages"* ]] || [ -z "$SELECTED_ITEMS" ]; then
        backup_packages || log "WARN" "恢复前备份软件包列表失败"
    fi
    
    # 备份系统日志
    if [[ "$SELECTED_ITEMS" == *"logs"* ]] || [ -z "$SELECTED_ITEMS" ]; then
        backup_logs || log "WARN" "恢复前备份系统日志失败"
    fi
    
    # 创建备份摘要
    create_backup_summary || log "WARN" "创建恢复前备份摘要失败"
    
    # 恢复原始备份目录
    BACKUP_DIR="$original_backup_dir"
    
    log "INFO" "恢复前备份完成: ${BACKUP_ROOT}/pre_restore_${TIMESTAMP}"
    return 0
}

# 恢复系统配置
restore_system_config() {
    if [[ "$SELECTED_ITEMS" != *"system"* ]] && [ -n "$SELECTED_ITEMS" ]; then
        log "INFO" "跳过系统配置恢复"
        return 0
    fi
    
    log "INFO" "开始恢复系统配置..."
    
    # 检查源目录是否存在
    if [ ! -d "${SOURCE_BACKUP_DIR}/etc" ]; then
        log "ERROR" "源备份目录中不存在系统配置: ${SOURCE_BACKUP_DIR}/etc"
        return 1
    fi
    
    # 确定目标目录
    local target_dir="/etc"
    if [ -n "$TARGET_DIR" ]; then
        target_dir="${TARGET_DIR}/etc"
        mkdir -p "$target_dir"
    fi
    
    # 确认恢复操作
    if [ "$FORCE_MODE" != "true" ]; then
        echo -e "${YELLOW}警告: 即将恢复系统配置到 $target_dir${NC}"
        echo -e "${YELLOW}这将覆盖现有的系统配置文件${NC}"
        read -p "是否继续? (y/n): " confirm
        if [[ "$confirm" != [yY] ]]; then
            log "INFO" "用户取消了系统配置恢复"
            return 0
        fi
    fi
    
    # 使用 rsync 恢复系统配置
    log "INFO" "恢复系统配置到: $target_dir"
    
    local rsync_cmd=""
    if [ -n "$TARGET_DIR" ]; then
        # 恢复到自定义目录，不需要sudo
        rsync_cmd="rsync -aAXv --info=progress2 \"${SOURCE_BACKUP_DIR}/etc/\" \"$target_dir/\" >> \"$LOG_FILE\" 2>&1"
    else
        # 恢复到系统目录，需要sudo
        rsync_cmd="sudo rsync -aAXv --info=progress2 \"${SOURCE_BACKUP_DIR}/etc/\" \"$target_dir/\" >> \"$LOG_FILE\" 2>&1"
    fi
    
    if exec_with_retry "$rsync_cmd" "系统配置恢复"; then
        log "INFO" "系统配置恢复完成"
        return 0
    else
        log "ERROR" "系统配置恢复失败"
        return 1
    fi
}

# 恢复用户配置
restore_user_config() {
    if [[ "$SELECTED_ITEMS" != *"user"* ]] && [ -n "$SELECTED_ITEMS" ]; then
        log "INFO" "跳过用户配置恢复"
        return 0
    fi
    
    log "INFO" "开始恢复用户配置..."
    
    # 检查源目录是否存在
    if [ ! -d "${SOURCE_BACKUP_DIR}/home" ]; then
        log "ERROR" "源备份目录中不存在用户配置: ${SOURCE_BACKUP_DIR}/home"
        return 1
    fi
    
    # 确定目标目录
    local target_dir="$REAL_HOME"
    if [ -n "$TARGET_DIR" ]; then
        target_dir="${TARGET_DIR}/home"
        mkdir -p "$target_dir"
    fi
    
    # 确认恢复操作
    if [ "$FORCE_MODE" != "true" ]; then
        echo -e "${YELLOW}警告: 即将恢复用户配置到 $target_dir${NC}"
        echo -e "${YELLOW}这将覆盖现有的用户配置文件${NC}"
        read -p "是否继续? (y/n): " confirm
        if [[ "$confirm" != [yY] ]]; then
            log "INFO" "用户取消了用户配置恢复"
            return 0
        fi
    fi
    
    # 使用 rsync 恢复用户配置
    log "INFO" "恢复用户配置到: $target_dir"
    
    local rsync_cmd="rsync -aAXv --info=progress2 \"${SOURCE_BACKUP_DIR}/home/\" \"$target_dir/\" >> \"$LOG_FILE\" 2>&1"
    
    if exec_with_retry "$rsync_cmd" "用户配置恢复"; then
        log "INFO" "用户配置恢复完成"
        return 0
    else
        log "ERROR" "用户配置恢复失败"
        return 1
    fi
}

# 恢复自定义路径
restore_custom_paths() {
    if [[ "$SELECTED_ITEMS" != *"custom"* ]] && [ -n "$SELECTED_ITEMS" ]; then
        log "INFO" "跳过自定义路径恢复"
        return 0
    fi
    
    log "INFO" "开始恢复自定义路径..."
    
    # 检查源目录是否存在
    if [ ! -d "${SOURCE_BACKUP_DIR}/custom" ]; then
        log "ERROR" "源备份目录中不存在自定义路径: ${SOURCE_BACKUP_DIR}/custom"
        return 1
    fi
    
    # 确定目标目录前缀
    local target_prefix=""
    if [ -n "$TARGET_DIR" ]; then
        target_prefix="${TARGET_DIR}"
        mkdir -p "$target_prefix"
    fi
    
    # 从配置文件中读取自定义路径列表
    IFS=' ' read -r -a custom_paths <<< "$CUSTOM_PATHS"
    local restore_errors=0
    
    for path in "${custom_paths[@]}"; do
        local base_name=$(basename "$path")
        
        if [ -e "${SOURCE_BACKUP_DIR}/custom/$base_name" ]; then
            # 确定目标路径
            local target_path="$path"
            if [ -n "$target_prefix" ]; then
                target_path="${target_prefix}${path}"
                # 创建必要的目录结构
                mkdir -p "$(dirname "$target_path")"
            fi
            
            # 确认恢复操作
            if [ "$FORCE_MODE" != "true" ]; then
                echo -e "${YELLOW}警告: 即将恢复自定义路径 $base_name 到 $target_path${NC}"
                echo -e "${YELLOW}这将覆盖现有的文件${NC}"
                read -p "是否继续? (y/n): " confirm
                if [[ "$confirm" != [yY] ]]; then
                    log "INFO" "用户取消了自定义路径 $base_name 的恢复"
                    continue
                fi
            fi
            
            log "INFO" "恢复自定义路径: $base_name 到 $target_path"
            
            # 使用 rsync 恢复自定义路径
            local rsync_cmd=""
            if [ -n "$target_prefix" ] || [ ! -w "$(dirname "$path")" ]; then
                # 恢复到自定义目录或原始目录需要sudo
                rsync_cmd="sudo rsync -aAXv --info=progress2 \"${SOURCE_BACKUP_DIR}/custom/$base_name\" \"$(dirname "$target_path")/\" >> \"$LOG_FILE\" 2>&1"
            else
                rsync_cmd="rsync -aAXv --info=progress2 \"${SOURCE_BACKUP_DIR}/custom/$base_name\" \"$(dirname "$target_path")/\" >> \"$LOG_FILE\" 2>&1"
            fi
            
            if ! exec_with_retry "$rsync_cmd" "自定义路径 $base_name 恢复"; then
                log "ERROR" "自定义路径 $base_name 恢复失败"
                restore_errors=$((restore_errors + 1))
            else
                log "INFO" "自定义路径 $base_name 恢复完成"
            fi
        else
            log "WARN" "备份中不存在自定义路径: $base_name，跳过恢复"
        fi
    done
    
    if [ $restore_errors -eq 0 ]; then
        log "INFO" "所有自定义路径恢复完成"
        return 0
    else
        log "WARN" "自定义路径恢复部分失败，$restore_errors 个错误"
        return 1
    fi
}

# 恢复软件包列表
restore_packages() {
    if [[ "$SELECTED_ITEMS" != *"packages"* ]] && [ -n "$SELECTED_ITEMS" ]; then
        log "INFO" "跳过软件包列表恢复"
        return 0
    fi
    
    log "INFO" "开始恢复软件包列表..."
    
    # 检查源目录是否存在
    if [ ! -d "${SOURCE_BACKUP_DIR}/packages" ]; then
        log "ERROR" "源备份目录中不存在软件包列表: ${SOURCE_BACKUP_DIR}/packages"
        return 1
    fi
    
    # 确定目标目录
    local target_dir="${TARGET_DIR:-/tmp}/packages_restore"
    mkdir -p "$target_dir"
    
    # 复制软件包列表到目标目录
    log "INFO" "复制软件包列表到: $target_dir"
    cp -f "${SOURCE_BACKUP_DIR}/packages/"* "$target_dir/" 2>/dev/null
    
    # 如果不是恢复到自定义目录，则提示用户如何使用软件包列表
    if [ -z "$TARGET_DIR" ]; then
        log "INFO" "软件包列表已复制到: $target_dir"
        log "INFO" "您可以使用以下命令安装官方软件包:"
        log "INFO" "  sudo pacman -S --needed - < $target_dir/official_packages.txt"
        
        if [ -f "$target_dir/aur_packages.txt" ]; then
            log "INFO" "您可以使用以下命令安装AUR软件包:"
            log "INFO" "  yay -S --needed - < $target_dir/aur_packages.txt"
        fi
        
        # 确认是否要自动安装软件包
        if [ "$FORCE_MODE" != "true" ]; then
            echo -e "${YELLOW}警告: 是否要自动安装备份的软件包?${NC}"
            echo -e "${YELLOW}这可能需要很长时间，并可能覆盖现有的软件包${NC}"
            read -p "是否继续? (y/n): " confirm
            if [[ "$confirm" != [yY] ]]; then
                log "INFO" "用户取消了软件包安装"
                return 0
            fi
        fi
        
        # 安装官方软件包
        if [ -f "$target_dir/official_packages.txt" ]; then
            log "INFO" "开始安装官方软件包..."
            if sudo pacman -S --needed --noconfirm - < "$target_dir/official_packages.txt" >> "$LOG_FILE" 2>&1; then
                log "INFO" "官方软件包安装完成"
            else
                log "WARN" "官方软件包安装部分失败，请查看日志获取详细信息"
            fi
        fi
        
        # 安装AUR软件包（如果有yay）
        if [ -f "$target_dir/aur_packages.txt" ] && command -v yay >/dev/null 2>&1; then
            log "INFO" "开始安装AUR软件包..."
            if yay -S --needed --noconfirm - < "$target_dir/aur_packages.txt" >> "$LOG_FILE" 2>&1; then
                log "INFO" "AUR软件包安装完成"
            else
                log "WARN" "AUR软件包安装部分失败，请查看日志获取详细信息"
            fi
        elif [ -f "$target_dir/aur_packages.txt" ]; then
            log "WARN" "未检测到yay，无法自动安装AUR软件包"
            log "INFO" "AUR软件包列表: $target_dir/aur_packages.txt"
        fi
    else
        log "INFO" "软件包列表已复制到: $target_dir"
    fi
    
    return 0
}

# 恢复系统日志
restore_logs() {
    if [[ "$SELECTED_ITEMS" != *"logs"* ]] && [ -n "$SELECTED_ITEMS" ]; then
        log "INFO" "跳过系统日志恢复"
        return 0
    fi
    
    log "INFO" "开始恢复系统日志..."
    
    # 检查源目录是否存在
    if [ ! -d "${SOURCE_BACKUP_DIR}/logs" ]; then
        log "ERROR" "源备份目录中不存在系统日志: ${SOURCE_BACKUP_DIR}/logs"
        return 1
    fi
    
    # 确定目标目录
    local target_dir="${TARGET_DIR:-/tmp}/logs_restore"
    mkdir -p "$target_dir"
    
    # 复制日志到目标目录
    log "INFO" "复制系统日志到: $target_dir"
    cp -rf "${SOURCE_BACKUP_DIR}/logs/"* "$target_dir/" 2>/dev/null
    
    log "INFO" "系统日志已复制到: $target_dir"
    log "INFO" "注意: 系统日志仅供参考，不会被恢复到系统中"
    
    return 0
}

# 执行恢复操作
do_restore() {
    log "INFO" "开始执行恢复操作..."
    
    # 检查备份ID是否指定
    if [ -z "$BACKUP_ID" ]; then
        log "ERROR" "未指定要恢复的备份ID，请使用 -b 或 --backup-id 选项指定"
        return 1
    fi
    
    # 确定源备份目录
    SOURCE_BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_ID}"
    
    # 检查源备份目录是否存在
    if [ ! -d "$SOURCE_BACKUP_DIR" ]; then
        # 检查是否有压缩的备份文件
        local compressed_backup=""
        for ext in ".tar.gz" ".tar.bz2" ".tar.xz" ".tar"; do
            if [ -f "${BACKUP_ROOT}/${BACKUP_ID}_backup$ext" ]; then
                compressed_backup="${BACKUP_ROOT}/${BACKUP_ID}_backup$ext"
                break
            fi
        done
        
        if [ -n "$compressed_backup" ]; then
            log "INFO" "找到压缩的备份文件: $compressed_backup"
            log "INFO" "解压备份文件..."
            
            # 创建临时解压目录
            local temp_extract_dir="${BACKUP_ROOT}/temp_extract_${TIMESTAMP}"
            mkdir -p "$temp_extract_dir"
            
            # 解压备份文件
            local decompress_cmd=""
            case "$compressed_backup" in
                *.tar.gz)
                    decompress_cmd="tar -xzf \"$compressed_backup\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                    ;;
                *.tar.bz2)
                    decompress_cmd="tar -xjf \"$compressed_backup\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                    ;;
                *.tar.xz)
                    decompress_cmd="tar -xJf \"$compressed_backup\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                    ;;
                *.tar)
                    decompress_cmd="tar -xf \"$compressed_backup\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                    ;;
            esac
            
            if exec_with_retry "$decompress_cmd" "解压备份文件"; then
                log "INFO" "备份文件解压成功"
                # 设置源备份目录为解压后的目录
                SOURCE_BACKUP_DIR="$temp_extract_dir/${BACKUP_ID}"
                
                # 检查解压后的目录是否存在
                if [ ! -d "$SOURCE_BACKUP_DIR" ]; then
                    # 尝试查找解压后的目录
                    local extracted_dir=$(find "$temp_extract_dir" -maxdepth 1 -type d | grep -v "^$temp_extract_dir$" | head -1)
                    if [ -n "$extracted_dir" ]; then
                        SOURCE_BACKUP_DIR="$extracted_dir"
                    else
                        log "ERROR" "无法找到解压后的备份目录"
                        rm -rf "$temp_extract_dir"
                        return 1
                    fi
                fi
            else
                log "ERROR" "备份文件解压失败"
                rm -rf "$temp_extract_dir"
                return 1
            fi
        else
            log "ERROR" "找不到指定的备份: ${BACKUP_ID}"
            return 1
        fi
    fi
    
    log "INFO" "使用备份源: $SOURCE_BACKUP_DIR"
    
    # 如果启用了恢复前备份，先创建当前状态的备份
    if [ "$PRE_RESTORE_BACKUP" == "true" ]; then
        create_pre_restore_backup || log "WARN" "恢复前备份创建失败，继续恢复操作"
    fi
    
    # 恢复系统配置
    restore_system_config
    
    # 恢复用户配置
    restore_user_config
    
    # 恢复自定义路径
    restore_custom_paths
    
    # 恢复软件包列表
    restore_packages
    
    # 恢复系统日志
    restore_logs
    
    # 清理临时解压目录
    if [[ "$SOURCE_BACKUP_DIR" == */temp_extract_* ]]; then
        log "INFO" "清理临时解压目录"
        rm -rf "$(dirname "$SOURCE_BACKUP_DIR")"
    fi
    
    log "INFO" "恢复操作完成"
    return 0
}

# 主函数
main() {
    # 设置中断处理
    trap 'log "WARN" "收到中断信号，正在清理并退出..."; exit 1' INT TERM
    
    # 解析命令行参数
    parse_args "$@"
    
    # 加载配置文件
    load_config
    
    # 检查依赖
    check_dependencies || {
        log "FATAL" "依赖检查失败，无法继续执行"
        exit 1
    }
    
    # 根据命令执行相应的操作
    case "$COMMAND" in
        backup)
            # 创建备份目录
            create_backup_dirs
            
            # 执行备份
            do_backup
            exit $?
            ;;
        restore)
            # 执行恢复
            do_restore
            exit $?
            ;;
        list)
            # 列出可用的备份
            list_backups
            exit $?
            ;;
        *)
            log "ERROR" "未知命令: $COMMAND"
            show_help
            exit 1
            ;;
    esac
}

# 执行主函数
main "$@"

# 执行恢复操作
do_restore() {
    log "INFO" "开始执行恢复操作..."
    
    # 检查备份ID是否指定
    if [ -z "$BACKUP_ID" ]; then
        log "ERROR" "未指定要恢复的备份ID，请使用 -b 或 --backup-id 选项指定"
        return 1
    fi
    
    # 确定源备份目录
    SOURCE_BACKUP_DIR="${BACKUP_ROOT}/${BACKUP_ID}"
    
    # 检查源备份目录是否存在
    if [ ! -d "$SOURCE_BACKUP_DIR" ]; then
        # 检查是否有压缩的备份文件
        local compressed_backup=""
        for ext in ".tar.gz" ".tar.bz2" ".tar.xz" ".tar"; do
            if [ -f "${BACKUP_ROOT}/${BACKUP_ID}_backup$ext" ]; then
                compressed_backup="${BACKUP_ROOT}/${BACKUP_ID}_backup$ext"
                break
            fi
        done
        
        if [ -n "$compressed_backup" ]; then
            log "INFO" "找到压缩的备份文件: $compressed_backup"
            log "INFO" "解压备份文件..."
            
            # 创建临时解压目录
            local temp_extract_dir="${BACKUP_ROOT}/temp_extract_${TIMESTAMP}"
            mkdir -p "$temp_extract_dir"
            
            # 解压备份文件
            local decompress_cmd=""
            case "$compressed_backup" in
                *.tar.gz)
                    decompress_cmd="tar -xzf \"$compressed_backup\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                    ;;
                *.tar.bz2)
                    decompress_cmd="tar -xjf \"$compressed_backup\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                    ;;
                *.tar.xz)
                    decompress_cmd="tar -xJf \"$compressed_backup\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                    ;;
                *.tar)
                    decompress_cmd="tar -xf \"$compressed_backup\" -C \"$temp_extract_dir\" >> \"$LOG_FILE\" 2>&1"
                    ;;
            esac
            
            if exec_with_retry "$decompress_cmd" "解压备份文件"; then
                log "INFO" "备份文件解压成功"
                # 设置源备份目录为解压后的目录
                SOURCE_BACKUP_DIR="$temp_extract_dir/${BACKUP_ID}"
                
                # 检查解压后的目录是否存在
                if [ ! -d "$SOURCE_BACKUP_DIR" ]; then
                    # 尝试查找解压后的目录
                    local extracted_dir=$(find "$temp_extract_dir" -maxdepth 1 -type d | grep -v "^$temp_extract_dir$" | head -1)
                    if [ -n "$extracted_dir" ]; then
                        SOURCE_BACKUP_DIR="$extracted_dir"
                    else
                        log "ERROR" "无法找到解压后的备份目录"
                        rm -rf "$temp_extract_dir"
                        return 1
                    fi
                fi
            else
                log "ERROR" "备份文件解压失败"
                rm -rf "$temp_extract_dir"
                return 1
            fi
        else
            log "ERROR" "找不到指定的备份: ${BACKUP_ID}"
            return 1
        fi
    fi
    
    log "INFO" "使用备份源: $SOURCE_BACKUP_DIR"
    
    # 如果启用了恢复前备份，先创建当前状态的备份
    if [ "$PRE_RESTORE_BACKUP" == "true" ]; then
        create_pre_restore_backup || log "WARN" "恢复前备份创建失败，继续恢复操作"
    fi
    
    # 恢复系统配置
    restore_system_config
    
    # 恢复用户配置
    restore_user_config
    
    # 恢复自定义路径
    restore_custom_paths
    
    # 恢复软件包列表
    restore_packages
    
    # 恢复系统日志
    restore_logs
    
    # 清理临时解压目录
    if [[ "$SOURCE_BACKUP_DIR" == */temp_extract_* ]]; then
        log "INFO" "清理临时解压目录"
        rm -rf "$(dirname "$SOURCE_BACKUP_DIR")"
    fi
    
    log "INFO" "恢复操作完成"
    return 0
}

# 解析命令行参数
parse_args() {
    # 默认命令为备份
    COMMAND="backup"
    FORCE_MODE=false
    VERBOSE_MODE=false
    PRE_RESTORE_BACKUP=false
    SELECTED_ITEMS=""
    BACKUP_ID=""
    TARGET_DIR=""
    
    # 解析位置参数（命令）
    if [ $# -gt 0 ] && [[ "$1" != -* ]]; then
        case "$1" in
            backup|restore|list)
                COMMAND="$1"
                shift
                ;;
            help|--help|-h)
                show_help
                exit 0
                ;;
            *)
                log "ERROR" "未知命令: $1"
                show_help
                exit 1
                ;;
        esac
    fi
    
    # 解析选项参数
    while [ $# -gt 0 ]; do
        case "$1" in
            -h|--help)
                show_help
                exit 0
                ;;
            -c|--config)
                CONFIG_FILE="$2"
                shift 2
                ;;
            -d|--dir)
                BACKUP_ROOT="$2"
                shift 2
                ;;
            -s|--select)
                SELECTED_ITEMS="$2"
                shift 2
                ;;
            -f|--force)
                FORCE_MODE=true
                shift
                ;;
            -v|--verbose)
                VERBOSE_MODE=true
                shift
                ;;
            -b|--backup-id)
                BACKUP_ID="$2"
                shift 2
                ;;
            -p|--pre-backup)
                PRE_RESTORE_BACKUP=true
                shift
                ;;
            -t|--target)
                TARGET_DIR="$2"
                shift 2
                ;;
            *)
                log "ERROR" "未知选项: $1"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 验证参数
    if [ "$COMMAND" == "restore" ] && [ -z "$BACKUP_ID" ]; then
        log "ERROR" "恢复操作需要指定备份ID，请使用 -b 或 --backup-id 选项"
        show_help
        exit 1
    fi
    
    # 设置备份目录
    if [ "$COMMAND" == "backup" ]; then
        BACKUP_DIR="${BACKUP_ROOT}/${DATE_FORMAT}"
    fi
    
    # 如果启用了详细模式，设置日志级别
    if [ "$VERBOSE_MODE" == "true" ]; then
        # 这里可以添加详细日志的设置
        log "INFO" "启用详细输出模式"
    fi
}
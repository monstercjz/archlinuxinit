#!/bin/bash

# 依赖: logging.sh (log 函数)

# 设置默认配置值
# 这些值将在配置文件未定义相应变量时使用
set_default_config() {
    # 核心路径和文件
    BACKUP_ROOT=${BACKUP_ROOT:-"/mnt/backup/arch-backup"}
    # CONFIG_FILE 由主脚本根据 REAL_HOME 设置，这里不设默认值
    # LOG_FILE 由主脚本根据 BACKUP_ROOT 和 TIMESTAMP 设置，这里不设默认值

    # 备份内容开关
    BACKUP_SYSTEM_CONFIG=${BACKUP_SYSTEM_CONFIG:-true}
    BACKUP_USER_CONFIG=${BACKUP_USER_CONFIG:-true}
    BACKUP_CUSTOM_PATHS=${BACKUP_CUSTOM_PATHS:-true}
    BACKUP_PACKAGES=${BACKUP_PACKAGES:-true}
    BACKUP_LOGS=${BACKUP_LOGS:-true}

    # 备份目录结构 (相对于日期目录)
    BACKUP_DIRS=${BACKUP_DIRS:-"etc home packages logs custom"}

    # 用户配置相关
    USER_CONFIG_FILES=${USER_CONFIG_FILES:-".bashrc .zshrc .config/fish/config.fish .profile .bash_profile .zprofile .config .local/share .themes .icons .fonts .ssh .gnupg .mozilla .config/chromium .vimrc .config/nvim .tmux.conf .gitconfig .xinitrc .xprofile"}
    EXCLUDE_USER_CONFIGS=${EXCLUDE_USER_CONFIGS:-".cache node_modules .npm .yarn .local/share/Trash"}

    # 系统配置排除项
    EXCLUDE_SYSTEM_CONFIGS=${EXCLUDE_SYSTEM_CONFIGS:-"/etc/pacman.d/gnupg"}

    # 自定义路径相关
    CUSTOM_PATHS=${CUSTOM_PATHS:-""} # 默认为空
    EXCLUDE_CUSTOM_PATHS=${EXCLUDE_CUSTOM_PATHS:-"*/temp */cache */logs"}

    # 备份选项
    COMPRESS_BACKUP=${COMPRESS_BACKUP:-false}
    COMPRESS_METHOD=${COMPRESS_METHOD:-"gzip"}
    DIFF_BACKUP=${DIFF_BACKUP:-false}
    VERIFY_BACKUP=${VERIFY_BACKUP:-false}
    PARALLEL_BACKUP=${PARALLEL_BACKUP:-false}
    PARALLEL_JOBS=${PARALLEL_JOBS:-4}

    # 保留策略
    LOG_RETENTION_DAYS=${LOG_RETENTION_DAYS:-30}
    BACKUP_RETENTION_COUNT=${BACKUP_RETENTION_COUNT:-7}

    # 内部使用的或示例性的配置
    NETWORK_BACKUP=${NETWORK_BACKUP:-false}
    ENCRYPT_BACKUP=${ENCRYPT_BACKUP:-false}
    TEST_RESTORE=${TEST_RESTORE:-false}

    # 确保 PARALLEL_JOBS 是数字且大于0
    if ! [[ "$PARALLEL_JOBS" =~ ^[0-9]+$ ]] || [ "$PARALLEL_JOBS" -le 0 ]; then
        log "WARN" "PARALLEL_JOBS ('$PARALLEL_JOBS') 不是有效的正整数，将使用默认值 4"
        PARALLEL_JOBS=4
    fi
    # 确保保留天数和数量是数字且非负
    if ! [[ "$LOG_RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
        log "WARN" "LOG_RETENTION_DAYS ('$LOG_RETENTION_DAYS') 不是有效的非负整数，将使用默认值 30"
        LOG_RETENTION_DAYS=30
    fi
     if ! [[ "$BACKUP_RETENTION_COUNT" =~ ^[0-9]+$ ]]; then
        log "WARN" "BACKUP_RETENTION_COUNT ('$BACKUP_RETENTION_COUNT') 不是有效的非负整数，将使用默认值 7"
        BACKUP_RETENTION_COUNT=7
    fi
}

# 加载配置文件
# 功能：加载用户配置文件，如果不存在则使用默认配置
# 参数：
#   $1 - 配置文件的路径
# 返回值：
#   0 - 加载成功或文件不存在使用默认值
#   1 - 配置文件存在但无法读取
# 副作用：
#   会覆盖 set_default_config 设置的变量值（如果配置文件中定义了）
load_config() {
    local config_path="$1"

    # 先设置默认值
    set_default_config

    if [ -f "$config_path" ]; then
        log "INFO" "加载配置文件: $config_path"
        # 检查文件是否可读
        if [ -r "$config_path" ]; then
            # 使用 source 加载配置，这将覆盖默认值
            # 在子shell中执行source，避免污染当前环境的非配置变量
            # 但我们需要配置变量生效，所以直接 source
            source "$config_path"
            log "INFO" "配置文件加载完成"
            return 0
        else
            log "ERROR" "配置文件 $config_path 存在但不可读，将使用默认配置"
            return 1 # 返回错误码，表示配置加载有问题
        fi
    else
        log "WARN" "配置文件 $config_path 不存在，将使用默认配置"
        # 可选：如果希望在文件不存在时创建默认文件，可以在这里调用创建逻辑
        # create_default_config_if_not_exists "$config_path"
        return 0 # 文件不存在不是错误，使用默认值
    fi
}

# 可选：创建默认配置文件的函数（如果需要）
create_default_config_if_not_exists() {
    local config_path="$1"
    if [ ! -f "$config_path" ]; then
        log "INFO" "创建默认配置文件: $config_path"
        mkdir -p "$(dirname "$config_path")"
        # 从 set_default_config 或硬编码的默认值生成文件内容
        # 注意：这部分逻辑需要仔细编写，以反映所有默认值
        cat > "$config_path" << EOF
# Arch Linux 备份配置文件 (自动生成)

BACKUP_ROOT="/mnt/backup/arch-backup"
BACKUP_DIRS="etc home packages logs custom"
USER_CONFIG_FILES=".bashrc .zshrc .config/fish/config.fish .profile .bash_profile .zprofile .config .local/share .themes .icons .fonts .ssh .gnupg .mozilla .config/chromium .vimrc .config/nvim .tmux.conf .gitconfig .xinitrc .xprofile"
EXCLUDE_USER_CONFIGS=".cache node_modules .npm .yarn .local/share/Trash"
EXCLUDE_SYSTEM_CONFIGS="/etc/pacman.d/gnupg"
CUSTOM_PATHS=""
EXCLUDE_CUSTOM_PATHS="*/temp */cache */logs"
BACKUP_SYSTEM_CONFIG=true
BACKUP_USER_CONFIG=true
BACKUP_CUSTOM_PATHS=true
BACKUP_PACKAGES=true
BACKUP_LOGS=true
COMPRESS_BACKUP=false
COMPRESS_METHOD="gzip"
DIFF_BACKUP=false
VERIFY_BACKUP=false
PARALLEL_BACKUP=false
PARALLEL_JOBS=4
LOG_RETENTION_DAYS=30
BACKUP_RETENTION_COUNT=7
EOF
    fi
}

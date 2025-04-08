# 加载配置文件
# 功能：加载用户配置文件，如果不存在则创建默认配置文件
# 参数：无
# 返回值：无
# 错误处理：
#   如果配置文件不存在，会创建一个包含默认设置的配置文件
# 配置项：
#   - 备份根目录
#   - 备份目录结构
#   - 用户配置文件列表
#   - 排除项
#   - 备份选项（压缩、差异备份等）
#   - 并行备份设置
#   - 日志和备份保留策略
# 使用示例：
#   load_config
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        # Source the config file first to load variables into the current shell
        source "$CONFIG_FILE"
        # Export the variables to make them available to sub-processes/scripts
        export BACKUP_ROOT BACKUP_DIRS
        export BACKUP_SYSTEM_CONFIG BACKUP_USER_CONFIG BACKUP_CUSTOM_PATHS BACKUP_PACKAGES BACKUP_LOGS
        export USER_CONFIG_FILES CUSTOM_PATHS
        export EXCLUDE_SYSTEM_CONFIGS EXCLUDE_USER_CONFIGS EXCLUDE_CUSTOM_PATHS
        export DIFF_BACKUP PARALLEL_BACKUP PARALLEL_JOBS VERIFY_BACKUP VERIFY_CHECKSUM COMPRESS_BACKUP COMPRESS_METHOD
        export LOG_LEVEL LOG_TO_FILE VERBOSE PROGRESS_TYPE COLOR_OUTPUT SHOW_PROGRESS LOG_SHOW_CALLER
        export LOG_FILE_MAX_SIZE LOG_FILE_MAX_COUNT LOG_RETENTION_DAYS
        init_logging # Initialize logging after sourcing config for LOG_LEVEL etc.
        log_section "初始化******配置文件 (${TIMESTAMP})"  $LOG_LEVEL_NOTICE
        log "INFO" "加载配置文件: $CONFIG_FILE"
        # Log loaded values (optional, for debugging)
        log "DEBUG" "BACKUP_ROOT=$BACKUP_ROOT"
        log "DEBUG" "VERIFY_CHECKSUM=$VERIFY_CHECKSUM"
        # Add more debug logs if needed
    else
        # 创建默认配置文件
        mkdir -p "$(dirname "$CONFIG_FILE")"
        cat > "$CONFIG_FILE" << EOF
# Arch Linux 备份配置默认文件

# ---------------备份目标目录设定---------------
# 备份根目录
BACKUP_ROOT="/var/backups/arch-backup"

# ---------------备份总类---------------
# 备份目录结构（空格分隔）
BACKUP_DIRS="etc home custom packages logs"

# ---------------备份开关---------------
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

# ---------------源目录---------------
# etc目录固定，无需再次设定
# 要备份的用户配置文件和目录（空格分隔）
USER_CONFIG_FILES=".bashrc .zshrc .p10k.zsh .nanorc .bash_profile .profile .zprofile .gitconfig .xinitrc .xprofile .config .local .vscode"

# 自定义备份路径（空格分隔）
CUSTOM_PATHS="/boot"

# ---------------排除项---------------
# 排除项相对于源目录
# 要排除的系统配置目录（空格分隔）
EXCLUDE_SYSTEM_CONFIGS=""

# 要排除的用户配置文件和目录（空格分隔）
EXCLUDE_USER_CONFIGS=""

# 要排除的自定义路径（空格分隔）
EXCLUDE_CUSTOM_PATHS=""

# ---------------备份管理---------------
# 是否进行差异备份 (true/false)
# 差异备份只备份自上次备份以来变化的文件
DIFF_BACKUP=false

# 是否启用并行备份 (true/false)
# 并行备份可以同时执行多个备份任务，提高备份速度
PARALLEL_BACKUP=false

# 并行备份的最大任务数
# 建议设置为CPU核心数或略低于核心数
PARALLEL_JOBS=4

# 是否验证备份 (true/false)
# 验证备份会检查备份文件的完整性
VERIFY_BACKUP=true

# 是否压缩备份 (true/false)
COMPRESS_BACKUP=false

# 压缩方法 (gzip, bzip2, xz)
COMPRESS_METHOD="gzip"

# ---------------日志管理---------------
# 日志级别说明：
# - TRACE: 最详细的跟踪信息，用于开发调试
# - DEBUG: 调试信息，用于排查问题
# - INFO: 一般信息，默认级别
# - NOTICE: 重要提示信息
# - WARN: 警告信息
# - ERROR: 错误信息
# - CRITICAL: 严重错误信息
# - FATAL: 致命错误信息
LOG_LEVEL="INFO"            # 日志级别: TRACE, DEBUG, INFO, NOTICE, WARN, ERROR, CRITICAL, FATAL

# 是否将日志同时写入文件
LOG_TO_FILE="true"

# 日志选项
VERBOSE="false"              # 显示详细输出

# 进度显示类型 ('bar' 或 'percent')。
PROGRESS_TYPE="bar"

# 是否使用彩色输出
COLOR_OUTPUT="true"

# logging内自定义彩色进度显示
SHOW_PROGRESS="true"

# 是否显示调用者信息（函数名和行号）
LOG_SHOW_CALLER="false"     

# 日志文件最大大小（默认10MB） 
LOG_FILE_MAX_SIZE="10485760"

# 日志文件最大数量（默认5个）
LOG_FILE_MAX_COUNT="5"

# 日志保留天数
LOG_RETENTION_DAYS=30

EOF
        # Source the newly created default config file
        source "$CONFIG_FILE"
        init_logging # Initialize logging after sourcing config
        log_section "初始化******配置文件 (${TIMESTAMP})"  $LOG_LEVEL_NOTICE
        log "WARN" "由于配置文件不存在，已经创建配置文件，并且使用默认配置"
        log "INFO" "已创建默认配置文件(${TIMESTAMP}): $CONFIG_FILE"

        # Export default variables as well
        export BACKUP_ROOT BACKUP_DIRS
        export BACKUP_SYSTEM_CONFIG BACKUP_USER_CONFIG BACKUP_CUSTOM_PATHS BACKUP_PACKAGES BACKUP_LOGS
        export USER_CONFIG_FILES CUSTOM_PATHS
        export EXCLUDE_SYSTEM_CONFIGS EXCLUDE_USER_CONFIGS EXCLUDE_CUSTOM_PATHS
        export DIFF_BACKUP PARALLEL_BACKUP PARALLEL_JOBS VERIFY_BACKUP VERIFY_CHECKSUM COMPRESS_BACKUP COMPRESS_METHOD
        export LOG_LEVEL LOG_TO_FILE VERBOSE PROGRESS_TYPE COLOR_OUTPUT SHOW_PROGRESS LOG_SHOW_CALLER
        export LOG_FILE_MAX_SIZE LOG_FILE_MAX_COUNT LOG_RETENTION_DAYS
    fi
}
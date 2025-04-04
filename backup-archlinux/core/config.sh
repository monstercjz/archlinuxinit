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

# Arch Linux 备份配置默认文件

# ---------------备份目标目录设定---------------
# 备份根目录
BACKUP_ROOT="/mnt/backup/arch-backup"
# 单次备份目录------无需在配置文件定义,真正的目录
BACKUP_DIR="${BACKUP_ROOT}/${DATE_FORMAT}"
# 日志目录------无需在配置文件定义
LOG_FILE="${BACKUP_ROOT}/backup_${TIMESTAMP}.log"
# 配置文件目录------无需在配置文件定义
# LOG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../backup_${TIMESTAMP}.log"
CONFIG_FILE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/../arch-backup.conf" # 使用脚本所在目录的上级目录

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
# 差异备份关联对比目录------无需在配置文件定义
LAST_BACKUP_DIR=""
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
LOG_LEVEL="DEBUG"            # 日志级别: TRACE, DEBUG, INFO, NOTICE, WARN, ERROR, CRITICAL, FATAL

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

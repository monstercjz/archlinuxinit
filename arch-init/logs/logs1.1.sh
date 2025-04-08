#!/bin/bash
# Shebang: 指定脚本使用bash执行

#############################################################
# 版本历史
# v1.0 (Initial): 基础日志和进度功能实现。
# v1.1 (2025-03-31): 添加详细的最佳实践注释，解释代码逻辑和推荐用法。
#############################################################

#############################################################
# 增强日志模块
# 功能：提供更细粒度的日志记录、控制台输出展示和进度显示功能
# 最佳实践：在脚本开头添加清晰的描述性注释，说明脚本的用途和主要功能。
#############################################################

# --- 日志级别定义 ---
# 使用大写变量名表示常量是一种常见的Shell脚本实践。
# 数字越小，日志级别越详细。
LOG_LEVEL_TRACE=0    # 最详细的跟踪信息，用于深入调试。
LOG_LEVEL_DEBUG=1    # 调试信息，用于开发和问题排查。
LOG_LEVEL_INFO=2     # 一般信息，报告脚本的正常运行状态。
LOG_LEVEL_NOTICE=3   # 重要提示信息，需要用户注意但不一定是问题。
LOG_LEVEL_WARN=4     # 警告信息，表示可能存在的问题或潜在风险。
LOG_LEVEL_ERROR=5    # 错误信息，表示发生了可恢复的错误。
LOG_LEVEL_CRITICAL=6 # 严重错误信息，表示发生了可能影响系统稳定性的错误。
LOG_LEVEL_FATAL=7    # 致命错误信息，表示脚本无法继续执行的严重错误。

# --- Configuration Defaults ---
# 最佳实践：为配置变量提供默认值，并允许通过环境变量覆盖。
# 使用 ":=" 操作符可以在变量未设置或为空时设置默认值。
# 这使得脚本更灵活，用户可以在不修改脚本本身的情况下调整行为。
: "${LOG_LEVEL:=INFO}"                 # 默认日志级别。可被环境变量 LOG_LEVEL 覆盖。
: "${COLOR_OUTPUT:=true}"              # 默认启用彩色输出。可被环境变量 COLOR_OUTPUT=false 禁用。
: "${LOG_TO_FILE:=false}"              # 默认禁用日志文件记录。可被环境变量 LOG_TO_FILE=true 启用。
: "${LOG_FILE:=/tmp/script.log}"       # 默认日志文件路径（当 LOG_TO_FILE=true 时生效）。可被环境变量 LOG_FILE 覆盖。
: "${LOG_FILE_MAX_SIZE:=10485760}"     # 默认日志文件最大大小（10MB）。可被环境变量 LOG_FILE_MAX_SIZE 覆盖。
: "${LOG_FILE_MAX_COUNT:=5}"           # 默认日志文件轮转保留的最大数量。可被环境变量 LOG_FILE_MAX_COUNT 覆盖。
: "${VERBOSE:=false}"                  # 默认禁用在 TRACE/DEBUG 日志中显示详细的调用者信息（函数名:行号）。可被环境变量 VERBOSE=true 启用。
: "${SHOW_PROGRESS:=true}"             # 默认启用进度显示。可被环境变量 SHOW_PROGRESS=false 禁用。
: "${PROGRESS_TYPE:=bar}"              # 默认进度显示类型 ('bar' 或 'percent')。可被环境变量 PROGRESS_TYPE 覆盖。

# --- 内部状态变量 ---
# 当前日志级别 (将在 set_log_level 函数中根据 LOG_LEVEL 环境变量或默认值进行更新)
CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO # 初始值，将在 init_logging 中被正确设置。

# --- 颜色代码定义 ---
# 最佳实践：将颜色代码定义为变量，提高可读性和可维护性。
# 使用 \033[...m 定义 ANSI 转义序列来控制终端颜色和样式。
if [[ "$COLOR_OUTPUT" == "true" ]]; then
    # 前景色 (Foreground Colors)
    COLOR_RED="\033[0;31m"          # 红色 - 通常用于错误
    COLOR_LIGHT_RED="\033[1;31m"    # 亮红色 - 通常用于严重错误
    COLOR_GREEN="\033[0;32m"        # 绿色 - 通常用于信息/成功
    COLOR_LIGHT_GREEN="\033[1;32m"  # 亮绿色 - 通常用于强调成功
    COLOR_YELLOW="\033[0;33m"       # 黄色 - 通常用于警告
    COLOR_LIGHT_YELLOW="\033[1;33m" # 亮黄色 - 通常用于提示
    COLOR_BLUE="\033[0;34m"         # 蓝色 - 通常用于调试
    COLOR_LIGHT_BLUE="\033[1;34m"   # 亮蓝色 - 通常用于跟踪
    COLOR_PURPLE="\033[0;35m"       # 紫色
    COLOR_LIGHT_PURPLE="\033[1;35m" # 亮紫色 - 通常用于致命错误
    COLOR_CYAN="\033[0;36m"         # 青色
    COLOR_LIGHT_CYAN="\033[1;36m"   # 亮青色 - 通常用于通知
    COLOR_GRAY="\033[0;37m"         # 灰色
    COLOR_WHITE="\033[1;37m"        # 白色

    # 背景色 (Background Colors)
    COLOR_BG_RED="\033[41m"
    COLOR_BG_GREEN="\033[42m"
    COLOR_BG_YELLOW="\033[43m"
    COLOR_BG_BLUE="\033[44m"
    COLOR_BG_PURPLE="\033[45m"
    COLOR_BG_CYAN="\033[46m"
    COLOR_BG_WHITE="\033[47m"

    # 文本样式 (Text Styles)
    COLOR_BOLD="\033[1m"            # 粗体
    COLOR_UNDERLINE="\033[4m"       # 下划线
    COLOR_RESET="\033[0m"           # 重置所有颜色和样式属性
else
    # 如果禁用彩色输出，将所有颜色变量设置为空字符串。
    # 这样在输出时不会插入任何 ANSI 转义序列。
    # 前景色
    COLOR_RED=""
    COLOR_LIGHT_RED=""
    COLOR_GREEN=""
    COLOR_LIGHT_GREEN=""
    COLOR_YELLOW=""
    COLOR_LIGHT_YELLOW=""
    COLOR_BLUE=""
    COLOR_LIGHT_BLUE=""
    COLOR_PURPLE=""
    COLOR_LIGHT_PURPLE=""
    COLOR_CYAN=""
    COLOR_LIGHT_CYAN=""
    COLOR_GRAY=""
    COLOR_WHITE=""

    # 背景色
    COLOR_BG_RED=""
    COLOR_BG_GREEN=""
    COLOR_BG_YELLOW=""
    COLOR_BG_BLUE=""
    COLOR_BG_PURPLE=""
    COLOR_BG_CYAN=""
    COLOR_BG_WHITE=""

    # 文本样式
    COLOR_BOLD=""
    COLOR_UNDERLINE=""
    COLOR_RESET=""
fi

# --- 日志文件相关变量 ---
LOG_FILE_PATH="" # 实际使用的日志文件路径，在 init_logging 中根据 LOG_TO_FILE 和 LOG_FILE 设置。

# 日志文件最大大小（从配置中获取，这里只是重复定义，可以考虑移除）
# LOG_FILE_MAX_SIZE=10485760 # 已在配置默认值部分定义

# 日志文件最大数量（从配置中获取，这里只是重复定义，可以考虑移除）
# LOG_FILE_MAX_COUNT=5 # 已在配置默认值部分定义

# --- 日志缓冲相关变量 ---
# 最佳实践：使用日志缓冲可以减少频繁的磁盘I/O操作，提高性能，尤其是在大量日志产生时。
LOG_BUFFER=""             # 用于存储待写入文件的日志条目的缓冲区。
LOG_BUFFER_SIZE=0         # 当前缓冲区中内容的字节大小。
LOG_BUFFER_MAX_SIZE=1024  # 缓冲区最大大小（1KB）。当达到此大小时，缓冲区内容将被写入文件。

# --- 函数定义 ---

# 函数：set_log_level
# 功能：根据输入的级别字符串设置全局 CURRENT_LOG_LEVEL 变量。
# 参数：$1 - 日志级别字符串 (e.g., "INFO", "DEBUG", "WARN")，不区分大小写。
# 最佳实践：使用 local 关键字声明函数内部变量，避免污染全局命名空间。
# 最佳实践：使用 ${level^^} 将输入转换为大写，实现不区分大小写的比较。
set_log_level() {
    local level="$1" # 将第一个参数赋值给局部变量 level
    case "${level^^}" in # 将 level 转为大写进行比较
        "TRACE")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_TRACE
            ;;
        "DEBUG")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG
            ;;
        "INFO")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
            ;;
        "NOTICE")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_NOTICE
            ;;
        "WARN"|"WARNING") # 允许使用 "WARN" 或 "WARNING"
            CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN
            ;;
        "ERROR")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR
            ;;
        "CRITICAL")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_CRITICAL
            ;;
        "FATAL")
            CURRENT_LOG_LEVEL=$LOG_LEVEL_FATAL
            ;;
        *)
            # 如果提供了无效的级别，输出错误信息并使用默认的 INFO 级别。
            echo "未知的日志级别: $level，使用默认级别 INFO" >&2 # 输出到 stderr
            CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
            ;;
    esac

    # 记录日志级别变更（如果当前级别允许 INFO）
    # 注意：这里调用 log_info 可能会在 init_logging 完成前发生，
    # 如果 LOG_TO_FILE=true，此时 LOG_FILE_PATH 可能尚未设置。
    # 但由于 set_log_level 主要在 init_logging 中调用，通常问题不大。
    log_info "日志级别设置为: ${level^^}"
}

# 函数：get_log_level_name
# 功能：根据日志级别数值返回对应的级别名称字符串。
# 参数：$1 - 日志级别数值 (e.g., 0, 1, 2)。
# 返回：对应的日志级别名称字符串 (e.g., "TRACE", "DEBUG", "INFO") 或 "UNKNOWN"。
# 最佳实践：使用 case 语句处理离散值映射。
get_log_level_name() {
    local level=$1
    case $level in
        $LOG_LEVEL_TRACE)
            echo "TRACE"
            ;;
        $LOG_LEVEL_DEBUG)
            echo "DEBUG"
            ;;
        $LOG_LEVEL_INFO)
            echo "INFO"
            ;;
        $LOG_LEVEL_NOTICE)
            echo "NOTICE"
            ;;
        $LOG_LEVEL_WARN)
            echo "WARN"
            ;;
        $LOG_LEVEL_ERROR)
            echo "ERROR"
            ;;
        $LOG_LEVEL_CRITICAL)
            echo "CRITICAL"
            ;;
        $LOG_LEVEL_FATAL)
            echo "FATAL"
            ;;
        *)
            echo "UNKNOWN"
            ;;
    esac
}

# 函数：get_log_level_color
# 功能：根据日志级别数值返回对应的 ANSI 颜色代码。
# 参数：$1 - 日志级别数值。
# 返回：对应的颜色代码字符串或重置代码 COLOR_RESET。
get_log_level_color() {
    local level=$1
    case $level in
        $LOG_LEVEL_TRACE)
            echo "$COLOR_LIGHT_BLUE"
            ;;
        $LOG_LEVEL_DEBUG)
            echo "$COLOR_BLUE"
            ;;
        $LOG_LEVEL_INFO)
            echo "$COLOR_GREEN"
            ;;
        $LOG_LEVEL_NOTICE)
            echo "$COLOR_LIGHT_CYAN"
            ;;
        $LOG_LEVEL_WARN)
            echo "$COLOR_YELLOW"
            ;;
        $LOG_LEVEL_ERROR)
            echo "$COLOR_RED"
            ;;
        $LOG_LEVEL_CRITICAL)
            echo "$COLOR_LIGHT_RED"
            ;;
        $LOG_LEVEL_FATAL)
            echo "$COLOR_LIGHT_PURPLE"
            ;;
        *)
            echo "$COLOR_RESET" # 对于未知级别，不应用颜色
            ;;
    esac
}

# 函数：init_logging
# 功能：初始化日志系统。设置最终的日志级别，配置日志文件（如果启用）。
#       应在脚本早期调用此函数。
# 最佳实践：将初始化逻辑封装在函数中。
init_logging() {
    # 1. 设置日志级别
    # 使用环境变量 LOG_LEVEL 或其默认值来设置实际的 CURRENT_LOG_LEVEL。
    set_log_level "$LOG_LEVEL"

    # 2. 配置日志文件
    if [[ "$LOG_TO_FILE" == "true" ]]; then
        LOG_FILE_PATH="$LOG_FILE" # 使用环境变量 LOG_FILE 或其默认值
        # 确保日志文件所在的目录存在。
        # 最佳实践：使用 mkdir -p 创建目录及其父目录（如果不存在）。
        # 最佳实践：添加错误处理，如果目录创建失败，则禁用文件日志记录。
        mkdir -p "$(dirname "$LOG_FILE_PATH")" || {
            log_error "无法创建日志目录: $(dirname "$LOG_FILE_PATH")，已禁用文件日志记录。"
            LOG_FILE_PATH="" # 清空路径以禁用文件日志
        }

        # 仅当日志文件路径有效（目录创建成功）时，才写入日志头信息。
        if [[ -n "$LOG_FILE_PATH" ]]; then
            # 最佳实践：在日志文件开头添加时间戳和元数据，方便追踪。
            # 使用 > 创建或覆盖日志文件，>> 追加内容。
            echo "===== 日志开始于 $(date) =====" > "$LOG_FILE_PATH"
            echo "===== 日志级别: $(get_log_level_name $CURRENT_LOG_LEVEL) =====" >> "$LOG_FILE_PATH"
            echo "===== 脚本名称: $(basename "$0") =====" >> "$LOG_FILE_PATH" # 新增：记录脚本基本名称
            echo "===== 进程 ID: $$ =====" >> "$LOG_FILE_PATH"              # 新增：记录脚本进程ID
            echo "===== 工作目录: $(pwd) =====" >> "$LOG_FILE_PATH"          # 新增：记录当前工作目录
            echo "===== 系统信息: $(uname -a) =====" >> "$LOG_FILE_PATH"
            # 最佳实践：仅当相关信息存在时才记录，避免空行或错误。
            # 例如，检查 REAL_USER 和 BACKUP_DIR 变量是否存在且非空。
            [[ -n "$REAL_USER" ]] && echo "===== 用户: $REAL_USER =====" >> "$LOG_FILE_PATH"
            [[ -n "$BACKUP_DIR" ]] && echo "===== 备份目录: $BACKUP_DIR =====" >> "$LOG_FILE_PATH"
            echo "" >> "$LOG_FILE_PATH" # 添加空行分隔头信息和日志内容
        fi
    else
        # 如果禁用了文件日志，确保 LOG_FILE_PATH 为空。
        LOG_FILE_PATH=""
    fi

    # 3. 输出初始化完成信息（如果日志级别允许 DEBUG）
    log_debug "日志系统初始化完成 (File logging: $LOG_TO_FILE, Path: ${LOG_FILE_PATH:-'N/A'})"
}

# 函数：check_log_file_rotation
# 功能：检查当前日志文件大小是否超过限制，如果超过则执行轮转。
# 轮转逻辑：
#   1. 删除最旧的日志文件 (e.g., script.log.5)
#   2. 将 script.log.4 重命名为 script.log.5, script.log.3 重命名为 script.log.4, ...
#   3. 将当前的 script.log 重命名为 script.log.1
#   4. 创建一个新的空的 script.log 文件并写入头信息。
# 最佳实践：将日志轮转逻辑封装在函数中。
# 最佳实践：在进行文件操作前检查文件是否存在。
check_log_file_rotation() {
    # 如果未启用文件日志或文件不存在，则直接返回。
    if [[ -z "$LOG_FILE_PATH" || ! -f "$LOG_FILE_PATH" ]]; then
        return
    fi

    # 获取当前日志文件大小。
    # 最佳实践：兼容不同的 stat 命令版本 (Linux vs macOS/BSD)。
    # 2>/dev/null 抑制错误输出（例如，如果文件在检查时被删除）。
    local file_size
    file_size=$(stat -c %s "$LOG_FILE_PATH" 2>/dev/null || stat -f %z "$LOG_FILE_PATH" 2>/dev/null)

    # 如果获取大小失败或文件大小未超过限制，则返回。
    if [[ -z "$file_size" || $file_size -le $LOG_FILE_MAX_SIZE ]]; then
        return
    fi

    # 文件大小超过限制，执行轮转。
    log_debug "日志文件大小($file_size bytes)超过限制($LOG_FILE_MAX_SIZE bytes)，进行轮转"

    # 1. 删除最旧的日志文件（如果存在）
    local oldest_log="${LOG_FILE_PATH}.${LOG_FILE_MAX_COUNT}"
    if [[ -f "$oldest_log" ]]; then
        rm -f "$oldest_log"
    fi

    # 2. 轮转现有的备份日志文件 (从 LOG_FILE_MAX_COUNT-1 到 1)
    local i
    for ((i = LOG_FILE_MAX_COUNT - 1; i >= 1; i--)); do
        local current_log="${LOG_FILE_PATH}.$i"
        local next_log="${LOG_FILE_PATH}.$((i + 1))"
        if [[ -f "$current_log" ]]; then
            mv "$current_log" "$next_log"
        fi
    done

    # 3. 将当前日志文件移动为 .1
    if [[ -f "$LOG_FILE_PATH" ]]; then # 再次检查，以防万一
        mv "$LOG_FILE_PATH" "${LOG_FILE_PATH}.1"
    fi

    # 4. 创建新的日志文件并写入头信息
    # 注意：这里不应再次调用 init_logging，只需创建新文件和写入必要的头信息。
    echo "===== 日志文件轮转于 $(date) =====" > "$LOG_FILE_PATH"
    echo "===== 日志级别: $(get_log_level_name $CURRENT_LOG_LEVEL) =====" >> "$LOG_FILE_PATH"
    echo "" >> "$LOG_FILE_PATH"

    log_debug "日志文件轮转完成"
}

# 函数：flush_log_buffer
# 功能：将日志缓冲区的内容强制写入日志文件。
#       在缓冲区满、脚本退出或需要确保日志立即写入时调用。
# 最佳实践：检查缓冲区和日志文件路径是否有效。
flush_log_buffer() {
    # 仅当缓冲区非空且文件日志已启用时才执行。
    if [[ -n "$LOG_BUFFER" && -n "$LOG_FILE_PATH" ]]; then
        # 使用 printf "%b" 可以解释缓冲区中的转义字符，如 \n。
        # 追加 (>>) 到日志文件。
        printf "%b" "$LOG_BUFFER" >> "$LOG_FILE_PATH"
        # 清空缓冲区并重置大小计数器。
        LOG_BUFFER=""
        LOG_BUFFER_SIZE=0
    fi
}

# 函数：add_to_log_buffer
# 功能：将单条日志条目添加到缓冲区。如果缓冲区已满，则先刷新缓冲区。
# 参数：$1 - 要添加的日志条目字符串（不含换行符）。
add_to_log_buffer() {
    local log_entry="$1"

    # 仅当启用了文件日志时才操作缓冲区。
    if [[ -n "$LOG_FILE_PATH" ]]; then
        # 将日志条目和换行符追加到缓冲区。
        LOG_BUFFER+="$log_entry\n"
        # 更新缓冲区大小计数器（估算）。
        # ${#log_entry} 获取字符串长度，+1 计算换行符。
        LOG_BUFFER_SIZE=$((LOG_BUFFER_SIZE + ${#log_entry} + 1))

        # 如果缓冲区大小达到或超过最大限制，刷新到文件。
        if [[ $LOG_BUFFER_SIZE -ge $LOG_BUFFER_MAX_SIZE ]]; then
            flush_log_buffer
        fi
    fi
}

# 函数：log_message (核心日志函数)
# 功能：根据指定的日志级别记录消息到控制台和/或日志文件（通过缓冲区）。
# 参数：
#   $1 - 日志级别数值。
#   $2 - 要记录的消息字符串。
# 最佳实践：这是所有特定级别日志函数（log_info, log_error 等）调用的核心实现。
# 最佳实践：使用 date 命令获取标准格式的时间戳。
# 最佳实践：根据 VERBOSE 设置和日志级别决定是否包含调用者信息。
log_message() {
    local level=$1
    local message="$2"
    # 检查日志级别是否低于当前设置的级别。如果低于，则不记录。
    if [[ $level -lt $CURRENT_LOG_LEVEL ]]; then
        return # 不记录低于当前级别的消息
    fi

    # 获取通用信息
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S") # 标准时间戳格式
    local level_name
    level_name=$(get_log_level_name "$level")
    local level_color
    level_color=$(get_log_level_color "$level")
    local caller_info=""

    # 获取调用者信息（如果 VERBOSE=true 且级别为 DEBUG 或 TRACE）
    # FUNCNAME[2] 获取调用 log_message 的函数名 (e.g., log_debug)
    # BASH_LINENO[1] 获取调用 log_message 的行号
    # :-"main" 和 :-"?" 提供默认值，以防在顶层调用或信息不可用。
    if [[ "$VERBOSE" == "true" && $level -le $LOG_LEVEL_DEBUG ]]; then
        local caller_func=${FUNCNAME[2]:-"main"}
        local caller_line=${BASH_LINENO[1]:-"?"}
        caller_info=" (${caller_func}:${caller_line})" # 格式化调用者信息
    fi

    # --- 控制台输出 ---
    # 最佳实践：使用 echo -e 启用转义序列（如颜色代码）。
    # 最佳实践：在彩色输出中，使用 COLOR_RESET 确保后续文本不受影响。
    # 最佳实践：使用粗体强调日志级别，提高可读性。
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        echo -e "${COLOR_BOLD}${level_color}[${level_name}]${COLOR_RESET} [${timestamp}]${caller_info} ${level_color}${message}${COLOR_RESET}"
    else
        echo "[${level_name}] [${timestamp}]${caller_info} ${message}"
    fi

    # --- 文件输出 (通过缓冲区) ---
    if [[ -n "$LOG_FILE_PATH" ]]; then
        # 构建用于文件的日志条目（无颜色代码）。
        local log_entry="[${level_name}] [${timestamp}]${caller_info} ${message}"
        add_to_log_buffer "$log_entry"

        # 每次记录后检查是否需要轮转（因为 add_to_log_buffer 可能已刷新缓冲区并写入文件）。
        # 这确保日志文件不会无限增长。
        check_log_file_rotation
    fi
}

# --- 特定级别的日志函数 ---
# 最佳实践：提供易于使用的包装函数，隐藏 log_message 的复杂性。
# 这些函数使得调用者只需提供消息即可。
log_trace() {
    log_message $LOG_LEVEL_TRACE "$1"
}

log_debug() {
    log_message $LOG_LEVEL_DEBUG "$1"
}

log_info() {
    log_message $LOG_LEVEL_INFO "$1"
}

log_notice() {
    log_message $LOG_LEVEL_NOTICE "$1"
}

log_warn() {
    log_message $LOG_LEVEL_WARN "$1"
}

log_error() {
    log_message $LOG_LEVEL_ERROR "$1"
}

log_critical() {
    log_message $LOG_LEVEL_CRITICAL "$1"
}

log_fatal() {
    log_message $LOG_LEVEL_FATAL "$1"
}

# --- 带格式化的日志函数 ---

# 函数：log_format (核心格式化日志函数)
# 功能：类似于 log_message，但接受 printf 格式字符串和参数。
# 参数：
#   $1 - 日志级别数值。
#   $2 - printf 格式字符串。
#   $@ - 传递给 printf 的参数 (从第三个参数开始)。
# 最佳实践：使用 printf 进行安全的格式化输出，避免潜在的代码注入风险。
# 最佳实践：使用 shift 命令处理函数参数。
log_format() {
    local level=$1
    local format="$2"
    shift 2 # 移除前两个参数 (level 和 format)
    # 使用 printf 将格式字符串和剩余参数组合成最终的消息。
    # 使用 local message=$(...) 捕获 printf 的输出。
    local message
    message=$(printf "$format" "$@")
    # 调用核心 log_message 函数记录格式化后的消息。
    log_message "$level" "$message"
}

# --- 特定级别的格式化日志函数 ---
# 最佳实践：提供易于使用的格式化日志包装函数。
log_trace_format() {
    local format="$1"
    shift # 移除 format 参数
    log_format $LOG_LEVEL_TRACE "$format" "$@"
}

log_debug_format() {
    local format="$1"
    shift
    log_format $LOG_LEVEL_DEBUG "$format" "$@"
}

log_info_format() {
    local format="$1"
    shift
    log_format $LOG_LEVEL_INFO "$format" "$@"
}

log_notice_format() {
    local format="$1"
    shift
    log_format $LOG_LEVEL_NOTICE "$format" "$@"
}

log_warn_format() {
    local format="$1"
    shift
    log_format $LOG_LEVEL_WARN "$format" "$@"
}

log_error_format() {
    local format="$1"
    shift
    log_format $LOG_LEVEL_ERROR "$format" "$@"
}

log_critical_format() {
    local format="$1"
    shift
    log_format $LOG_LEVEL_CRITICAL "$format" "$@"
}

log_fatal_format() {
    local format="$1"
    shift
    log_format $LOG_LEVEL_FATAL "$format" "$@"
}

# 函数：log_section
# 功能：在控制台和日志文件中输出一个带有标题的分隔线，用于组织日志输出。
# 参数：
#   $1 - 分隔线的标题字符串。
#   $2 - (可选) 日志级别，默认为 INFO。
# 最佳实践：使日志输出更结构化，易于阅读。
# 最佳实践：计算填充以使分隔线居中对齐。
log_section() {
    local title="$1"
    # 使用 :- 操作符设置默认日志级别为 INFO。
    local level=${2:-$LOG_LEVEL_INFO}
    # 检查日志级别是否低于当前设置的级别。
    if [[ $level -lt $CURRENT_LOG_LEVEL ]]; then
        return
    fi

    local width=60 # 分隔线的目标宽度
    local title_len=${#title}
    # 计算两侧填充的字符数。-4 是为了减去 " ## " 或 " ★ ★ " 的长度。
    local padding=$(( (width - title_len - 4) / 2 ))
    # 确保填充数不为负（如果标题过长）。
    [[ $padding -lt 0 ]] && padding=0

    local plain_line=""   # 用于日志文件的纯文本分隔线
    local colored_line="" # 用于控制台的彩色分隔线
    local level_name
    level_name=$(get_log_level_name "$level")
    local timestamp
    timestamp=$(date "+%Y-%m-%d %H:%M:%S")

    # --- 构建纯文本分隔线 ---
    local i
    for ((i=0; i<padding; i++)); do plain_line+="="; done
    plain_line+=" ## $title ## "
    for ((i=0; i<padding; i++)); do plain_line+="="; done
    # 如果计算出的长度不足，补齐 '=' 到目标宽度。
    while [[ ${#plain_line} -lt $width ]]; do plain_line+="="; done

    # --- 构建彩色分隔线 (如果启用) ---
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        local level_color
        level_color=$(get_log_level_color "$level")
        colored_line+="${COLOR_BOLD}${level_color}" # 使用级别颜色和粗体
        for ((i=0; i<padding; i++)); do colored_line+="━"; done # 使用特殊字符
        colored_line+=" ★ $title ★ " # 使用特殊字符包围标题
        for ((i=0; i<padding; i++)); do colored_line+="━"; done
        # 估算颜色代码的长度，并补齐 '━' 以接近目标宽度。
        # 注意：ANSI代码不占显示宽度，精确对齐比较困难。
        local approx_color_len=${#COLOR_BOLD}+${#level_color}+${#COLOR_RESET}
        while [[ ${#colored_line} -lt $width+$approx_color_len ]]; do colored_line+="━"; done
        colored_line+="${COLOR_RESET}" # 重置颜色
    fi

    # --- 输出 ---
    # 控制台输出 (添加空行以提高可读性)
    echo "" # 前导空行
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        echo -e "$colored_line"
    else
        echo "$plain_line"
    fi
    echo "" # 后续空行

    # 文件输出 (总是使用纯文本，通过缓冲区)
    if [[ -n "$LOG_FILE_PATH" ]]; then
        # 文件日志中包含级别和时间戳。
        local log_entry="[${level_name}] [${timestamp}] ${plain_line}" # 不包含 caller_info
        add_to_log_buffer "$log_entry"
        # 检查轮转，因为 add_to_log_buffer 可能触发 flush_log_buffer。
        check_log_file_rotation
    fi
}

# 函数：finalize_logging
# 功能：在脚本退出前执行清理工作，主要是确保日志缓冲区被刷新到文件。
# 最佳实践：使用 trap 命令注册此函数，确保在脚本正常退出或被信号中断时都能执行。
finalize_logging() {
    # 强制刷新缓冲区，确保所有待处理的日志都写入文件。
    flush_log_buffer

    # 在日志文件末尾添加结束标记（如果启用了文件日志）。
    if [[ -n "$LOG_FILE_PATH" ]]; then
        # 检查文件是否存在，以防在脚本执行期间被删除。
        if [[ -f "$LOG_FILE_PATH" ]]; then
             echo "" >> "$LOG_FILE_PATH" # 添加空行
             echo "===== 日志结束于 $(date) =====" >> "$LOG_FILE_PATH"
        fi
    fi
}

# 注册退出处理函数
# 最佳实践：使用 trap 命令捕获 EXIT 信号（脚本正常或异常退出时触发）。
# 这确保 finalize_logging 总会被调用，防止日志丢失。
trap finalize_logging EXIT

#############################################################
# 进度显示相关功能
# 提供在长时间运行的任务中向用户显示进度的能力。
#############################################################

# 函数：format_time
# 功能：将秒数格式化为 HH:MM:SS 或 MM:SS 的可读格式。
# 参数：$1 - 总秒数。
# 返回：格式化后的时间字符串。
# 最佳实践：使用 printf 进行格式化，确保输出宽度一致（例如 %02d）。
format_time() {
    local seconds=$1
    # 防止负数或非数字输入导致错误
    if ! [[ "$seconds" =~ ^[0-9]+$ ]]; then
        echo "N/A"
        return
    fi
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))

    if [[ $hours -gt 0 ]]; then
        printf "%02d:%02d:%02d" "$hours" "$minutes" "$secs"
    else
        printf "%02d:%02d" "$minutes" "$secs"
    fi
}

# 函数：show_progress_bar (内部函数)
# 功能：显示一个基于字符的进度条。
# 参数：
#   $1 - 当前进度值。
#   $2 - 总进度值。
#   $3 - (可选) 任务描述字符串。
#   $4 - (可选) 附加信息字符串 (e.g., ETA)。
# 最佳实践：使用 \r (回车符) 和 \033[K (清除到行尾) 来在同一行更新进度条，避免滚动屏幕。
# 最佳实践：在彩色输出中使用不同的颜色和字符增强视觉效果。
# 最佳实践：在任务开始和结束时添加空行和分隔符，区分不同的进度条。
show_progress_bar() {
    local current=$1
    local total=$2
    local description="${3:-}" # 使用默认空字符串
    local extra_info="${4:-}"  # 使用默认空字符串
    local width=50 # 进度条宽度

    # 防止除以零错误
    if [[ $total -eq 0 ]]; then
        percentage=0
        completed=0
    else
        # 使用整数运算计算百分比和完成的字符数
        percentage=$((current * 100 / total))
        completed=$((width * current / total))
    fi
    local remaining=$((width - completed))

    # 在第一个进度更新时（current=1 或 0）打印任务开始的分隔线
    if [[ $current -le 1 ]]; then
        echo "" # 前导空行
        if [[ -n "$description" ]]; then # 仅当有描述时打印开始信息
             if [[ "$COLOR_OUTPUT" == "true" ]]; then
                 echo -e "${COLOR_BOLD}${COLOR_BG_CYAN} 开始 ${COLOR_RESET} ${COLOR_BOLD}${COLOR_CYAN}$description${COLOR_RESET}"
             else
                 echo "[开始] $description"
             fi
        fi
        # 打印分隔线
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            echo -e "${COLOR_CYAN}----------------------------------------------------------${COLOR_RESET}"
        else
            echo "----------------------------------------------------------"
        fi
    fi

    # 构建进度条字符串
    local progress=""

    # 添加任务描述（如果提供）
    if [[ -n "$description" ]]; then
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            progress+="${COLOR_BOLD}${COLOR_CYAN}$description${COLOR_RESET}: "
        else
            progress+="[$description]: "
        fi
    fi

    # 添加百分比
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        local percent_color="$COLOR_GREEN" # 默认绿色
        if [[ $percentage -lt 30 ]]; then percent_color="$COLOR_RED";
        elif [[ $percentage -lt 70 ]]; then percent_color="$COLOR_YELLOW"; fi
        progress+="${COLOR_BOLD}${percent_color}${percentage}%${COLOR_RESET} "
    else
        progress+="${percentage}% "
    fi

    # 添加附加信息（如果提供）
    if [[ -n "$extra_info" ]]; then
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            progress+="${COLOR_CYAN}[$extra_info]${COLOR_RESET} "
        else
            progress+="[$extra_info] "
        fi
    fi

    # 构建进度条主体
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        progress+="${COLOR_BOLD}[" # 左边界
        local bar_color="$COLOR_GREEN" # 默认绿色
        if [[ $percentage -lt 30 ]]; then bar_color="$COLOR_RED";
        elif [[ $percentage -lt 70 ]]; then bar_color="$COLOR_YELLOW"; fi

        progress+="$bar_color" # 设置进度条颜色
        local i
        for ((i=0; i<completed; i++)); do progress+=">"; done # 已完成部分
        if [[ $completed -lt $width ]]; then
            progress+=">${COLOR_RESET}" # 当前位置指示器，然后重置颜色
            for ((i=0; i<remaining-1; i++)); do progress+="."; done # 剩余部分
        else
             progress+="${COLOR_RESET}" # 如果已满，在末尾重置颜色
        fi
        progress+="${COLOR_BOLD}]${COLOR_RESET}" # 右边界
    else
        # 非彩色版本
        progress+="["
        local i
        for ((i=0; i<completed; i++)); do progress+=">"; done
        if [[ $completed -lt $width ]]; then
            progress+=">"
            for ((i=0; i<remaining-1; i++)); do progress+=" "; done # 使用空格表示剩余
        fi
        progress+="]"
    fi

    # 清除当前行 (\033[K) 并打印进度条 (\r 回到行首)
    echo -ne "\r\033[K${progress}"

    # 如果任务完成 (current == total)
    if [[ $current -eq $total ]]; then
        echo "" # 换行，结束进度条更新
        if [[ -n "$description" ]]; then # 仅当有描述时打印完成信息
            if [[ "$COLOR_OUTPUT" == "true" ]]; then
                echo -e "${COLOR_BOLD}${COLOR_BG_GREEN} 完成 ${COLOR_RESET} ${COLOR_BOLD}${COLOR_GREEN}$description${COLOR_RESET} ${COLOR_CYAN}($(date +"%H:%M:%S"))${COLOR_RESET}"
                # 添加分隔线
                echo -e "${COLOR_CYAN}----------------------------------------------------------${COLOR_RESET}"
            else
                echo "[完成] $description ($(date +"%H:%M:%S"))"
                echo "----------------------------------------------------------"
            fi
        fi
         echo "" # 完成后添加额外空行
    fi
}

# 函数：show_progress_percent (内部函数)
# 功能：仅显示百分比进度。
# 参数：(同 show_progress_bar)
# 最佳实践：提供一种更简洁的进度显示方式。
show_progress_percent() {
    local current=$1
    local total=$2
    local description="${3:-}"
    local extra_info="${4:-}"

    # 防止除以零错误
    if [[ $total -eq 0 ]]; then
        percentage=0
    else
        percentage=$((current * 100 / total))
    fi

    # 在第一个进度更新时打印任务开始的分隔线
    if [[ $current -le 1 ]]; then
        echo "" # 前导空行
         if [[ -n "$description" ]]; then # 仅当有描述时打印开始信息
             if [[ "$COLOR_OUTPUT" == "true" ]]; then
                 echo -e "${COLOR_BOLD}${COLOR_BG_PURPLE} 进度 ${COLOR_RESET} ${COLOR_BOLD}${COLOR_LIGHT_PURPLE}$description${COLOR_RESET}"
             else
                 echo "[进度] $description"
             fi
         fi
        # 打印分隔线
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            echo -e "${COLOR_PURPLE}----------------------------------------------------------${COLOR_RESET}"
        else
            echo "----------------------------------------------------------"
        fi
    fi

    # 构建进度字符串
    local progress=""

    # 添加任务描述
    if [[ -n "$description" ]]; then
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            progress+="${COLOR_BOLD}${COLOR_LIGHT_PURPLE}$description${COLOR_RESET}: "
        else
            progress+="[$description]: "
        fi
    fi

    # 添加百分比
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        local percent_color="$COLOR_GREEN"
        if [[ $percentage -lt 30 ]]; then percent_color="$COLOR_RED";
        elif [[ $percentage -lt 70 ]]; then percent_color="$COLOR_YELLOW"; fi
        progress+="${COLOR_BOLD}${percent_color}${percentage}%${COLOR_RESET}"
    else
        progress+="${percentage}%"
    fi

    # 添加附加信息
    if [[ -n "$extra_info" ]]; then
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            progress+=" ${COLOR_CYAN}[$extra_info]${COLOR_RESET}"
        else
            progress+=" [$extra_info]"
        fi
    fi

    # 清除行并打印
    echo -ne "\r\033[K${progress}"

    # 如果完成
    if [[ $current -eq $total ]]; then
        echo "" # 换行
        if [[ -n "$description" ]]; then
            if [[ "$COLOR_OUTPUT" == "true" ]]; then
                echo -e "${COLOR_BOLD}${COLOR_BG_GREEN} 完成 ${COLOR_RESET} ${COLOR_BOLD}${COLOR_GREEN}$description${COLOR_RESET} ${COLOR_CYAN}($(date +"%H:%M:%S"))${COLOR_RESET}"
                echo -e "${COLOR_CYAN}----------------------------------------------------------${COLOR_RESET}"
            else
                echo "[完成] $description ($(date +"%H:%M:%S"))"
                echo "----------------------------------------------------------"
            fi
        fi
        echo "" # 完成后添加额外空行
    fi
}

# 函数：show_progress (公共接口)
# 功能：根据全局配置 SHOW_PROGRESS 和 PROGRESS_TYPE 调用相应的内部进度显示函数。
# 参数：(同 show_progress_bar / show_progress_percent)
# 最佳实践：提供统一的公共接口来调用进度显示。
show_progress() {
    # 如果全局禁用了进度显示，则直接返回。
    if [[ "$SHOW_PROGRESS" != "true" ]]; then
        return
    fi

    local current=$1
    local total=$2
    local description="${3:-}"
    local extra_info="${4:-}"

    # 再次检查 total 是否为 0，避免后续错误。
    if [[ $total -eq 0 ]]; then
        # 可以考虑记录一个警告或调试信息
        # log_warn "show_progress called with total=0 for description: $description"
        return
    fi

    # 根据全局配置 PROGRESS_TYPE 选择调用哪个内部函数。
    if [[ "$PROGRESS_TYPE" == "bar" ]]; then
        show_progress_bar "$current" "$total" "$description" "$extra_info"
    else # 默认为 percent 或任何非 "bar" 的值
        show_progress_percent "$current" "$total" "$description" "$extra_info"
    fi
}

# 函数：show_progress_with_eta (公共接口)
# 功能：显示进度（条形或百分比），并计算和显示估计剩余时间 (ETA)。
# 参数：
#   $1 - 当前进度值。
#   $2 - 总进度值。
#   $3 - (可选) 任务描述字符串。
#   $4 - 任务开始时间的时间戳 (通过 date +%s 获取)。
# 依赖：需要 bc 命令来进行浮点数运算以计算 ETA。
# 最佳实践：在计算 ETA 前检查 bc 命令是否存在。
# 最佳实践：处理 current=0 的情况（无法计算速率）。
show_progress_with_eta() {
    # 如果全局禁用了进度显示，则直接返回。
    if [[ "$SHOW_PROGRESS" != "true" ]]; then
        return
    fi

    local current=$1
    local total=$2
    local description="${3:-}"
    local start_time=$4

    # 检查 total 和 start_time 是否有效
    if [[ $total -eq 0 ]]; then
        # log_warn "show_progress_with_eta called with total=0 for description: $description"
        return
    fi
    if ! [[ "$start_time" =~ ^[0-9]+$ ]]; then
         log_error "show_progress_with_eta 需要有效的开始时间戳 (第四个参数)"
         return
    fi


    # 计算已用时间
    local current_time
    current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    local elapsed_formatted
    elapsed_formatted=$(format_time "$elapsed")
    local eta_formatted="计算中..." # 默认 ETA

    # 计算 ETA (需要 bc)
    if command -v bc &> /dev/null; then
        if [[ $current -gt 0 ]]; then
            # 使用 bc 进行浮点数计算：rate = elapsed / current
            # remaining_seconds = rate * (total - current)
            # scale=4 设置小数位数以提高精度
            local rate remaining_seconds
            # 添加错误处理，以防 bc 计算出错
            rate=$(echo "scale=4; $elapsed / $current" | bc 2>/dev/null)
            if [[ -n "$rate" ]]; then
                 remaining_seconds=$(echo "scale=4; $rate * ($total - $current)" | bc 2>/dev/null)
                 if [[ -n "$remaining_seconds" ]]; then
                     # 将结果转换为整数秒
                     remaining_seconds=${remaining_seconds%.*}
                     if [[ $remaining_seconds -gt 0 ]]; then
                         eta_formatted=$(format_time "$remaining_seconds")
                     else
                         # 如果剩余时间小于1秒或为0，显示 "即将完成"
                         eta_formatted="< 1s"
                     fi
                 else
                      eta_formatted="ETA计算错误"
                 fi
            else
                 eta_formatted="速率计算错误"
            fi
        else
            # 如果 current 为 0，无法计算速率
            eta_formatted="未知"
        fi
    else
        # 如果 bc 命令不存在
        eta_formatted="N/A (需要 bc)"
    fi

    # 构建附加信息字符串
    local extra_info="已用:${elapsed_formatted} 剩余:${eta_formatted}"

    # 调用通用的 show_progress 函数来显示进度条/百分比和附加信息
    show_progress "$current" "$total" "$description" "$extra_info"
}

# 函数：reset_retry_counter (示例，当前未在日志模块中使用)
# 功能：重置一个假设存在的重试计数器。
# 注意：这个函数似乎与日志模块本身关系不大，可能是其他脚本逻辑的一部分。
#      如果不需要，可以考虑移除。
reset_retry_counter() {
    # 假设存在一个名为 CURRENT_RETRY 的全局变量
    CURRENT_RETRY=0
    log_debug "重试计数器已重置" # 添加日志记录
}

# --- 日志系统初始化调用 ---
# 最佳实践：在脚本主体开始执行实际任务之前调用初始化函数。
# init_logging # 取消注释此行以在 source 时自动初始化，或者在主脚本中显式调用。
# 注意：如果此脚本旨在被其他脚本 source，通常不在被 source 的脚本中直接调用初始化。
#       而是在 source 它的主脚本中调用 init_logging。
#       如果这是一个独立运行的脚本，则应在此处调用 init_logging。

# --- 脚本结束 ---
# trap EXIT 会自动调用 finalize_logging

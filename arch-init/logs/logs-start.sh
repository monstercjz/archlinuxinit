#!/bin/bash

#############################################################
# 增强日志模块
# 功能：提供更细粒度的日志记录、控制台输出展示和进度显示功能
#############################################################

# 日志级别定义
LOG_LEVEL_TRACE=0    # 最详细的跟踪信息
LOG_LEVEL_DEBUG=1    # 调试信息
LOG_LEVEL_INFO=2     # 一般信息
LOG_LEVEL_NOTICE=3   # 重要提示信息
LOG_LEVEL_WARN=4     # 警告信息
LOG_LEVEL_ERROR=5    # 错误信息
LOG_LEVEL_CRITICAL=6 # 严重错误信息
LOG_LEVEL_FATAL=7    # 致命错误信息

# 当前日志级别（默认为INFO）
CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO

# 定义颜色代码（如果启用彩色输出）
if [[ "$COLOR_OUTPUT" == "true" ]]; then
    # 前景色
    COLOR_RED="\033[0;31m"          # 红色 - 错误
    COLOR_LIGHT_RED="\033[1;31m"    # 亮红色 - 严重错误
    COLOR_GREEN="\033[0;32m"        # 绿色 - 信息
    COLOR_LIGHT_GREEN="\033[1;32m"  # 亮绿色 - 成功
    COLOR_YELLOW="\033[0;33m"       # 黄色 - 警告
    COLOR_LIGHT_YELLOW="\033[1;33m" # 亮黄色 - 提示
    COLOR_BLUE="\033[0;34m"         # 蓝色 - 调试
    COLOR_LIGHT_BLUE="\033[1;34m"   # 亮蓝色 - 跟踪
    COLOR_PURPLE="\033[0;35m"       # 紫色
    COLOR_LIGHT_PURPLE="\033[1;35m" # 亮紫色 - 致命错误
    COLOR_CYAN="\033[0;36m"         # 青色
    COLOR_LIGHT_CYAN="\033[1;36m"   # 亮青色 - 通知
    COLOR_GRAY="\033[0;37m"         # 灰色
    COLOR_WHITE="\033[1;37m"        # 白色
    
    # 背景色
    COLOR_BG_RED="\033[41m"
    COLOR_BG_GREEN="\033[42m"
    COLOR_BG_YELLOW="\033[43m"
    COLOR_BG_BLUE="\033[44m"
    COLOR_BG_PURPLE="\033[45m"
    COLOR_BG_CYAN="\033[46m"
    COLOR_BG_WHITE="\033[47m"
    
    # 文本样式
    COLOR_BOLD="\033[1m"            # 粗体
    COLOR_UNDERLINE="\033[4m"       # 下划线
    COLOR_RESET="\033[0m"           # 重置
else
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

# 日志文件路径
LOG_FILE_PATH=""

# 日志文件最大大小（默认10MB）
LOG_FILE_MAX_SIZE=10485760

# 日志文件最大数量（默认5个）
LOG_FILE_MAX_COUNT=5

# 日志缓冲区（用于批量写入文件，减少IO操作）
LOG_BUFFER=""
LOG_BUFFER_SIZE=0
LOG_BUFFER_MAX_SIZE=1024 # 1KB

# 设置日志级别
set_log_level() {
    local level="$1"
    case "${level^^}" in
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
        "WARN"|"WARNING")
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
            echo "未知的日志级别: $level，使用默认级别 INFO"
            CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO
            ;;
    esac
    
    log_info "日志级别设置为: ${level^^}"
}

# 获取日志级别名称
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

# 获取日志级别颜色
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
            echo "$COLOR_RESET"
            ;;
    esac
}

# 初始化日志系统
init_logging() {
    # 根据配置设置日志级别
    if [[ -n "$LOG_LEVEL" ]]; then
        set_log_level "$LOG_LEVEL"
    fi
    
    # 设置日志文件路径
    if [[ "$LOG_TO_FILE" == "true" && -n "$LOG_FILE" ]]; then
        LOG_FILE_PATH="$LOG_FILE"
        # 确保日志目录存在
        mkdir -p "$(dirname "$LOG_FILE_PATH")"
        # 创建日志文件并写入头部信息
        echo "===== 备份日志开始于 $(date) =====" > "$LOG_FILE_PATH"
        echo "===== 日志级别: $(get_log_level_name $CURRENT_LOG_LEVEL) =====" >> "$LOG_FILE_PATH"
        echo "===== 系统信息: $(uname -a) =====" >> "$LOG_FILE_PATH"
        echo "===== 用户: $REAL_USER =====" >> "$LOG_FILE_PATH"
        echo "===== 备份目录: $BACKUP_DIR =====" >> "$LOG_FILE_PATH"
        echo "" >> "$LOG_FILE_PATH"
    fi
    
    # 输出日志系统初始化信息
    log_debug "日志系统初始化完成"
}

# 检查日志文件大小并进行轮转
check_log_file_rotation() {
    # 如果未启用日志文件，直接返回
    if [[ -z "$LOG_FILE_PATH" || ! -f "$LOG_FILE_PATH" ]]; then
        return
    fi
    
    # 获取当前日志文件大小
    local file_size=$(stat -c %s "$LOG_FILE_PATH" 2>/dev/null || stat -f %z "$LOG_FILE_PATH" 2>/dev/null)
    
    # 如果文件大小超过最大限制，进行轮转
    if [[ $file_size -gt $LOG_FILE_MAX_SIZE ]]; then
        log_debug "日志文件大小($file_size)超过限制($LOG_FILE_MAX_SIZE)，进行轮转"
        
        # 删除最旧的日志文件（如果存在）
        if [[ -f "${LOG_FILE_PATH}.${LOG_FILE_MAX_COUNT}" ]]; then
            rm -f "${LOG_FILE_PATH}.${LOG_FILE_MAX_COUNT}"
        fi
        
        # 轮转现有的日志文件
        for ((i=LOG_FILE_MAX_COUNT-1; i>=1; i--)); do
            local j=$((i+1))
            if [[ -f "${LOG_FILE_PATH}.$i" ]]; then
                mv "${LOG_FILE_PATH}.$i" "${LOG_FILE_PATH}.$j"
            fi
        done
        
        # 将当前日志文件移动为.1
        mv "$LOG_FILE_PATH" "${LOG_FILE_PATH}.1"
        
        # 创建新的日志文件
        echo "===== 日志文件轮转于 $(date) =====" > "$LOG_FILE_PATH"
        echo "===== 日志级别: $(get_log_level_name $CURRENT_LOG_LEVEL) =====" >> "$LOG_FILE_PATH"
        echo "" >> "$LOG_FILE_PATH"
        
        log_debug "日志文件轮转完成"
    fi
}

# 刷新日志缓冲区到文件
flush_log_buffer() {
    if [[ -n "$LOG_BUFFER" && -n "$LOG_FILE_PATH" ]]; then
        echo -n "$LOG_BUFFER" >> "$LOG_FILE_PATH"
        LOG_BUFFER=""
        LOG_BUFFER_SIZE=0
    fi
}

# 添加日志到缓冲区
add_to_log_buffer() {
    local log_entry="$1"
    
    if [[ -n "$LOG_FILE_PATH" ]]; then
        # 添加到缓冲区
        LOG_BUFFER+="$log_entry\n"
        LOG_BUFFER_SIZE=$((LOG_BUFFER_SIZE + ${#log_entry} + 1))
        
        # 如果缓冲区大小超过最大限制，刷新到文件
        if [[ $LOG_BUFFER_SIZE -ge $LOG_BUFFER_MAX_SIZE ]]; then
            flush_log_buffer
        fi
    fi
}

# 通用日志函数
log_message() {
    local level=$1
    local message="$2"
    local timestamp=$(date "+%Y-%m-%d %H:%M:%S")
    local level_name=$(get_log_level_name $level)
    local level_color=$(get_log_level_color $level)
    local caller_info=""
    
    # 如果是调试或跟踪级别，添加调用者信息
    if [[ $level -le $LOG_LEVEL_DEBUG && "$VERBOSE" == "true" ]]; then
        # 获取调用者信息（函数名和行号）
        local caller_func=${FUNCNAME[2]:-"main"}
        local caller_line=${BASH_LINENO[1]:-"?"}
        caller_info=" ($caller_func:$caller_line)"
    fi
    
    if [[ $CURRENT_LOG_LEVEL -le $level ]]; then
        # 控制台输出
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            # 增强视觉区分度，使用粗体显示日志级别
            echo -e "${COLOR_BOLD}${level_color}[${level_name}]${COLOR_RESET} [${timestamp}]${caller_info} ${level_color}$message${COLOR_RESET}"
        else
            echo "[${level_name}] [${timestamp}]${caller_info} $message"
        fi
        
        # 文件输出
        if [[ -n "$LOG_FILE_PATH" ]]; then
            local log_entry="[${level_name}] [${timestamp}]${caller_info} $message"
            add_to_log_buffer "$log_entry"
            
            # 检查是否需要轮转日志文件
            check_log_file_rotation
        fi
    fi
}

# 各级别日志函数
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

# 带有格式化的日志函数
log_format() {
    local level=$1
    local format="$2"
    shift 2
    local message=$(printf "$format" "$@")
    log_message $level "$message"
}

# 带有格式化的各级别日志函数
log_trace_format() {
    local format="$1"
    shift
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

# 显示带有标题的分隔线
log_section() {
    local title="$1"
    local level=${2:-$LOG_LEVEL_INFO}
    local width=60
    local title_len=${#title}
    local padding=$(( (width - title_len - 4) / 2 ))
    local line=""
    local level_color=$(get_log_level_color $level)
    
    # 构建分隔线
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        # 彩色版本，使用不同符号增强视觉效果
        line+="${COLOR_BOLD}${level_color}"
        
        for ((i=0; i<padding; i++)); do
            line+="━"
        done
        
        line+=" ★ $title ★ "
        
        for ((i=0; i<padding; i++)); do
            line+="━"
        done
        
        # 如果总长度不足width，补充=
        while [[ ${#line} -lt $width+${#COLOR_BOLD}+${#level_color} ]]; do
            line+="━"
        done
        
        line+="${COLOR_RESET}"
    else
        # 无彩色版本
        for ((i=0; i<padding; i++)); do
            line+="="
        done
        
        line+=" ## $title ## "
        
        for ((i=0; i<padding; i++)); do
            line+="="
        done
        
        # 如果总长度不足width，补充=
        while [[ ${#line} -lt $width ]]; do
            line+="="
        done
    fi
    
    # 添加空行增强可读性
    echo ""
    log_message $level "$line"
    echo ""
}

# 在脚本结束时刷新日志缓冲区
finalize_logging() {
    flush_log_buffer
    
    if [[ -n "$LOG_FILE_PATH" ]]; then
        echo "" >> "$LOG_FILE_PATH"
        echo "===== 备份日志结束于 $(date) =====" >> "$LOG_FILE_PATH"
    fi
}

# 注册退出处理函数，确保日志缓冲区被刷新
trap finalize_logging EXIT

#############################################################
# 进度显示相关功能
#############################################################

# 格式化时间（秒转为可读格式）
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    
    if [[ $hours -gt 0 ]]; then
        printf "%02d:%02d:%02d" $hours $minutes $secs
    else
        printf "%02d:%02d" $minutes $secs
    fi
}

# 显示进度条 - 增强版，避免多个进度条模糊在一起
show_progress_bar() {
    local current=$1
    local total=$2
    local description=$3
    local extra_info=$4
    local width=50
    local percentage=$((current * 100 / total))
    local completed=$((width * current / total))
    local remaining=$((width - completed))
    
    # 在每个新任务前添加空行和分隔线，避免进度条模糊在一起
    if [[ $current -eq 1 || $current -eq 0 ]]; then
        echo ""
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            echo -e "${COLOR_CYAN}▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁${COLOR_RESET}"
        else
            echo "----------------------------------------------------------"
        fi
    fi
    
    # 构建进度条
    local progress=""
    
    # 添加任务标识符和描述信息（如果有）
    if [[ -n "$description" ]]; then
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            # 添加任务标识符，使用不同背景色增强区分度
            progress="${COLOR_BOLD}${COLOR_BG_BLUE} 任务 ${COLOR_RESET} ${COLOR_BOLD}${COLOR_CYAN}$description${COLOR_RESET}: "
        else
            progress="[任务] $description: "
        fi
    fi
    
    # 添加百分比和额外信息
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        # 根据进度选择颜色
        if [[ $percentage -lt 30 ]]; then
            progress+="${COLOR_BOLD}${COLOR_RED}"
        elif [[ $percentage -lt 70 ]]; then
            progress+="${COLOR_BOLD}${COLOR_YELLOW}"
        else
            progress+="${COLOR_BOLD}${COLOR_GREEN}"
        fi
        progress+="$percentage%${COLOR_RESET} "
    else
        progress+="$percentage% "
    fi
    
    # 添加额外信息（如果有）
    if [[ -n "$extra_info" ]]; then
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            progress+="${COLOR_CYAN}[$extra_info]${COLOR_RESET} "
        else
            progress+="[$extra_info] "
        fi
    fi
    
    # 使用彩色输出（如果启用）
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        # 添加进度条左边界
        progress+="${COLOR_BOLD}[${COLOR_RESET}"
        
        # 已完成部分（根据进度选择颜色）
        if [[ $completed -gt 0 ]]; then
            if [[ $percentage -lt 30 ]]; then
                progress+="${COLOR_RED}"
            elif [[ $percentage -lt 70 ]]; then
                progress+="${COLOR_YELLOW}"
            else
                progress+="${COLOR_GREEN}"
            fi
            
            for ((i=0; i<completed; i++)); do
                progress+=" >" # 使用>符号代替实心方块，添加空格提高可读性
            done
            progress+="${COLOR_RESET}"
        fi
        
        # 当前位置指示器
        if [[ $completed -lt $width ]]; then
            if [[ $percentage -lt 30 ]]; then
                progress+="${COLOR_RED}>${COLOR_RESET}"
            elif [[ $percentage -lt 70 ]]; then
                progress+="${COLOR_YELLOW}>${COLOR_RESET}"
            else
                progress+="${COLOR_GREEN}>${COLOR_RESET}"
            fi
            
            # 剩余部分
            for ((i=0; i<remaining-1; i++)); do
                progress+=" ." # 使用.符号代替空心方块，添加空格提高可读性
            done
        fi
        
        # 添加进度条右边界
        progress+="${COLOR_BOLD}]${COLOR_RESET}"
    else
        # 无彩色版本
        progress+="["
        for ((i=0; i<completed; i++)); do
            progress+="="
        done
        
        if [[ $completed -lt $width ]]; then
            progress+=">"
            for ((i=0; i<remaining-1; i++)); do
                progress+=" "
            done
        fi
        
        progress+="]"
    fi
    
    # 清除当前行并显示进度条
    echo -ne "\r\033[K$progress"
    
    # 如果完成，换行并显示完成消息
    if [[ $current -eq $total ]]; then
        echo ""
        if [[ -n "$description" ]]; then
            if [[ "$COLOR_OUTPUT" == "true" ]]; then
                echo -e "${COLOR_GREEN}✓ $description 完成${COLOR_RESET} ${COLOR_CYAN}($(date +"%H:%M:%S"))${COLOR_RESET}"
                echo -e "${COLOR_BOLD}${COLOR_BG_GREEN} 完成 ${COLOR_RESET} ${COLOR_BOLD}${COLOR_GREEN}$description${COLOR_RESET}" 
                # 添加分隔线增强可读性
                echo -e "${COLOR_CYAN}----------------------------------------${COLOR_RESET}"
            else
                echo "✓ $description 完成 ($(date +"%H:%M:%S"))"
                echo "[完成] $description"
                echo "----------------------------------------"
            fi
        fi
    fi
}

# 显示百分比进度
show_progress_percent() {
    local current=$1
    local total=$2
    local description=$3
    local extra_info=$4
    local percentage=$((current * 100 / total))
    
    # 在每个新任务前添加空行和分隔线，避免进度显示模糊在一起
    if [[ $current -eq 1 || $current -eq 0 ]]; then
        echo ""
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            echo -e "${COLOR_PURPLE}▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁▁${COLOR_RESET}"
        else
            echo "----------------------------------------------------------"
        fi
    fi
    
    # 构建进度信息
    local progress=""
    
    # 添加任务标识符和描述信息（如果有）
    if [[ -n "$description" ]]; then
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            # 添加任务标识符，使用不同背景色增强区分度
            progress="${COLOR_BOLD}${COLOR_BG_PURPLE} 进度 ${COLOR_RESET} ${COLOR_BOLD}${COLOR_LIGHT_PURPLE}$description${COLOR_RESET}: "
        else
            progress="[进度] $description: "
        fi
    fi
    
    # 使用彩色输出（如果启用）
    if [[ "$COLOR_OUTPUT" == "true" ]]; then
        # 根据进度选择颜色
        if [[ $percentage -lt 30 ]]; then
            progress+="${COLOR_BOLD}${COLOR_RED}$percentage%${COLOR_RESET}"
        elif [[ $percentage -lt 70 ]]; then
            progress+="${COLOR_BOLD}${COLOR_YELLOW}$percentage%${COLOR_RESET}"
        else
            progress+="${COLOR_BOLD}${COLOR_GREEN}$percentage%${COLOR_RESET}"
        fi
    else
        progress+="进度: $percentage%"
    fi
    
    # 添加额外信息（如果有）
    if [[ -n "$extra_info" ]]; then
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            progress+=" ${COLOR_CYAN}[$extra_info]${COLOR_RESET}"
        else
            progress+=" [$extra_info]"
        fi
    fi
    
    # 清除当前行并显示进度
    echo -ne "\r\033[K$progress"
    
    # 如果完成，换行并显示完成消息
    if [[ $current -eq $total ]]; then
        echo ""
        if [[ -n "$description" ]]; then
            if [[ "$COLOR_OUTPUT" == "true" ]]; then
                echo -e "${COLOR_GREEN}✓ $description 完成${COLOR_RESET} ${COLOR_CYAN}($(date +"%H:%M:%S"))${COLOR_RESET}"
                echo -e "${COLOR_BOLD}${COLOR_BG_GREEN} 完成 ${COLOR_RESET} ${COLOR_BOLD}${COLOR_GREEN}$description${COLOR_RESET}"
                # 添加分隔线增强可读性
                echo -e "${COLOR_CYAN}----------------------------------------${COLOR_RESET}"
            else
                echo "✓ $description 完成 ($(date +"%H:%M:%S"))"
                echo "[完成] $description"
                echo "----------------------------------------"
            fi
        fi
    fi
}

# 通用进度显示函数
show_progress() {
    local current=$1
    local total=$2
    local description=$3
    local extra_info=$4
    
    # 如果禁用进度显示，则直接返回
    if [[ "$SHOW_PROGRESS" != "true" ]]; then
        return
    fi
    
    # 如果总数为0，避免除以零错误
    if [[ $total -eq 0 ]]; then
        return
    fi
    
    # 根据配置选择进度显示类型
    if [[ "$PROGRESS_TYPE" == "bar" ]]; then
        show_progress_bar "$current" "$total" "$description" "$extra_info"
    else
        show_progress_percent "$current" "$total" "$description" "$extra_info"
    fi
}

# 显示带有ETA的进度条
show_progress_with_eta() {
    local current=$1
    local total=$2
    local description=$3
    local start_time=$4
    
    # 如果禁用进度显示，则直接返回
    if [[ "$SHOW_PROGRESS" != "true" ]]; then
        return
    fi
    
    # 如果总数为0，避免除以零错误
    if [[ $total -eq 0 ]]; then
        return
    fi
    
    # 计算已用时间（秒）
    local current_time=$(date +%s)
    local elapsed=$((current_time - start_time))
    
    # 计算预计剩余时间（秒）
    local eta="未知"
    if [[ $current -gt 0 ]]; then
        local rate=$(echo "scale=2; $elapsed / $current" | bc)
        local remaining=$(echo "scale=2; $rate * ($total - $current)" | bc)
        remaining=${remaining%.*} # 取整
        
        if [[ $remaining -gt 0 ]]; then
            eta=$(format_time $remaining)
        else
            eta="即将完成"
        fi
    fi
    
    # 显示进度
    local extra_info="已用:$(format_time $elapsed) 剩余:$eta"
    
    # 在每个新任务前添加空行，增强可读性
    if [[ $current -eq 1 ]]; then
        echo ""
        if [[ "$COLOR_OUTPUT" == "true" ]]; then
            echo -e "${COLOR_BOLD}${COLOR_BG_CYAN} 开始 ${COLOR_RESET} ${COLOR_BOLD}$description${COLOR_RESET}"
        else
            echo "[开始] $description"
        fi
    fi
    
    # 根据配置选择进度显示类型
    if [[ "$PROGRESS_TYPE" == "bar" ]]; then
        show_progress_bar "$current" "$total" "$description" "$extra_info"
    else
        show_progress_percent "$current" "$total" "$description" "$extra_info"
    fi
}

# 重置重试计数器
reset_retry_counter() {
    CURRENT_RETRY=0
}
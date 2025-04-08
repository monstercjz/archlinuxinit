#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 创建日志函数
# 功能：记录不同级别的日志信息到日志文件并显示在终端上
# 参数：
#   $1 - 日志级别（INFO, WARN, ERROR, FATAL, DEBUG）
#   $2 - 日志消息内容
# 全局变量依赖:
#   LOG_FILE - 日志文件的路径 (应在主脚本或配置加载器中定义)
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
#   log "INFO" "开始备份操作"
#   log "ERROR" "文件不存在"
#   log "FATAL" "无法访问备份目录"
log() {
    # 检查 LOG_FILE 是否已定义且非空
    if [ -z "${LOG_FILE}" ]; then
        echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [FATAL] LOG_FILE 未定义，无法记录日志。${NC}" >&2
        exit 1
    fi

    local level=$1
    local message=$2
    local color=$NC
    
    case $level in
        "INFO") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "FATAL") color=$RED ;;
        "DEBUG") color=$BLUE ;;
        *) level="DEBUG"; color=$BLUE ;; # 默认为 DEBUG 级别
    esac
    
    # 确保日志目录存在
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    if [ ! -d "$log_dir" ]; then
        mkdir -p "$log_dir" || {
            echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [FATAL] 无法创建日志目录: $log_dir ${NC}" >&2
            exit 1
        }
    fi

    # 写入日志文件和终端
    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}${NC}" | tee -a "$LOG_FILE"
    
    # 如果是致命错误，退出脚本
    if [ "$level" == "FATAL" ]; then
        echo -e "${RED}备份过程中遇到致命错误，退出脚本${NC}" | tee -a "$LOG_FILE"
        exit 1
    fi
}

# 初始化日志文件函数
# 功能：确保日志文件存在并写入初始信息
# 参数：无
# 全局变量依赖:
#   LOG_FILE - 日志文件的路径
#   TIMESTAMP - 当前时间戳 (格式: YYYY-MM-DD_HH-MM-SS)
# 返回值：无
init_log() {
    if [ -z "${LOG_FILE}" ]; then
        echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] [FATAL] LOG_FILE 未定义，无法初始化日志。${NC}" >&2
        exit 1
    fi
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    mkdir -p "$log_dir"
    # 写入日志文件头
    echo "=============================================================" > "$LOG_FILE"
    echo " Arch Linux Backup Log - ${TIMESTAMP}" >> "$LOG_FILE"
    echo "=============================================================" >> "$LOG_FILE"
    log "INFO" "日志文件初始化: ${LOG_FILE}"
}

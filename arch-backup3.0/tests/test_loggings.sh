#!/bin/bash

# 测试 core/loggings.sh 的控制台颜色输出

# 获取脚本自身的位置，用于定位 core 目录
TEST_SCRIPT_DIR=$(dirname "$0")
PROJECT_ROOT=$(cd "$TEST_SCRIPT_DIR/.." &amp;&amp; pwd) # 获取项目根目录

# 定义 core 目录路径
CORE_DIR="$PROJECT_ROOT/core"

# 检查 loggings.sh 是否存在
LOGGINGS_SCRIPT="$CORE_DIR/loggings.sh"
if [ ! -f "$LOGGINGS_SCRIPT" ]; then
    echo "错误：无法找到日志脚本: $LOGGINGS_SCRIPT" >&2
    exit 1
fi

# --- 强制设置测试环境 ---
# 覆盖可能存在的外部配置，确保测试的是颜色输出本身
export COLOR_OUTPUT=true    # 强制启用颜色
export LOG_TO_FILE=false    # 强制禁用文件日志
export LOG_LEVEL="TRACE"    # 显示所有级别的日志
export VERBOSE=true         # 显示详细调用信息

# 加载日志脚本
# shellcheck source=../core/loggings.sh
source "$LOGGINGS_SCRIPT"

# 初始化日志系统 (会读取上面的环境变量)
init_logging

echo -e "\n--- 开始日志颜色测试 ---"
echo "预期：下面的每行日志应该有不同的颜色（或至少与普通文本不同）。"
echo "如果所有行颜色都一样（通常是终端默认颜色），则颜色输出可能存在问题。"
echo "-------------------------"

# 调用不同级别的日志函数
log_trace   "这是一条 TRACE 级别的日志。"
log_debug   "这是一条 DEBUG 级别的日志。"
log_info    "这是一条 INFO 级别的日志。"
log_notice  "这是一条 NOTICE 级别的日志。"
log_warn    "这是一条 WARN 级别的日志。"
log_error   "这是一条 ERROR 级别的日志。"
log_critical "这是一条 CRITICAL 级别的日志。"
log_fatal   "这是一条 FATAL 级别的日志。"

log_section "这是一个日志分节标题" $LOG_LEVEL_NOTICE

echo -e "\n--- 日志颜色测试结束 ---"
echo "请检查上面的输出是否带有颜色。"

# 测试带颜色的普通输出
echo -e "${COLOR_RED}这是红色文本${COLOR_RESET}"
echo -e "${COLOR_GREEN}这是绿色文本${COLOR_RESET}"
echo -e "${COLOR_YELLOW}这是黄色文本${COLOR_RESET}"
echo -e "${COLOR_BLUE}这是蓝色文本${COLOR_RESET}"
echo -e "${COLOR_BOLD}这是粗体文本${COLOR_RESET}"
echo -e "${COLOR_UNDERLINE}这是带下划线的文本${COLOR_RESET}"

exit 0
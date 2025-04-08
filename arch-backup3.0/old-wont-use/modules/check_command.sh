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
####### 已经废弃，被check_command_version替代
check_command() {
    command -v "$1" >/dev/null 2>&1 || { log "ERROR" "命令 $1 未安装，请先安装该命令"; exit 1; }
}
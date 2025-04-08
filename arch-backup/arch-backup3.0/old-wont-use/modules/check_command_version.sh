# 检查命令版本
# 功能：检查指定命令的版本是否满足最低要求
# 参数：
#   $1 - 要检查的命令名称
#   $2 - 最低版本要求（如 "3.1.0"）
#   $3 - 获取版本的命令行选项（默认为 --version）
#   $4 - 版本号的正则表达式模式（默认为 '[0-9]+(\.[0-9]+)+'）
# 返回值：
#   0 - 版本满足要求或无法获取版本信息
#   1 - 版本低于最低要求
# 错误处理：
#   如果无法获取版本信息，会记录警告但不会中断执行
#   如果版本低于要求，会记录警告但不会中断执行
# 使用示例：
#   check_command_version "rsync" "3.1.0"
#   check_command_version "openssl" "1.1.0" "version" "[0-9]+(\.[0-9]+)+[a-z]*"
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
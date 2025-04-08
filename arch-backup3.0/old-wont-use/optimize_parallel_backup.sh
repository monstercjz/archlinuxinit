#!/bin/bash

#############################################################
# 并行备份资源优化脚本
#
# 功能:
#   优化并行备份的资源使用，避免系统负载过高
#   根据系统当前负载动态调整并行任务数量
#   提供资源监控和任务调度功能
#
# 参数:
#   $1 - 最大并行任务数 (可选，默认使用配置文件中的 PARALLEL_JOBS)
#   $2 - 负载阈值 (可选，默认为 CPU 核心数的 70%)
#
# 返回值:
#   0 - 成功
#   1 - 失败
#
# 依赖项:
#   - 外部命令: bc, awk, grep, ps
#   - 核心脚本:
#     - core/loggings.sh (提供 log 函数)
#
# 使用示例:
#   $ optimize_parallel_backup 4 0.7
#
#############################################################

# 获取系统资源信息
get_system_resources() {
    # 获取CPU核心数
    local cpu_count=$(grep -c processor /proc/cpuinfo 2>/dev/null || echo "4")
    
    # 获取系统负载
    local system_load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "0")
    
    # 获取可用内存（MB）
    local available_memory=$(free -m | awk '/^Mem:/ {print $7}' 2>/dev/null || echo "1024")
    
    # 输出资源信息
    echo "CPU_COUNT=$cpu_count"
    echo "SYSTEM_LOAD=$system_load"
    echo "AVAILABLE_MEMORY=$available_memory"
}

# 计算最佳并行任务数
calculate_optimal_jobs() {
    local max_jobs="$1"
    local load_threshold="$2"
    
    # 获取系统资源信息
    local resource_info=$(get_system_resources)
    local cpu_count=$(echo "$resource_info" | grep CPU_COUNT | cut -d= -f2)
    local system_load=$(echo "$resource_info" | grep SYSTEM_LOAD | cut -d= -f2)
    local available_memory=$(echo "$resource_info" | grep AVAILABLE_MEMORY | cut -d= -f2)
    
    # 计算当前CPU使用率
    local cpu_usage=$(echo "$system_load / $cpu_count" | bc -l 2>/dev/null || echo "0.5")
    
    # 根据CPU使用率调整并行任务数
    local optimal_jobs=$max_jobs
    
    # 如果系统负载过高，减少并行任务数
    if (( $(echo "$cpu_usage > $load_threshold" | bc -l 2>/dev/null || echo "0") )); then
        # 根据负载程度动态调整
        if (( $(echo "$cpu_usage > 0.9" | bc -l 2>/dev/null || echo "0") )); then
            # 负载非常高，大幅减少任务数
            optimal_jobs=$(( max_jobs / 4 ))
        elif (( $(echo "$cpu_usage > 0.8" | bc -l 2>/dev/null || echo "0") )); then
            # 负载较高，减少一半任务数
            optimal_jobs=$(( max_jobs / 2 ))
        else
            # 负载略高，小幅减少任务数
            optimal_jobs=$(( max_jobs * 3 / 4 ))
        fi
    fi
    
    # 确保至少有一个任务
    optimal_jobs=$(( optimal_jobs > 0 ? optimal_jobs : 1 ))
    
    # 考虑内存限制
    # 假设每个备份任务平均需要 200MB 内存
    local memory_based_jobs=$(( available_memory / 200 ))
    if [ $memory_based_jobs -lt $optimal_jobs ]; then
        optimal_jobs=$memory_based_jobs
    fi
    
    # 再次确保至少有一个任务
    optimal_jobs=$(( optimal_jobs > 0 ? optimal_jobs : 1 ))
    
    echo $optimal_jobs
}

# 监控系统资源并调整正在运行的任务
monitor_and_adjust() {
    local max_jobs="$1"
    local load_threshold="$2"
    local check_interval=5 # 每5秒检查一次
    
    log "INFO" "开始监控系统资源，最大并行任务数: $max_jobs，负载阈值: $load_threshold"
    
    while true; do
        # 获取当前运行的备份任务数
        local running_jobs=$(ps aux | grep -v grep | grep -c "rsync")
        
        # 计算最佳并行任务数
        local optimal_jobs=$(calculate_optimal_jobs "$max_jobs" "$load_threshold")
        
        # 获取系统资源信息用于日志
        local resource_info=$(get_system_resources)
        local system_load=$(echo "$resource_info" | grep SYSTEM_LOAD | cut -d= -f2)
        
        log "DEBUG" "系统负载: $system_load, 运行中任务: $running_jobs, 最佳任务数: $optimal_jobs"
        
        # 如果运行的任务数超过最佳任务数，可以考虑暂停一些任务
        # 这里只记录日志，实际暂停任务需要更复杂的实现
        if [ $running_jobs -gt $optimal_jobs ]; then
            log "WARN" "系统负载过高，建议减少并行任务数从 $running_jobs 到 $optimal_jobs"
        fi
        
        # 休眠一段时间再检查
        sleep $check_interval
    done
}

# 优化并行备份主函数
optimize_parallel_backup() {
    local max_jobs="${1:-$PARALLEL_JOBS}"
    local load_threshold="${2:-0.7}"
    
    # 检查参数
    if ! [[ "$max_jobs" =~ ^[0-9]+$ ]]; then
        log "ERROR" "无效的最大并行任务数: $max_jobs"
        return 1
    fi
    
    if ! [[ "$load_threshold" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
        log "ERROR" "无效的负载阈值: $load_threshold"
        return 1
    fi
    
    # 获取系统资源信息
    log "INFO" "获取系统资源信息..."
    local resource_info=$(get_system_resources)
    local cpu_count=$(echo "$resource_info" | grep CPU_COUNT | cut -d= -f2)
    local system_load=$(echo "$resource_info" | grep SYSTEM_LOAD | cut -d= -f2)
    local available_memory=$(echo "$resource_info" | grep AVAILABLE_MEMORY | cut -d= -f2)
    
    log "INFO" "系统资源信息: CPU核心数=$cpu_count, 系统负载=$system_load, 可用内存=${available_memory}MB"
    
    # 计算最佳并行任务数
    local optimal_jobs=$(calculate_optimal_jobs "$max_jobs" "$load_threshold")
    
    log "INFO" "根据当前系统状态，最佳并行任务数为: $optimal_jobs (最大设置: $max_jobs)"
    
    # 返回最佳并行任务数
    echo "OPTIMAL_JOBS=$optimal_jobs"
    return 0
}

# 如果直接运行此脚本（非被其他脚本source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 获取脚本所在目录
    parent_dir="$(dirname "${BASH_SOURCE[0]}")/.."

    # 加载配置和日志脚本
    config_script="$parent_dir/core/config.sh"
    load_config_script="$parent_dir/core/load_config.sh"
    logging_script="$parent_dir/core/loggings.sh"

    _libs_loaded_optimize=true
    # 加载依赖脚本
    if [ -f "$logging_script" ]; then . "$logging_script"; else echo "错误：无法加载 $logging_script" >&2; _libs_loaded_optimize=false; fi
    if [ -f "$config_script" ]; then . "$config_script"; else echo "错误：无法加载 $config_script" >&2; _libs_loaded_optimize=false; fi
    if [ -f "$load_config_script" ]; then . "$load_config_script"; else echo "错误：无法加载 $load_config_script" >&2; _libs_loaded_optimize=false; fi

    if ! $_libs_loaded_optimize; then
        exit 1 # 依赖加载失败
    fi

    # 加载配置文件并初始化日志
    load_config
    
    # 检查操作类型
    if [ "$1" == "monitor" ]; then
        shift
        monitor_and_adjust "$1" "$2"
        exit $?
    else
        optimize_parallel_backup "$1" "$2"
        exit $?
    fi
fi
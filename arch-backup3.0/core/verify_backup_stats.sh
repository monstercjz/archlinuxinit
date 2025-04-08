#!/bin/bash

#############################################################
# 验证备份后的数量和大小
# 功能：比较备份前后的文件数量和大小，确保备份成功完成
# 参数：
#   $1 - 目标根目录路径 (dest_root)
#   $2 - 源路径相对于其基础的相对路径 (relative_path) - 由 rsync -R 创建
#   $3 - 预期的净大小 (字节, expected_net_size)
#   $4 - 预期的净数量 (文件数, expected_net_count)
#   $5 - 允许的差异百分比（可选，默认为5%）
# 返回值：
#   0 - 验证成功
#   1 - 验证失败
#############################################################

# (移除此处的 SCRIPT_DIR, PARENT_DIR 定义和 source 逻辑)
# 依赖的 source 和初始化移至直接执行的 if 块中

# 主函数
verify_backup_stats() {
    local dest_root="$1"
    local relative_path="$2" # 第二个参数现在是相对路径
    local expected_net_size="$3"
    local expected_net_count="$4"
    local acceptable_diff_percent="${5:-5}"  # 默认允许5%的差异
    
    # 检查参数
    if [ -z "$dest_root" ]; then log "ERROR" "验证：未提供目标根目录路径"; return 1; fi
    if [ -z "$relative_path" ]; then log "ERROR" "验证：未提供相对路径"; return 1; fi
    if [[ ! "$expected_net_size" =~ ^[0-9]+$ ]]; then log "ERROR" "验证：未提供有效的预期净大小"; return 1; fi
    if [[ ! "$expected_net_count" =~ ^[0-9]+$ ]]; then log "ERROR" "验证：未提供有效的预期净数量"; return 1; fi
    if [ ! -d "$dest_root" ]; then log "ERROR" "验证：目标根目录不存在: $dest_root"; return 1; fi
    
    # 构建实际要检查的目标路径
    local dest_path="$dest_root/$relative_path"
    # 确保路径没有双斜杠
    dest_path=$(echo "$dest_path" | sed 's|//|/|g')

    log "INFO" "开始验证备份目标: $dest_path (预期大小: $expected_net_size, 预期数量: $expected_net_count)"
    
    # (移除获取源路径大小和数量的代码)
    
    # 获取实际备份目标的大小和文件数量
    local actual_dest_size=0
    local actual_dest_count=0
    # dest_path 已经在上面根据 relative_path 构建好了
    
    
    # 检查目标路径是否存在
    if [ ! -e "$dest_path" ]; then
        log "ERROR" "备份后目标路径不存在: $dest_path"
        return 1
    fi
    
    if [ -d "$dest_path" ]; then
        actual_dest_size=$(du -sb "$dest_path" | awk '{print $1}')
        actual_dest_count=$(find "$dest_path" -type f | wc -l)
    else
        actual_dest_size=$(stat -c %s "$dest_path")
        actual_dest_count=1
    fi
    
    # 转换为人类可读格式
    # 转换为人类可读格式
    local human_expected_size=$(numfmt --to=iec-i --suffix=B "$expected_net_size")
    local human_actual_dest_size=$(numfmt --to=iec-i --suffix=B "$actual_dest_size")
    
    log "INFO" "预期净大小: $human_expected_size ($expected_net_size 字节)"
    log "INFO" "预期净数量: $expected_net_count"
    log "INFO" "实际目标大小: $human_actual_dest_size ($actual_dest_size 字节)"
    log "INFO" "实际目标数量: $actual_dest_count"
    
    # 计算差异
    # 计算预期与实际的差异
    local size_diff=$((expected_net_size - actual_dest_size))
    local count_diff=$((expected_net_count - actual_dest_count))
    
    # 计算差异的百分比
    local size_diff_percent=0
    local count_diff_percent=0
    
    # 使用预期值作为百分比计算基数
    if [ $expected_net_size -gt 0 ]; then
        size_diff_percent=$(echo "scale=2; 100 * ${size_diff#-} / $expected_net_size" | bc)
    fi
    
    if [ $expected_net_count -gt 0 ]; then
        count_diff_percent=$(echo "scale=2; 100 * ${count_diff#-} / $expected_net_count" | bc)
    fi
    
    log "INFO" "大小差异: $size_diff_percent%"
    log "INFO" "数量差异: $count_diff_percent%"
    
    # 检查差异是否在可接受范围内
    if (( $(echo "$size_diff_percent < $acceptable_diff_percent" | bc -l) )) && \
       (( $(echo "$count_diff_percent < $acceptable_diff_percent" | bc -l) )); then
        log "INFO" "备份验证成功：文件大小和数量差异在可接受范围内"
        return 0
    else
        log "ERROR" "备份验证失败：文件大小或数量差异超出可接受范围"
        return 1
    fi
}

# 如果直接运行此脚本（非被其他脚本source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # --- 直接执行时的设置 ---
    # 获取脚本所在目录
    script_dir=$(dirname "$0") # 使用简化方式
    parent_dir=$(dirname "$script_dir")

    # 加载配置和日志脚本
    # 注意: verify_backup_stats 函数目前不依赖 config.sh 的默认值，但为了统一，还是加载
    config_script="$parent_dir/core/config.sh"
    load_config_script="$parent_dir/core/load_config.sh"
    logging_script="$parent_dir/core/loggings.sh" # load_config 依赖 loggings

    _libs_loaded_verify=true
    # 先加载日志，因为 load_config 会调用 init_logging
    if [ -f "$logging_script" ]; then . "$logging_script"; else echo "错误：无法加载 $logging_script" >&2; _libs_loaded_verify=false; fi
    if [ -f "$config_script" ]; then . "$config_script"; else echo "错误：无法加载 $config_script" >&2; _libs_loaded_verify=false; fi
    if [ -f "$load_config_script" ]; then . "$load_config_script"; else echo "错误：无法加载 $load_config_script" >&2; _libs_loaded_verify=false; fi

    if ! $_libs_loaded_verify; then
        exit 1 # 依赖加载失败
    fi

    # 加载配置文件并初始化日志
    load_config
    # init_logging 会在 load_config 内部被调用，无需再次调用
    
    # 执行主函数
    # 直接执行时需要提供预期值，可能不太实用，但保持签名一致
    # 直接执行时，第二个参数应该是相对路径
    verify_backup_stats "$1" "$2" "$3" "$4" "$5"
    exit $?
fi
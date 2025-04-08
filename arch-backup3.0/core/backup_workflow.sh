#!/bin/bash

#############################################################
# Arch Linux 备份工作流脚本
# 功能：按照流程执行备份操作
# 1. 检查备份可行性 (源大小、目标空间、空间比较)
# 2. 执行备份 (rsync)
# 3. 验证备份结果 (统计对比)
# 4. 备份工作流完成
#
# 参数：
#   $1 - 源路径（文件或目录）
#   $2 - 目标路径 (基础目录)
#   $3 - 排除模式（可选，格式为逗号分隔的字符串）
# 返回值：
#   0 - 备份工作流成功完成
#   1 - 备份工作流失败（任何步骤失败）
#
# 使用示例：
#   $ ./backup_workflow.sh /home/user/documents /var/backups "*.tmp,*.log"
#
# 依赖项：
#   - 外部脚本：
#     - core/check_backup_feasibility.sh: 检查备份可行性 (大小、空间、比较)
#     - file-check/rsync_backup.sh: 执行实际的 rsync 备份操作
#     - file-check/verify_backup_stats.sh: 验证备份后的文件数量和大小
#   - 内部函数：
#     - log: 来自core/loggings.sh，用于记录不同级别的日志信息
#       格式: log "级别" "消息"，级别可以是INFO、ERROR等
#     - log_section: 来自core/loggings.sh，用于记录日志分节信息
#     - init_logging: 来自core/loggings.sh，用于初始化日志系统
#       在脚本直接执行时会调用此函数
#############################################################

# 主函数
backup_workflow() {
    local src="$1"
    local dest="$2"
    local exclude_patterns="$3"
    # 不再需要 backup_errors 计数器，因为任何失败都会立即返回
    # (移除不再需要的 backup_errors 变量)
    # 获取此脚本文件所在的目录，确保无论如何调用都能找到依赖脚本
    local current_script_dir
    # BASH_SOURCE[0] 在 source 时指向源文件，在直接执行时指向脚本本身
    # 使用更简单的方式获取脚本目录
    current_script_dir=$(dirname "${BASH_SOURCE[0]}")
    local parent_dir
    parent_dir=$(dirname "$current_script_dir")
    
    # 检查参数
    if [ -z "$src" ]; then
        log "ERROR" "未提供源路径"
        return 1
    fi
    
    if [ -z "$dest" ]; then
        log "ERROR" "未提供目标路径"
        return 1
    fi
    
    # 检查源路径是否存在
    if [ ! -e "$src" ]; then
            log "ERROR" "源路径不存在: $src"
        return 1
    fi
    # 检查外部命令依赖
    if ! command -v bc > /dev/null 2>&1; then
        log "ERROR" "命令 'bc' 未找到，请安装它 (例如: sudo pacman -S bc)"
        return 1
    fi
    if ! command -v numfmt > /dev/null 2>&1; then
        log "ERROR" "命令 'numfmt' 未找到，请安装它 (例如: sudo pacman -S coreutils)"
        return 1
    fi    
    log_section "开始备份工作流 (${src})(${TIMESTAMP})" $LOG_LEVEL_INFO
    
    # 步骤1：检查备份可行性
    log_section "第一步：检查备份可行性 (源大小、目标空间、空间比较)" $LOG_LEVEL_INFO
    # (移除不再需要的 feasibility_script 变量)

    # (移除脚本存在性检查，因为库已在顶层 source)

    log "INFO" "调用函数: check_backup_feasibility \"$src\" \"$dest\" \"$exclude_patterns\""
    # 将排除模式作为第三个参数传递给函数调用，并捕获其标准输出
    local feasibility_output
    if ! feasibility_output=$(check_backup_feasibility "$src" "$dest" "$exclude_patterns"); then
        local exit_code=$?
        log "ERROR" "备份可行性检查失败，退出码: $exit_code 。请查看上面的日志了解详情。"
        # 可以根据 $exit_code 进一步区分错误原因，但对于工作流来说，失败就是失败
        return 1 # 可行性检查失败，终止工作流
    fi
    # 如果脚本执行到这里，说明可行性检查通过
    # 解析输出以获取净大小和数量
    local net_size=$(echo "$feasibility_output" | awk -F= '/^NET_SIZE=/ {print $2}')
    local net_count=$(echo "$feasibility_output" | awk -F= '/^NET_COUNT=/ {print $2}')
    local human_net_size=$(numfmt --to=iec-i --suffix=B "$net_size") # 转换为可读格式

    log "INFO" "备份可行性检查通过。预计净备份大小: $human_net_size ($net_size 字节), 净文件数: $net_count"
    log "INFO" "继续执行备份流程..."
    
    # 步骤2：执行备份 (rsync)
    log_section "第二步：执行备份 (rsync)" $LOG_LEVEL_INFO
    
    # (移除重复的日志行)
    # 直接调用 rsync_backup 函数 (它在 core/ 目录下)
    log "INFO" "调用函数: rsync_backup \"$src\" \"$dest\" \"$exclude_patterns\""
    if ! rsync_backup "$src" "$dest" "$exclude_patterns"; then
        log "ERROR" "备份项目失败 (rsync 步骤)"
        return 1 # 备份失败，立即退出
    fi
    
    # 步骤3：验证备份结果 (统计对比)
    log_section "第三步：验证备份结果 (统计对比)" $LOG_LEVEL_INFO
    
    # 准备 verify_backup_stats 的参数
    # 计算相对路径 (移除 $src 开头的 /)
    local calculated_relative_path="${src#/}"
    log "INFO" "调用函数: verify_backup_stats \"$dest\" \"$calculated_relative_path\" \"$net_size\" \"$net_count\""
    # 调用 verify_backup_stats 函数，传递目标根目录、计算出的相对路径、净大小、净数量
    if ! verify_backup_stats "$dest" "$calculated_relative_path" "$net_size" "$net_count"; then
        log "ERROR" "备份验证失败"
        return 1 # 验证失败，立即退出
    fi
    
    # 如果脚本执行到这里，说明所有步骤都成功了
    log "INFO" "备份工作流成功完成！源: \"$src\", 目标: \"$dest\""
    # 步骤4：备份工作流完成
    log_section "第四步：备份工作流完成" $LOG_LEVEL_INFO
    
    return 0
    
}



# --- 主函数调用 (直接执行时) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # --- 库脚本加载 ---
    # 获取此脚本文件所在的目录 (使用简化方式)
    _workflow_script_dir=$(dirname "${BASH_SOURCE[0]}")
    _workflow_parent_dir=$(dirname "$_workflow_script_dir")

    # 定义需要 source 的脚本列表
    _required_libs=(
        "$_workflow_script_dir/config.sh"
        "$_workflow_script_dir/load_config.sh"
        "$_workflow_script_dir/loggings.sh"
        "$_workflow_script_dir/check_and_create_directory.sh" # rsync_backup 依赖
        "$_workflow_script_dir/calculate_size_and_count.sh" # check_backup_feasibility 依赖 (循环方法)
        "$_workflow_script_dir/check_disk_space.sh"         # check_backup_feasibility 依赖
        "$_workflow_script_dir/check_backup_feasibility.sh"
        "$_workflow_script_dir/rsync_backup.sh"             # rsync_backup 在 core/
        "$_workflow_script_dir/verify_backup_stats.sh" # verify_backup_stats 在 core/
    )

    # 循环 source 脚本，检查是否存在
    _libs_loaded=true
    for lib in "${_required_libs[@]}"; do
        if [ -f "$lib" ]; then
            # 使用 . 代替 source 更通用
            . "$lib"
        else
            echo "错误：无法加载依赖库 $lib" >&2
            _libs_loaded=false
        fi
    done
    # 检查库是否都已加载
    if ! $_libs_loaded; then
        echo "错误：部分依赖库未能加载，无法继续。" >&2
        exit 1
    fi

    # 初始化日志 (只需要执行一次)
    init_logging

    # 执行主函数
    backup_workflow "$1" "$2" "$3"
    exit $?
fi
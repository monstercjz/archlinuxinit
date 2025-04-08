#!/bin/bash

############################################################
# 备份自定义路径脚本
# 功能：调用核心备份工作流来备份配置文件中指定的自定义路径。
#       从配置文件读取要备份的路径列表、排除项和开关。
############################################################

# --- 脚本初始化 ---
# SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
# CORE_DIR="$PROJECT_ROOT/core"

# --- 主函数定义 ---
# 当被 source 时，调用者需要确保核心库已加载
backup_custom_paths() {
    # 注意：当作为库函数调用时，假定 load_config 已经被调用者执行
    # 因此日志系统应该已经初始化

    log_section "备份自定义路径" $LOG_LEVEL_NOTICE

    # 检查备份开关
    if [[ "$BACKUP_CUSTOM_PATHS" != "true" ]]; then
        log_notice "根据配置，跳过备份自定义路径。"
        return 0
    fi

    # 检查 CUSTOM_PATHS 是否为空
    if [ -z "$CUSTOM_PATHS" ]; then
        log_notice "没有配置自定义备份路径 (CUSTOM_PATHS 为空)，跳过。"
        return 0
    fi

    # 定义目标目录基础路径
    local dest_base="${BACKUP_DIR}/custom" # 修改目标基础目录
    # 将空格分隔的排除项转换为逗号分隔
    local exclude_patterns
    exclude_patterns=$(echo "$EXCLUDE_CUSTOM_PATHS" | tr ' ' ',')

    local overall_success=true # 跟踪所有备份项的总体状态
    local total_items=0
    local success_count=0
    local fail_count=0

    # 循环处理 CUSTOM_PATHS 中的每个路径
    # 将空格分隔的列表转换为数组，以便更准确地计数
    read -ra CUSTOM_PATHS_ARRAY <<< "$CUSTOM_PATHS"
    total_items=${#CUSTOM_PATHS_ARRAY[@]}
    log_info "准备备份 $total_items 个自定义路径..."

    for src in "${CUSTOM_PATHS_ARRAY[@]}"; do
        # 检查源路径是否存在
        if [ ! -e "$src" ]; then
            log_warn "自定义路径不存在，跳过: $src"
            # 即使跳过，也计入总数，但不计入成功或失败
            continue
        fi

        log_info "准备备份自定义路径: $src"

        # 调用核心工作流函数 (假设已被 source)
        if ! command -v backup_workflow > /dev/null 2>&1; then
            # 尝试 source backup_workflow.sh (作为后备)
            if [ -f "$CORE_DIR/backup_workflow.sh" ]; then
                log_warn "backup_workflow 函数未找到，尝试 source $CORE_DIR/backup_workflow.sh"
                . "$CORE_DIR/backup_workflow.sh"
                if ! command -v backup_workflow > /dev/null 2>&1; then
                     log_error "无法加载或找到 backup_workflow 函数，自定义路径 '$src' 备份失败。"
                     overall_success=false
                     continue # 继续处理下一个路径
                fi
            else
                log_error "backup_workflow 函数未找到，且无法找到 $CORE_DIR/backup_workflow.sh，自定义路径 '$src' 备份失败。"
                overall_success=false
                continue # 继续处理下一个路径
            fi
        fi

        local dest="$dest_base" # 目标目录是 custom 子目录

        # --- 生成源校验和清单 ---
        # 清单文件直接存储在 BACKUP_DIR 下
        # 为自定义路径创建安全的文件名
        local safe_src_name=$(echo "$src" | sed 's|^/||; s|/|_|g') # 移除开头的/，替换其他/为_
        local manifest_file="${BACKUP_DIR}/custom_${safe_src_name}.sha256"
        # 调用清单生成函数，传递源、清单路径和排除模式
        log_info "调用 generate_source_checksum_manifest \"$src\" \"$manifest_file\" \"$exclude_patterns\""
        if ! generate_source_checksum_manifest "$src" "$manifest_file" "$exclude_patterns"; then
            log_error "为源 $src 生成校验和清单失败 (已考虑排除项)，跳过此项备份。"
            ((fail_count++))
            continue # 跳到下一个路径
        fi

        # --- 调用核心工作流 ---
        log_info "调用 backup_workflow 函数: \"$src\" -> \"$dest\" (排除: \"$exclude_patterns\")"
        # 调用核心工作流（现在只有3个参数）
        if ! backup_workflow "$src" "$dest" "$exclude_patterns"; then
            log_error "备份自定义路径失败: $src"
            overall_success=false # 标记整体失败
            ((fail_count++))
            # continue # 继续处理下一个路径 (默认行为)
        else
            log_info "备份自定义路径 (rsync+stats) 成功: $src"
            # --- 在备份成功后立即进行校验和验证 ---
            # --- 调用封装好的校验函数 ---
            if ! verify_backup_checksum "$src" "$dest" "$manifest_file"; then
                # 校验失败（或跳过但标记为失败，虽然目前函数实现是跳过则返回0）
                # verify_backup_checksum 内部已记录详细错误
                overall_success=false
                ((fail_count++))
            else
                # 校验成功或被跳过（且未出错）
                # 只有真正校验成功才增加 success_count
                if [[ "$VERIFY_CHECKSUM" == "true" ]]; then
                     ((success_count++))
                else
                     # 如果跳过校验，也算作备份流程成功的一部分
                     # 但不在最终统计中显示为“校验成功”
                     # ((success_count++)) # 或者根据需求决定是否增加
                     : # 跳过校验时，不改变成功计数，只确保不计入失败
                fi
            fi
        fi
    done

    # 报告统计结果
    log_section "自定义路径备份统计" $LOG_LEVEL_NOTICE
    log_info "总共尝试路径数: $total_items"
    log_info "成功备份路径数: $success_count"
    log_info "失败备份路径数: $fail_count"
    local skipped_count=$((total_items - success_count - fail_count))
    if [ $skipped_count -gt 0 ]; then
        log_info "跳过路径数 (不存在): $skipped_count"
    fi

    if [ $fail_count -eq 0 ]; then
        log_info "所有自定义路径备份成功完成。"
        return 0
    else
        log_error "部分自定义路径备份失败。"
        return 1
    fi
}

# --- 直接执行块 ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # --- 脚本初始化 (for direct execution) ---
    SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
    PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
    CORE_DIR="$PROJECT_ROOT/core"
    file_check_dir="$PROJECT_ROOT/file-check" # 定义 file-check 目录

    # --- 加载核心库 (for direct execution) ---
    # 需要加载 backup_workflow 及其所有依赖项定义的函数
    _libs_loaded_custom_direct=true
    _core_libs=(
        "$CORE_DIR/config.sh"
        "$CORE_DIR/loggings.sh" # loggings 需要先加载
        "$CORE_DIR/load_config.sh" # load_config 会调用 init_logging
        "$CORE_DIR/check_dependencies.sh" # <--- 添加依赖检查脚本
        "$CORE_DIR/check_and_create_directory.sh" # rsync_backup 依赖
        "$CORE_DIR/calculate_size_and_count.sh" # check_backup_feasibility 依赖
        "$CORE_DIR/check_disk_space.sh"         # check_backup_feasibility 依赖
        "$CORE_DIR/check_backup_feasibility.sh"
        "$CORE_DIR/rsync_backup.sh"
        "$CORE_DIR/verify_backup_stats.sh"
        "$CORE_DIR/backup_workflow.sh" # 最后加载 workflow 本身
        "$file_check_dir/check_file_integrity.sh" # 包含 verify_checksum_manifest
        "$file_check_dir/verify_backup_checksum.sh" # 包含封装的校验函数 (已移动)
    )
    for lib in "${_core_libs[@]}"; do
        if [ -f "$lib" ]; then
            . "$lib" # 使用 . source 脚本
        else
            echo "错误：无法加载核心库 $lib" >&2
            _libs_loaded_custom_direct=false
        fi
    done

    if ! $_libs_loaded_custom_direct; then
        echo "错误：直接执行自定义路径备份脚本时未能加载所有核心依赖库，无法继续。" >&2
        exit 1
    fi

    # --- 检查外部依赖 ---
    if ! check_dependencies; then
         exit 1 # check_dependencies 内部会记录错误
    fi

    # --- 加载配置并初始化日志 (for direct execution) ---
    # load_config 应该在上面 source 时被加载了
    # 调用它来确保配置被读取且日志被初始化
    if command -v load_config > /dev/null 2>&1; then
        load_config
    else
        echo "错误：load_config 函数未定义，无法初始化配置和日志。" >&2
        exit 1
    fi

    # --- 执行主函数 (for direct execution) ---
    backup_custom_config
    exit $? # 退出脚本，使用函数的返回码
fi
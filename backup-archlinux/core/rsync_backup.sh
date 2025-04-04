#!/bin/bash
# rsync_backup.sh - 核心rsync备份模块 (v2)
# 功能：提供统一的rsync备份功能，支持各种备份场景
#
# 必需参数：
#   $1 - 源路径数组（空格分隔的字符串）
#   $2 - 目标目录基础路径
# 可选位置参数：
#   $3 - 排除参数（可选，格式为空格分隔的字符串）
#   $4 - 排除参数（可选，格式为空格分隔的字符串）
#
# 可选参数 (使用标志形式, e.g., --retry --progress):
#   --retry         启用重试机制 (默认不启用)
#   --max-retries NUM   最大重试次数 (默认 3, 需配合 --retry)
#   --retry-delay SEC   重试间隔时间 (默认 5, 需配合 --retry)
#   --progress       显示备份进度 (默认启用)
#   --no-progress    禁用备份进度显示
#   --diff         启用差异备份 (基于上次备份)
#   --last-backup DIR   上次备份的目录 (需配合 --diff)
#
# 返回值：
#   0 - 所有路径备份成功 (或rsync返回24)
#   非0 - 至少有一个路径备份失败
#
# 错误处理：
#   - 记录详细错误信息
#   - 使用 exec_with_retry 处理重试逻辑

# --- 依赖加载 ---
# 假设 loggings.sh, exec_with_retry.sh, check_and_create_directory.sh 已在主脚本中加载
# 如果此脚本可能独立运行，需要添加加载逻辑

rsync_backup() {
    # --- 参数和选项初始化 ---
    local source_paths_str=""
    local target_base_dir=""
    # local backup_desc="" # Removed parameter
    local exclude_patterns_str=""
    local enable_retry=false
    local max_retries=3
    local retry_delay=5
    local show_progress=true # 默认启用进度，除非被覆盖
    local enable_diff=false
    local last_backup_dir=""
    local rsync_opts="-ah --delete --numeric-ids --exclude=lost+found/" # 基础选项
    local positional_args=()

    # --- 解析可选参数 ---
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --retry)
                enable_retry=true
                shift
                ;;
            --max-retries)
                max_retries="$2"
                shift 2
                ;;
            --retry-delay)
                retry_delay="$2"
                shift 2
                ;;
            --progress)
                # 允许通过参数控制，但默认值可能来自配置
                # show_progress=true # 保持默认或根据参数设置
                shift
                ;;
            --no-progress)
                show_progress=false
                shift
                ;;
            --diff)
                enable_diff=true
                shift
                ;;
            --last-backup)
                last_backup_dir="$2"
                shift 2
                ;;
            *)
                # 收集位置参数
                positional_args+=("$1")
                shift
                ;;
        esac
    done

    # --- 分配位置参数 ---
    # 预期顺序: source_paths_str, target_base_dir, [exclude_patterns_str]
    if [[ ${#positional_args[@]} -lt 2 ]]; then
        log_error "rsync_backup: 参数不足。需要源路径和目标基础路径。"
        return 1
    fi
    source_paths_str="${positional_args[0]}"
    target_base_dir="${positional_args[1]}"
    # backup_desc="${positional_args[2]}" # Removed parameter
    if [[ ${#positional_args[@]} -ge 3 ]]; then
        exclude_patterns_str="${positional_args[2]}" # Excludes is now the 3rd positional arg
    fi

    # --- 参数验证 ---
    if [[ -z "$source_paths_str" ]]; then
        log_error "rsync_backup: 源路径不能为空。"
        return 1
    fi
    if [[ -z "$target_base_dir" ]]; then
        log_error "rsync_backup: 目标基础路径不能为空。"
        return 1
    fi
     # Removed backup_desc validation

    # --- 构建 rsync 选项 ---
    # 进度显示
    # 检查全局配置变量 SHOW_PROGRESS 是否为 false，如果是，则覆盖参数设置
    if [[ "${SHOW_PROGRESS:-true}" == "false" ]]; then
        show_progress=false
    fi
    if [[ "$show_progress" == "true" ]]; then
        rsync_opts+=" --info=progress2"
    fi

    # 差异备份
    # 检查全局配置变量 DIFF_BACKUP 是否为 true
    if [[ "${DIFF_BACKUP:-false}" == "true" ]]; then
        enable_diff=true
        # 如果全局启用差异备份，尝试查找上次备份目录
        if [[ -z "$last_backup_dir" ]]; then
             find_last_backup # 调用模块查找，结果在 LAST_BACKUP_DIR
             last_backup_dir="$LAST_BACKUP_DIR" # 使用找到的目录
        fi
    fi

    if [[ "$enable_diff" == "true" ]]; then
        if [[ -n "$last_backup_dir" && -d "$last_backup_dir" ]]; then
            # 确保 last_backup_dir 是绝对路径或相对于 CWD 的正确路径
            # rsync 需要一个有效的目录用于 --link-dest
            # 如果 target_base_dir 是完整路径，last_backup_dir 也应该是
            # 假设 last_backup_dir 已经是正确的路径
            rsync_opts+=" --link-dest=\"$last_backup_dir\""
            log_info "启用差异备份，对比目录: $last_backup_dir"
        else
            log_warn "请求了差异备份 (--diff 或全局配置)，但未找到或提供有效的上次备份目录。将执行完整备份。"
            enable_diff=false # 禁用差异备份
        fi
    fi

    # 排除项
    if [[ -n "$exclude_patterns_str" ]]; then
        log_debug "处理排除模式: $exclude_patterns_str"
        local exclude_pattern
        # 将空格分隔的字符串转换为单独的 --exclude 参数
        for exclude_pattern in $exclude_patterns_str; do
             # 避免添加空的排除项
             if [[ -n "$exclude_pattern" ]]; then
                 rsync_opts+=" --exclude=\"$exclude_pattern\""
             fi
        done
    fi

    # --- 准备执行 ---
    # 确保目标基础目录存在
    if ! check_and_create_directory "$target_base_dir"; then
         log_error "rsync_backup: 无法创建或访问目标基础目录: $target_base_dir"
         return 1
    fi

    # 将源路径字符串转换为数组，以便正确处理带空格的路径（如果需要）
    # 但 rsync 通常可以直接接受空格分隔的源列表
    # 为了安全起见，如果源路径可能包含空格，需要更复杂的处理
    # 这里假设源路径不包含需要特殊处理的空格

    local cmd_to_run="rsync $rsync_opts $source_paths_str \"$target_base_dir/\""
    # 注意目标目录末尾的 / 很重要，表示将源复制到此目录下

    log_info "准备执行备份: $source_paths_str -> $target_base_dir/"
    log_debug "执行命令: $cmd_to_run" # 记录完整命令用于调试

    # --- 执行命令 ---
    local exit_code=0
    if [[ "$enable_retry" == "true" ]]; then
        log_info "使用重试机制执行 (最多 $max_retries 次，间隔 $retry_delay 秒)..."
        # 注意：exec_with_retry 的第5个参数是 show_progress 布尔值，但它内部可能不直接使用它来控制 rsync 进度
        # rsync 的进度由 --info=progress2 控制，这里传递 show_progress 主要用于 exec_with_retry 的日志
        # Derive a description for exec_with_retry from source/target
        local retry_desc="备份 $source_paths_str"
        if ! exec_with_retry "$cmd_to_run" "$retry_desc" "$max_retries" "$retry_delay" "$show_progress"; then
            exit_code=$?
            # rsync 退出码 24 表示部分文件传输因源文件消失而出错，通常可接受
            if [[ $exit_code -eq 24 ]]; then
                 log_warn "备份 '$source_paths_str' 完成 (重试后)，但部分文件在传输过程中消失 (退出码: 24)"
                 exit_code=0 # 视为成功
            else
                 log_error "备份 '$source_paths_str' 失败 (重试后)，退出码: $exit_code"
            fi
        else
             log_notice "备份 '$source_paths_str' 成功 (重试后)"
             exit_code=0 # 确保成功时 exit_code 为 0
        fi
    else
        # 直接执行
        eval "$cmd_to_run"
        exit_code=$?
        if [[ $exit_code -eq 0 ]]; then
            log_notice "备份 '$source_paths_str' 成功"
        else
            # rsync 退出码 24 表示部分文件传输因源文件消失而出错，通常可接受
            if [[ $exit_code -eq 24 ]]; then
                 log_warn "备份 '$source_paths_str' 完成，但部分文件在传输过程中消失 (退出码: 24)"
                 exit_code=0 # 视为成功
            else
                 log_error "备份 '$source_paths_str' 失败，退出码: $exit_code"
            fi
        fi
    fi
    
    return $exit_code
}

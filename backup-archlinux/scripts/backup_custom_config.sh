# 备份自定义路径
# 功能：备份用户在配置文件中指定的自定义路径
# 读取配置文件中的自定义路径，排除项目，目标路径
# 将读取的路径及自身的属性和一些特效传递给rsync_backup函数进行备份。
# 参数：
#   $1 - 源路径
#   $2 - 目标路径
#   $3 - 备份类型描述
#   $4 - 排除参数（可选，格式为空格分隔的字符串）
backup_custom_paths() {
    log_section "开始备份自定义路径" $LOG_LEVEL_NOTICE

    if [[ "$BACKUP_CUSTOM_PATHS" != "true" ]]; then
        log_info "根据配置，跳过备份自定义路径。"
        return 0 # Not an error, just skipped
    fi

    if [[ -z "$CUSTOM_PATHS" ]]; then
        log_warn "自定义路径列表 (CUSTOM_PATHS) 为空，跳过备份。"
        return 0
    fi

    local target_base_dir="$BACKUP_DIR/custom" # 目标基础目录
    local exclude_patterns="" # 排除模式字符串
    local overall_status=0 # 0 for success, 1 for failure

    # 从配置文件读取排除模式
    if [[ -n "$EXCLUDE_CUSTOM_PATHS" ]]; then
        exclude_patterns="$EXCLUDE_CUSTOM_PATHS"
        log_debug "自定义路径排除模式: ${exclude_patterns}"
    fi

    # 确保目标基础目录存在
    if ! check_and_create_directory "$target_base_dir"; then
         log_error "无法创建或访问自定义路径的目标目录: $target_base_dir"
         return 1
    fi

    # 循环处理每个自定义路径
    for item in $CUSTOM_PATHS; do
        # 检查源是否存在
        if [[ ! -e "$item" ]]; then
            log_warn "自定义路径源不存在，跳过: $item"
            continue # 跳过不存在的路径
        fi

        # local backup_desc="自定义路径 ($item)" # Removed parameter
        log_info "正在准备备份自定义路径从 '$item' 到 '$target_base_dir/'..."

        # 为每个路径调用核心 rsync 备份函数
        # 参数: 源路径(单个), 目标基础路径, [排除模式(字符串)]
        if ! rsync_backup "$item" "$target_base_dir" "$exclude_patterns"; then
            log_error "自定义路径 '$item' 备份失败。"
            overall_status=1 # 标记失败
            # 不立即返回，继续尝试备份其他路径
        else
            log_notice "自定义路径 '$item' 备份成功 (rsync完成)。"
        fi
    done

    if [[ $overall_status -eq 0 ]]; then
        log_notice "所有自定义路径备份完成。" # 使用 notice 级别表示整体完成
        return 0
    else
        log_error "部分自定义路径备份失败。"
        return 1 # 返回错误码表示至少有一个失败
    fi
}
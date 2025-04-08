# 备份用户配置文件
# 功能：备份用户主目录下的配置文件和目录
# 读取配置文件中的自定义路径，排除项目，目标路径
# 将读取的路径及自身的属性和一些特效传递给rsync_backup函数进行备份。
# 参数：
#   $1 - 源路径
#   $2 - 目标路径
#   $3 - 备份类型描述
#   $4 - 排除参数（可选，格式为空格分隔的字符串）
backup_user_config() {
    log_section "开始备份用户配置 (Home)" $LOG_LEVEL_NOTICE

    if [[ "$BACKUP_USER_CONFIG" != "true" ]]; then
        log_info "根据配置，跳过备份用户配置。"
        return 0 # Not an error, just skipped
    fi

    if [[ -z "$USER_CONFIG_FILES" ]]; then
        log_warn "用户配置文件列表 (USER_CONFIG_FILES) 为空，跳过备份。"
        return 0
    fi

    local home_dir="$REAL_HOME" # 获取用户主目录
    local source_paths="" # 用于构建传递给 rsync_backup 的源路径字符串
    local target_base_dir="$BACKUP_DIR/home" # 目标基础目录
    # local backup_desc="用户配置 (Home)" # Removed parameter
    local exclude_patterns="" # 排除模式字符串

    # 构建源路径字符串
    for item in $USER_CONFIG_FILES; do
        local full_path="$home_dir/$item"
        # 检查源是否存在，避免 rsync 报错
        if [[ -e "$full_path" ]]; then
            source_paths+="$full_path "
        else
            log_warn "用户配置源不存在，跳过: $full_path"
        fi
    done

    # 去除末尾空格
    source_paths=$(echo "$source_paths" | sed 's/ *$//')

    if [[ -z "$source_paths" ]]; then
        log_warn "没有有效的用户配置源路径可备份。"
        return 0
    fi

    log_debug "要备份的用户配置源路径: ${source_paths}"

    # 从配置文件读取排除模式
    if [[ -n "$EXCLUDE_USER_CONFIGS" ]]; then
        exclude_patterns="$EXCLUDE_USER_CONFIGS"
        log_debug "用户配置排除模式: ${exclude_patterns}"
    fi

    log_info "正在准备备份用户配置从 '$home_dir' 到 '$target_base_dir/'..." # 目标路径加 /

    # 调用核心 rsync 备份函数
    # 参数: 源路径(字符串), 目标基础路径, [排除模式(字符串)]
    if rsync_backup "$source_paths" "$target_base_dir" "$exclude_patterns"; then
        log_notice "用户配置备份成功 (rsync完成)。"
        return 0
    else
        log_error "用户配置备份失败。"
        return 1 # 返回错误码表示失败
    fi
}
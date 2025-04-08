# 备份系统配置文件
# 功能：备份系统配置文件（主要是/etc目录）
# 读取配置文件中的自定义路径，排除项目，目标路径
# 将读取的路径及自身的属性和一些特效传递给rsync_backup函数进行备份。
# 参数：
#   $1 - 源路径
#   $2 - 目标路径
#   $3 - 备份类型描述
#   $4 - 排除参数（可选，格式为空格分隔的字符串）
backup_system_config() {
    log_section "开始备份系统配置 (/etc)" $LOG_LEVEL_NOTICE

    if [[ "$BACKUP_SYSTEM_CONFIG" != "true" ]]; then
        log_info "根据配置，跳过备份系统配置。"
        return 0 # Not an error, just skipped
    fi

    local source_dir="/etc" # 系统配置源目录
    local target_base_dir="$BACKUP_DIR/etc" # 目标基础目录，rsync_backup 会处理子目录
    # local backup_desc="系统配置 (/etc)" # Removed parameter
    local exclude_patterns="" # 传递给 rsync_backup 的排除模式字符串

    # 从配置文件读取排除模式
    if [[ -n "$EXCLUDE_SYSTEM_CONFIGS" ]]; then
        exclude_patterns="$EXCLUDE_SYSTEM_CONFIGS"
        log_debug "系统配置排除模式: ${exclude_patterns}"
    fi

    log_info "正在准备备份系统配置从 '$source_dir' 到 '$target_base_dir/'..." # 目标路径加 /

    # 调用核心 rsync 备份函数
    # 参数: 源路径(字符串), 目标基础路径, [排除模式(字符串)]
    if rsync_backup "$source_dir" "$target_base_dir" "$exclude_patterns"; then
        log_notice "系统配置备份成功 (rsync完成)。"
        # 如果启用了验证，则执行统计验证
        if [[ "$VERIFY_BACKUP" == "true" ]]; then
            log_info "开始执行系统配置统计验证..."
            # 准备排除项字符串 (换行符分隔)
            local excludes_string=""
            local item
            for item in $exclude_patterns; do
                 excludes_string+="${item}\n"
            done
            # 去掉末尾的换行符 (如果存在)
            excludes_string=${excludes_string%\\n}

            if ! verify_backup_stats "$source_dir" "$target_base_dir" "系统配置 (统计验证)" "$excludes_string"; then
                log_error "系统配置统计验证失败。"
                return 1 # 验证失败也算整体失败
            else
                log_info "系统配置统计验证通过。"
                return 0 # rsync 和验证都成功
            fi
        else
            return 0 # rsync 成功，验证跳过
        fi
    else
        log_error "系统配置备份失败。"
        return 1 # 返回错误码表示失败
    fi
}
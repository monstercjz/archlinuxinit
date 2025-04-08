#!/bin/bash

# 依赖: logging.sh (log 函数), utils.sh (exec_with_retry, check_file_integrity, create_recovery_point)

# 备份用户配置文件
# 功能：备份用户主目录下的配置文件和目录
# 参数：无
# 全局变量依赖:
#   BACKUP_USER_CONFIG, BACKUP_DIR, REAL_HOME, USER_CONFIG_FILES,
#   EXCLUDE_USER_CONFIGS, DIFF_BACKUP, LAST_BACKUP_DIR, USE_PROGRESS_BAR, LOG_FILE
# 返回值：
#   0 - 备份成功或部分成功但关键配置已备份
#   1 - 关键配置备份失败
# 错误处理：
#   检查用户主目录是否存在
#   对关键配置使用重试机制
#   验证备份完整性
# 备份内容：
#   - 根据配置文件中的USER_CONFIG_FILES变量指定的文件和目录
# 特性：
#   - 区分关键配置和非关键配置
#   - 支持差异备份（如果启用）
#   - 支持进度显示
#   - 备份完成后创建恢复点
# 使用示例：
#   backup_user_config || log "ERROR" "用户配置备份失败"
backup_user_config() {
    if [ "${BACKUP_USER_CONFIG:-true}" != "true" ]; then
        log "INFO" "跳过用户配置备份 (根据配置)"
        return 0
    fi

    log "INFO" "开始备份用户配置文件 (用户: $REAL_USER)..."
    local home_backup_dir="${BACKUP_DIR}/home"
    mkdir -p "$home_backup_dir" # 确保目标目录存在

    # 检查用户主目录是否存在
    if [ ! -d "$REAL_HOME" ]; then
        log "ERROR" "用户主目录不存在: $REAL_HOME"
        return 1
    fi

    # 构建排除参数
    local exclude_params=""
    read -ra exclude_array <<< "${EXCLUDE_USER_CONFIGS:-}"
    for item in "${exclude_array[@]}"; do
        # rsync 的 --exclude 模式是相对于源目录的
        exclude_params+=" --exclude=$item"
        log "INFO" "用户配置排除项: $item"
    done

    # 差异备份参数
    local diff_params=""
    if [ "${DIFF_BACKUP:-false}" = "true" ] && [ -n "$LAST_BACKUP_DIR" ] && [ -d "$LAST_BACKUP_DIR/home" ]; then
        log "INFO" "使用差异备份模式，参考上次备份: $LAST_BACKUP_DIR/home"
        # 确保 link-dest 路径是绝对路径
        diff_params="--link-dest=${LAST_BACKUP_DIR}/home"
    fi

    # 从配置文件中读取用户配置文件列表
    read -ra user_files_array <<< "${USER_CONFIG_FILES:-}"

    # 统计成功和失败的备份
    local success_count=0
    local fail_count=0
    local critical_fail=false
    # 定义关键配置项（相对于 $REAL_HOME）
    local critical_configs=(".ssh" ".gnupg" ".config") # 可以根据需要调整

    if [ ${#user_files_array[@]} -eq 0 ]; then
        log "WARN" "配置文件中未定义 USER_CONFIG_FILES，跳过用户配置备份"
        return 0
    fi

    log "INFO" "准备备份 ${#user_files_array[@]} 个用户配置项..."

    for item in "${user_files_array[@]}"; do
        local src_path="$REAL_HOME/$item"
        # 目标路径直接放在 home_backup_dir 下
        local dest_path="${home_backup_dir}/$item"

        if [ ! -e "$src_path" ]; then
            log "DEBUG" "源路径不存在，跳过: $src_path"
            continue # 跳过不存在的源文件/目录
        fi

        # 检查是否在排除列表中 (简单匹配，rsync 的 --exclude 更可靠)
        # rsync 会处理 --exclude，这里主要是为了日志记录
        local is_excluded=false
        for exclude_item in "${exclude_array[@]}"; do
             # 使用更安全的匹配方式
             if [[ "$item" == "$exclude_item" || "$item" == "$exclude_item/"* ]]; then
                is_excluded=true
                log "INFO" "跳过排除项 (rsync 会处理): $item"
                break
            fi
        done
        if [ "$is_excluded" = true ]; then
            continue
        fi

        # 创建目标目录的父目录
        mkdir -p "$(dirname "$dest_path")"

        # 检查是否为关键配置
        local is_critical=false
        for critical_item in "${critical_configs[@]}"; do
            if [[ "$item" == "$critical_item" || "$item" == "$critical_item/"* ]]; then
                is_critical=true
                break
            fi
        done

        # 使用 rsync 备份，对关键配置使用重试机制，并显示进度
        local rsync_cmd="rsync -aAX --delete ${exclude_params} ${diff_params}"
        local backup_desc="用户配置备份: $item"

        if [ "${USE_PROGRESS_BAR:-false}" == "true" ]; then
            rsync_cmd+=" --info=progress2 \"$src_path\" \"$dest_path\""
        else
            rsync_cmd+=" --progress \"$src_path\" \"$dest_path\""
        fi
        rsync_cmd+=" >> \"$LOG_FILE\" 2>&1"

        local current_fail=false
        if $is_critical; then
            backup_desc="关键用户配置备份: $item"
            if ! exec_with_retry "$rsync_cmd" "$backup_desc" 3 5 true; then
                log "ERROR" "关键配置备份失败: $item"
                critical_fail=true
                current_fail=true
            fi
        else
            # 非关键配置，尝试一次
            if ! exec_with_retry "$rsync_cmd" "$backup_desc" 1 0 true; then # 尝试1次，无延迟
                 log "WARN" "备份失败: $item"
                 current_fail=true
            fi
        fi

        if $current_fail; then
            fail_count=$((fail_count + 1))
        else
            log "INFO" "已备份: $item"
            success_count=$((success_count + 1))
            # 验证备份完整性 (只检查目标是否存在)
            check_file_integrity "$dest_path" "备份的用户配置: $item" false # 不检查权限，因为可能刚创建
        fi
    done

    # 报告备份结果
    if [ $fail_count -eq 0 ]; then
        log "INFO" "用户配置文件备份完成，成功备份 $success_count 项"
        create_recovery_point "user_config"
        return 0
    elif [ "$critical_fail" = true ]; then
        log "ERROR" "用户配置文件备份部分失败，$success_count 成功，$fail_count 失败，包含关键配置失败"
        return 1
    else
        log "WARN" "用户配置文件备份部分失败，$success_count 成功，$fail_count 失败，但关键配置已备份"
        create_recovery_point "user_config"
        return 0 # 允许部分失败，只要关键配置成功
    fi
}

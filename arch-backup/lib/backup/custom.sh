#!/bin/bash

# 依赖: logging.sh (log 函数), utils.sh (exec_with_retry, check_file_integrity, create_recovery_point)

# 备份自定义路径
# 功能：备份用户在配置文件中指定的自定义路径
# 参数：无
# 全局变量依赖:
#   BACKUP_CUSTOM_PATHS, BACKUP_DIR, CUSTOM_PATHS, EXCLUDE_CUSTOM_PATHS,
#   DIFF_BACKUP, LAST_BACKUP_DIR, USE_PROGRESS_BAR, LOG_FILE
# 返回值：
#   0 - 备份成功或部分成功但成功率高于80%
#   1 - 备份大部分失败（成功率低于80%）
# 错误处理：
#   检查自定义路径是否存在
#   检查路径权限
#   使用重试机制执行rsync命令
#   验证备份完整性
# 备份内容：
#   - 根据配置文件中的CUSTOM_PATHS变量指定的路径
# 特性：
#   - 支持差异备份（如果启用）
#   - 支持进度显示
#   - 统计成功和失败的备份数量
#   - 备份完成后创建恢复点
# 使用示例：
#   backup_custom_paths || log "ERROR" "自定义路径备份失败"
backup_custom_paths() {
    if [ "${BACKUP_CUSTOM_PATHS:-true}" != "true" ]; then
        log "INFO" "跳过自定义路径备份 (根据配置)"
        return 0
    fi

    # 从配置文件中读取自定义路径列表
    read -ra custom_paths_array <<< "${CUSTOM_PATHS:-}"

    if [ ${#custom_paths_array[@]} -eq 0 ]; then
        log "INFO" "没有配置自定义路径 (CUSTOM_PATHS 为空)，跳过备份"
        return 0
    fi

    log "INFO" "开始备份自定义路径..."
    local custom_backup_dir="${BACKUP_DIR}/custom"
    mkdir -p "$custom_backup_dir" # 确保目标目录存在

    # 构建排除参数
    local exclude_params=""
    read -ra exclude_array <<< "${EXCLUDE_CUSTOM_PATHS:-}"
    for item in "${exclude_array[@]}"; do
        # rsync 的 --exclude 模式
        exclude_params+=" --exclude=$item"
        log "INFO" "自定义路径排除模式: $item"
    done

    # 差异备份参数
    local diff_params=""
    if [ "${DIFF_BACKUP:-false}" = "true" ] && [ -n "$LAST_BACKUP_DIR" ] && [ -d "$LAST_BACKUP_DIR/custom" ]; then
        log "INFO" "使用差异备份模式，参考上次备份: $LAST_BACKUP_DIR/custom"
        # 确保 link-dest 路径是绝对路径
        diff_params="--link-dest=${LAST_BACKUP_DIR}/custom"
    fi

    # 统计成功和失败的备份
    local success_count=0
    local fail_count=0
    local total_paths=${#custom_paths_array[@]}

    log "INFO" "共有 $total_paths 个自定义路径需要备份"

    for path in "${custom_paths_array[@]}"; do
        if [ ! -e "$path" ]; then
            log "WARN" "自定义路径不存在，跳过: $path"
            fail_count=$((fail_count + 1))
            continue
        fi

        # 获取路径的基本名称，用于目标目录
        local base_name
        base_name=$(basename "$path")
        # 如果 base_name 是 /，则使用 root 代替，避免路径问题
        [ "$base_name" == "/" ] && base_name="root"
        local dest_path="${custom_backup_dir}/${base_name}"

        log "INFO" "备份自定义路径: $path -> $dest_path"

        # 检查路径权限
        if [ ! -r "$path" ]; then
            # 尝试用 sudo 检查
            if sudo test -r "$path"; then
                log "DEBUG" "自定义路径 $path 可通过 sudo 读取"
            else
                log "WARN" "自定义路径不可读 (即使使用 sudo): $path，跳过"
                fail_count=$((fail_count + 1))
                continue
            fi
        fi

        # 使用 rsync 备份自定义路径，带进度显示和重试功能
        # 需要 sudo 来处理可能的权限问题
        local rsync_cmd="sudo rsync -aAX --delete ${exclude_params} ${diff_params}"
        local backup_desc="自定义路径备份: $path"

        if [ "${USE_PROGRESS_BAR:-false}" == "true" ]; then
            rsync_cmd+=" --info=progress2 \"$path\" \"$dest_path\""
        else
            rsync_cmd+=" --progress \"$path\" \"$dest_path\""
        fi
        rsync_cmd+=" >> \"$LOG_FILE\" 2>&1"

        if exec_with_retry "$rsync_cmd" "$backup_desc" 3 5 true; then
            log "INFO" "自定义路径备份完成: $path"
            success_count=$((success_count + 1))
            # 验证备份完整性 (只检查目标是否存在)
            check_file_integrity "$dest_path" "备份的自定义路径: $path" false
        else
            log "ERROR" "自定义路径备份失败: $path，即使在多次尝试后"
            fail_count=$((fail_count + 1))
        fi
    done

    # 报告备份结果
    if [ $total_paths -eq 0 ]; then # 再次检查以防万一
         log "INFO" "没有有效的自定义路径进行备份"
         return 0
    fi

    local success_percent=0
    if [ $total_paths -gt 0 ]; then
        success_percent=$((success_count * 100 / total_paths))
    fi

    if [ $fail_count -eq 0 ]; then
        log "INFO" "自定义路径备份完成，成功率: 100%"
        create_recovery_point "custom_paths"
        return 0
    elif [ $success_percent -ge 80 ]; then
        log "WARN" "自定义路径备份部分失败，成功率: ${success_percent}% ($success_count 成功, $fail_count 失败)"
        create_recovery_point "custom_paths"
        return 0 # 允许部分失败
    else
        log "ERROR" "自定义路径备份大部分失败，成功率: ${success_percent}% ($success_count 成功, $fail_count 失败)"
        return 1
    fi
}

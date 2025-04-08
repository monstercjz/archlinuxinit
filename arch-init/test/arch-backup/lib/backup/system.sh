#!/bin/bash

# 依赖: logging.sh (log 函数), utils.sh (exec_with_retry, check_file_integrity, create_recovery_point)

# 备份系统配置文件
# 功能：备份系统配置文件（主要是/etc目录）
# 参数：无
# 全局变量依赖:
#   BACKUP_SYSTEM_CONFIG, BACKUP_DIR, EXCLUDE_SYSTEM_CONFIGS,
#   DIFF_BACKUP, LAST_BACKUP_DIR, USE_PROGRESS_BAR, LOG_FILE
# 返回值：
#   0 - 备份成功
#   1 - 备份失败
# 错误处理：
#   检查关键系统文件是否存在且可读
#   使用重试机制执行rsync命令
#   验证备份完整性
# 备份内容：
#   - /etc目录下的所有文件（排除配置中指定的项目）
# 特性：
#   - 支持差异备份（如果启用）
#   - 支持进度显示
#   - 备份完成后创建恢复点
# 使用示例：
#   backup_system_config || log "ERROR" "系统配置备份失败"
backup_system_config() {
    if [ "${BACKUP_SYSTEM_CONFIG:-true}" != "true" ]; then
        log "INFO" "跳过系统配置备份 (根据配置)"
        return 0
    fi

    log "INFO" "开始备份系统配置文件 (/etc)..."
    local etc_backup_dir="${BACKUP_DIR}/etc"
    mkdir -p "$etc_backup_dir" # 确保目标目录存在

    # 检查关键系统文件是否存在且可读
    if [ ! -d "/etc" ]; then
        log "FATAL" "/etc 目录不存在或不可访问"
        return 1
    fi

    # 检查关键配置文件
    local critical_files=("/etc/fstab" "/etc/passwd" "/etc/group" "/etc/shadow" "/etc/hosts")
    local missing_files=0

    for file in "${critical_files[@]}"; do
        if [ ! -f "$file" ]; then
            log "WARN" "关键系统文件不存在: $file"
            missing_files=$((missing_files + 1))
        elif [ ! -r "$file" ]; then
            # 尝试用 sudo 检查是否可读
             if sudo test -r "$file"; then
                 log "DEBUG" "关键系统文件 $file 可通过 sudo 读取"
             else
                 log "WARN" "关键系统文件不可读 (即使使用 sudo): $file"
             fi
        fi
    done

    if [ $missing_files -gt 0 ]; then
        log "WARN" "有 $missing_files 个关键系统文件缺失，备份可能不完整"
    fi

    # 构建排除参数
    local exclude_params=""
    # 使用 read -ra 将字符串分割成数组，处理带空格的路径
    read -ra exclude_array <<< "${EXCLUDE_SYSTEM_CONFIGS:-}"
    for item in "${exclude_array[@]}"; do
        # 确保排除路径以 / 开头，匹配 rsync 行为
        if [[ "$item" == /* ]]; then
            exclude_params+=" --exclude=$item"
            log "INFO" "系统配置排除项: $item"
        else
            log "WARN" "无效的系统配置排除项 (必须是绝对路径): $item"
        fi
    done

    # 差异备份参数
    local diff_params=""
    if [ "${DIFF_BACKUP:-false}" = "true" ] && [ -n "$LAST_BACKUP_DIR" ] && [ -d "$LAST_BACKUP_DIR/etc" ]; then
        log "INFO" "使用差异备份模式，参考上次备份: $LAST_BACKUP_DIR/etc"
        # 确保 link-dest 路径是绝对路径
        diff_params="--link-dest=${LAST_BACKUP_DIR}/etc"
    fi

    # 使用 rsync 备份 /etc 目录，带进度显示和重试功能
    # 注意：rsync 源路径末尾的 / 很重要，表示复制目录内容而非目录本身
    local rsync_cmd="sudo rsync -aAX --delete ${exclude_params} ${diff_params}"

    if [ "${USE_PROGRESS_BAR:-false}" == "true" ]; then
        # 使用 pv 工具显示进度条 (需要调整命令结构)
        # rsync 的 --info=progress2 结合 pv 可能不直接工作，优先使用 rsync 内置
        log "INFO" "使用 rsync 内置进度显示 (pv 暂不支持此模式)"
        rsync_cmd+=" --info=progress2 /etc/ \"${etc_backup_dir}/\""
    else
        # 使用 rsync 内置详细进度显示
        log "INFO" "使用 rsync 内置详细进度显示功能"
        rsync_cmd+=" --progress /etc/ \"${etc_backup_dir}/\""
    fi

    # 将 rsync 输出重定向到日志文件
    rsync_cmd+=" >> \"$LOG_FILE\" 2>&1"

    if exec_with_retry "$rsync_cmd" "系统配置文件备份" 3 5 true; then
        log "INFO" "系统配置文件备份完成"

        # 验证备份完整性 (检查备份目录中的关键文件)
        if check_file_integrity "${etc_backup_dir}/passwd" "备份的系统用户文件" && \
           check_file_integrity "${etc_backup_dir}/fstab" "备份的文件系统表"; then
            log "INFO" "系统配置文件备份完整性基本验证通过"
            # 创建恢复点
            create_recovery_point "system_config"
            return 0
        else
            log "ERROR" "系统配置文件备份完整性验证失败 (关键文件检查)"
            return 1
        fi
    else
        log "ERROR" "系统配置文件备份失败，即使在多次尝试后"
        return 1
    fi
}

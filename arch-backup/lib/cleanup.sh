#!/bin/bash

# 依赖: logging.sh (log 函数)

# 清理旧备份
# 功能：根据配置的保留策略清理旧的备份和日志文件
# 参数：无
# 全局变量依赖:
#   BACKUP_ROOT, BACKUP_RETENTION_COUNT, LOG_RETENTION_DAYS, LOG_FILE
# 返回值：
#   0 - 清理成功或无需清理
#   1 - 清理过程中出现错误
# 错误处理：
#   如果清理过程中出现错误，会记录在日志中
# 清理内容：
#   - 超过保留数量的旧备份目录 (YYYY-MM-DD 格式)
#   - 超过保留天数的旧日志文件 (backup_*.log)
#   - 超过保留天数的旧并行日志文件 (parallel_log_*.txt)
#   - 超过保留天数的旧恢复点文件 (recovery_*.json)
#   - 超过保留天数的旧验证报告 (verification-report_*.txt)
# 特性：
#   - 按日期排序备份目录，保留最新的备份
#   - 根据BACKUP_RETENTION_COUNT配置决定保留的备份数量
#   - 根据LOG_RETENTION_DAYS配置决定保留的日志天数
cleanup_old_backups() {
    log "INFO" "开始清理旧备份和日志..."
    local cleanup_errors=0

    # --- 清理旧备份目录 ---
    log "INFO" "检查旧备份目录 (保留最近 $BACKUP_RETENTION_COUNT 个)..."
    # 获取所有符合日期格式的备份目录并按名称排序（旧的在前）
    local all_backups
    all_backups=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" -printf '%f\n' | sort)
    local backup_count=$(echo "$all_backups" | wc -l)

    if [ -z "$all_backups" ]; then
         backup_count=0
    fi

    # 确保 BACKUP_RETENTION_COUNT 是有效的数字
    if ! [[ "$BACKUP_RETENTION_COUNT" =~ ^[0-9]+$ ]]; then
        log "WARN" "BACKUP_RETENTION_COUNT ('$BACKUP_RETENTION_COUNT') 无效，使用默认值 7"
        BACKUP_RETENTION_COUNT=7
    fi

    if [ $backup_count -gt $BACKUP_RETENTION_COUNT ]; then
        local to_delete_count=$((backup_count - BACKUP_RETENTION_COUNT))
        log "INFO" "发现 $backup_count 个备份，超过保留数量 $BACKUP_RETENTION_COUNT，将删除 $to_delete_count 个最旧的备份"

        # 获取要删除的目录列表
        local backups_to_delete=$(echo "$all_backups" | head -n "$to_delete_count")

        for backup_dir_name in $backups_to_delete; do
            local full_path="${BACKUP_ROOT}/${backup_dir_name}"
            log "INFO" "删除旧备份目录: $full_path"
            if ! rm -rf "$full_path"; then
                log "ERROR" "删除旧备份目录失败: $full_path"
                cleanup_errors=$((cleanup_errors + 1))
            fi
        done
    else
        log "INFO" "备份数量 ($backup_count) 未超过保留限制 ($BACKUP_RETENTION_COUNT)，无需清理备份目录"
    fi

    # --- 清理旧日志文件 ---
    # 确保 LOG_RETENTION_DAYS 是有效的数字
    if ! [[ "$LOG_RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
        log "WARN" "LOG_RETENTION_DAYS ('$LOG_RETENTION_DAYS') 无效，使用默认值 30"
        LOG_RETENTION_DAYS=30
    fi

    log "INFO" "清理超过 $LOG_RETENTION_DAYS 天的旧日志文件..."
    # 清理 backup_*.log
    find "$BACKUP_ROOT" -maxdepth 1 -name "backup_*.log" -type f -mtime "+$LOG_RETENTION_DAYS" -print -delete || {
        log "WARN" "清理旧 backup 日志文件时出错"
        cleanup_errors=$((cleanup_errors + 1))
    }
    # 清理 parallel_log_*.txt
    find "$BACKUP_ROOT" -maxdepth 1 -name "parallel_log_*.txt" -type f -mtime "+$LOG_RETENTION_DAYS" -print -delete || {
        log "WARN" "清理旧 parallel 日志文件时出错"
        cleanup_errors=$((cleanup_errors + 1))
    }
    # 清理 recovery_*.json
    find "$BACKUP_ROOT" -maxdepth 1 -name "recovery_*.json" -type f -mtime "+$LOG_RETENTION_DAYS" -print -delete || {
        log "WARN" "清理旧恢复点文件时出错"
        cleanup_errors=$((cleanup_errors + 1))
    }
    # 清理 verification-report_*.txt
    find "$BACKUP_ROOT" -maxdepth 1 -name "verification-report_*.txt" -type f -mtime "+$LOG_RETENTION_DAYS" -print -delete || {
        log "WARN" "清理旧验证报告文件时出错"
        cleanup_errors=$((cleanup_errors + 1))
    }

    if [ $cleanup_errors -eq 0 ]; then
        log "INFO" "旧备份和日志清理完成"
        return 0
    else
        log "WARN" "旧备份和日志清理过程中出现 $cleanup_errors 个错误"
        return 1
    fi
}

# 清理恢复点文件（通常在备份成功结束时调用）
# 功能：删除所有恢复点文件
# 参数：无
# 全局变量依赖:
#   BACKUP_ROOT
# 返回值：无
cleanup_recovery_points() {
    log "INFO" "清理所有恢复点文件..."
    find "$BACKUP_ROOT" -maxdepth 1 -name "recovery_*.json" -type f -delete || {
        log "WARN" "清理恢复点文件时出错"
    }
}

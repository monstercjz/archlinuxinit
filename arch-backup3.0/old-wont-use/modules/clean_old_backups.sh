# 清理旧备份
# 功能：根据配置的保留策略清理旧的备份和日志文件
# 参数：无
# 返回值：无
# 错误处理：
#   如果清理过程中出现错误，会记录在日志中，但不会中断脚本执行
# 清理内容：
#   - 超过保留数量的旧备份目录
#   - 超过保留天数的旧日志文件
# 特性：
#   - 按日期排序备份目录，保留最新的备份
#   - 根据BACKUP_RETENTION_COUNT配置决定保留的备份数量
#   - 根据LOG_RETENTION_DAYS配置决定保留的日志天
cleanup_old_backups() {
    log "INFO" "清理旧备份..."
    
    # 获取所有备份目录并按日期排序
    local all_backups=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" | sort))
    local backup_count=${#all_backups[@]}   
    # 如果备份数量超过保留数量，则删除最旧的备份
    if [ $backup_count -gt $BACKUP_RETENTION_COUNT ]; then
        local to_delete=$((backup_count - BACKUP_RETENTION_COUNT))
        log "INFO" "发现 $backup_count 个备份，保留 $BACKUP_RETENTION_COUNT 个，将删除 $to_delete 个最旧的备份"
        
        for ((i=0; i<$to_delete; i++)); do
            log "INFO" "删除旧备份: ${all_backups[$i]}"
            rm -rf "${all_backups[$i]}"
        done
    else
        log "INFO" "备份数量 ($backup_count) 未超过保留限制 ($BACKUP_RETENTION_COUNT)，无需清理"
    fi
    
    # 清理旧日志文件
    find "$BACKUP_ROOT" -name "backup_*.log" -type f -mtime +$LOG_RETENTION_DAYS -delete
    log "INFO" "已清理超过 $LOG_RETENTION_DAYS 天的日志文件"
}
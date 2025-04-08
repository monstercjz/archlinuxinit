# 查找最近的备份目录
# 功能：查找最近的备份目录，用于差异备份
# 参数：无
# 返回值：
#   0 - 总是返回成功
# 副作用：
#   设置全局变量LAST_BACKUP_DIR为找到的最近备份目录路径
# 错误处理：
#   如果没有找到以前的备份，会记录信息并继续执行完整备份
# 特性：
#   - 仅在差异备份模式下有效
#   - 按日期排序查找备份目录
# 使用示例：
#   find_last_backup
find_last_backup() {
    if [ "$DIFF_BACKUP" != "true" ]; then
        return 0
    fi
    
    log "INFO" "查找最近的备份目录..."
    
    # 获取所有备份目录并按日期排序（最新的在最后）
    local all_backups=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" | sort))
    local backup_count=${#all_backups[@]}
    
    if [ $backup_count -gt 0 ]; then
        # 获取最新的备份目录
        LAST_BACKUP_DIR="${all_backups[$((backup_count-1))]}"
        log "INFO" "找到最近的备份目录: $LAST_BACKUP_DIR"
    else
        log "INFO" "没有找到以前的备份，将进行完整备份"
    fi
}
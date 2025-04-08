# 备份系统日志
# 功能：备份系统日志
# 参数：无
# 返回值：
#   0 - 备份成功
#   1 - 备份失败
# 错误处理：
#   检查journalctl命令是否可用
#   使用重试机制执行journalctl命令
#   验证备份文件完整性
# 备份内容：
#   - 当前年份的系统日志
# 特性：
#   - 使用临时目录进行备份，成功后移动到最终位置
#   - 备份完成后创建恢复点
# 使用示例：
#   backup_logs || log "ERROR" "系统日志备份失败"
backup_logs() {
    if [ "$BACKUP_LOGS" != "true" ]; then
        log "INFO" "跳过系统日志备份"
        return 0
    fi
    
    log "INFO" "开始备份系统日志..."
    
    # 检查 journalctl 是否可用
    if ! command -v journalctl &> /dev/null; then
        log "ERROR" "journalctl 命令不可用，无法备份系统日志"
        return 1
    fi
    
    # 创建临时目录用于存储日志
    local temp_dir="${BACKUP_DIR}/logs.tmp"
    mkdir -p "$temp_dir"
    
    # 获取当前年份
    local current_year=$(date +"%Y")
    local log_file="${temp_dir}/system-log-${current_year}.txt"
    
    # 备份当年的系统日志，带重试功能
    local journalctl_cmd="journalctl --since \"${current_year}-01-01\" --until \"${current_year}-12-31\" > \"${log_file}\" 2>> \"$LOG_FILE\""
    
    if exec_with_retry "$journalctl_cmd" "系统日志备份"; then
        log "INFO" "系统日志备份完成"
        
        # 验证备份完整性
        if check_file_integrity "$log_file" "系统日志"; then
            # 移动临时文件到最终目录
            if mv "$temp_dir"/* "${BACKUP_DIR}/logs/" 2>> "$LOG_FILE"; then
                log "INFO" "系统日志备份文件移动成功"
                rm -rf "$temp_dir"
                create_recovery_point "logs"
                return 0
            else
                log "ERROR" "系统日志备份文件移动失败"
                return 1
            fi
        else
            log "ERROR" "系统日志备份完整性验证失败"
            return 1
        fi
    else
        log "ERROR" "系统日志备份失败，即使在多次尝试后"
        return 1
    fi
}
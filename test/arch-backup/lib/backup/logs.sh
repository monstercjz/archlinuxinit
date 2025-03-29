#!/bin/bash

# 依赖: logging.sh (log 函数), utils.sh (exec_with_retry, check_file_integrity, create_recovery_point)

# 备份系统日志
# 功能：备份系统日志
# 参数：无
# 全局变量依赖:
#   BACKUP_LOGS, BACKUP_DIR, LOG_FILE
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
#   - 备份完成后创建恢复点
# 使用示例：
#   backup_logs || log "ERROR" "系统日志备份失败"
backup_logs() {
    if [ "${BACKUP_LOGS:-true}" != "true" ]; then
        log "INFO" "跳过系统日志备份 (根据配置)"
        return 0
    fi

    log "INFO" "开始备份系统日志..."
    local logs_backup_dir="${BACKUP_DIR}/logs"
    mkdir -p "$logs_backup_dir" # 确保目标目录存在

    # 检查 journalctl 是否可用
    if ! command -v journalctl &> /dev/null; then
        log "ERROR" "journalctl 命令不可用，无法备份系统日志"
        return 1
    fi

    # 获取当前年份
    local current_year=$(date +"%Y")
    local log_file="${logs_backup_dir}/system-log-${current_year}.txt"

    # 备份当年的系统日志，带重试功能
    # 使用 --no-pager 避免 journalctl 进入交互模式
    # 增加超时设置，防止 journalctl 卡住
    local journalctl_cmd="journalctl --no-pager --since \"${current_year}-01-01\" --until \"${current_year}-12-31\""

    # 将命令输出重定向到文件，错误输出到日志
    # 注意：直接重定向 > 会覆盖文件，如果需要追加则用 >>
    local full_cmd="${journalctl_cmd} > \"${log_file}\" 2>> \"$LOG_FILE\""

    # 设置一个合理的超时时间，例如 5 分钟
    if exec_with_retry "$full_cmd" "系统日志备份" 2 10 true 300; then
        log "INFO" "系统日志备份完成"

        # 验证备份完整性
        if check_file_integrity "$log_file" "系统日志"; then
            log "INFO" "系统日志备份完整性验证通过"
            create_recovery_point "logs"
            return 0
        else
            log "ERROR" "系统日志备份完整性验证失败"
            return 1
        fi
    else
        log "ERROR" "系统日志备份失败，即使在多次尝试后"
        # 检查是否因为超时失败
        if [ $? -eq 124 ]; then
            log "ERROR" "系统日志备份超时"
        fi
        return 1
    fi
}

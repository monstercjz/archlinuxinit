# 创建恢复点
# 功能：在备份过程中创建检查点，记录当前备份阶段，用于从故障中恢复
# 参数：
#   $1 - 当前备份阶段名称（如 "system_config", "user_config" 等）
# 返回值：无
# 错误处理：
#   如果恢复点文件创建失败，会记录在日志中，但不会中断脚本执行
# 恢复点信息：
#   - 时间戳
#   - 当前备份阶段
#   - 备份目录路径
#   - 已完成的备份步骤列表
# 使用示例：
#   create_recovery_point "system_config"
#   create_recovery_point "packages"
# 创建恢复点
# 功能：在备份过程中创建检查点，以便在备份中断时能够从该点继续
# 参数：
#   $1 - 备份阶段名称（如 system_config, user_config 等）
#   $2 - 额外的恢复点信息（可选，JSON格式）
# 返回值：
#   0 - 恢复点创建成功
#   1 - 恢复点创建失败
# 错误处理：
#   如果恢复点文件创建失败，会记录错误但不会中断脚本执行
# 特性：
#   - 自动清理旧的恢复点文件（保留最近5个）
#   - 记录详细的备份状态和配置信息
#   - 支持额外的自定义恢复点信息
# 使用示例：
#   create_recovery_point "system_config"
#   create_recovery_point "packages" '{"last_package":"firefox"}'  
create_recovery_point() {
    local stage=$1
    local extra_info=${2:-"{}"}
    local recovery_file="${BACKUP_ROOT}/recovery_${TIMESTAMP}_${stage}.json"
    local status=0
    
    log "INFO" "创建恢复点: $stage"
    
    # 获取系统信息
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    local kernel_version=$(uname -r 2>/dev/null || echo "unknown")
    local available_space=$(df -h "$BACKUP_ROOT" | awk 'NR==2 {print $4}' 2>/dev/null || echo "unknown")
    
    # 创建恢复点文件
    if ! cat > "$recovery_file" << EOF
{
    "timestamp": "$(date +"%Y-%m-%d %H:%M:%S")",
    "stage": "$stage",
    "backup_dir": "$BACKUP_DIR",
    "user": "$REAL_USER",
    "hostname": "$hostname",
    "kernel": "$kernel_version",
    "available_space": "$available_space",
    "backup_options": {
        "compress": "$COMPRESS_BACKUP",
        "compress_method": "$COMPRESS_METHOD",
        "diff_backup": "$DIFF_BACKUP",
        "verify_backup": "$VERIFY_BACKUP",
        "parallel_backup": "$PARALLEL_BACKUP"
    },
    "extra_info": $extra_info,
    "completed_steps": [
        $([ "$stage" == "system_config" ] && echo "\"system_config\"" || echo "")
        $([ "$stage" == "user_config" ] && echo "\"system_config\", \"user_config\"" || echo "")
        $([ "$stage" == "custom_paths" ] && echo "\"system_config\", \"user_config\", \"custom_paths\"" || echo "")
        $([ "$stage" == "packages" ] && echo "\"system_config\", \"user_config\", \"custom_paths\", \"packages\"" || echo "")
        $([ "$stage" == "logs" ] && echo "\"system_config\", \"user_config\", \"custom_paths\", \"packages\", \"logs\"" || echo "")
    ]
}
EOF
    then
        log "ERROR" "创建恢复点文件失败: $recovery_file"
        status=1
    else
        # 验证恢复点文件
        if [ -s "$recovery_file" ]; then
            log "DEBUG" "恢复点文件已创建: $recovery_file ($(stat -c%s "$recovery_file") 字节)"
            
            # 清理旧的恢复点文件，只保留最近5个
            local old_recovery_files=($(find "$BACKUP_ROOT" -name "recovery_*.json" -type f | sort -r | tail -n +6))
            if [ ${#old_recovery_files[@]} -gt 0 ]; then
                log "DEBUG" "清理 ${#old_recovery_files[@]} 个旧恢复点文件"
                for old_file in "${old_recovery_files[@]}"; do
                    rm -f "$old_file" 2>/dev/null
                done
            fi
        else
            log "WARN" "恢复点文件创建成功但为空: $recovery_file"
            status=1
        fi
    fi
    
    return $status
}
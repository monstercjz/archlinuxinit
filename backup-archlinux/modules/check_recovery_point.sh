# 检查是否存在恢复点
# 功能：检查是否存在之前中断的备份恢复点，用于从中断处继续备份
# 参数：无
# 返回值：
#   0 - 没有找到恢复点或恢复点处理完成
#   非0 - 恢复点处理失败
# 错误处理：
#   如果恢复点文件解析失败，会记录错误但继续执行完整备份
# 恢复点处理：
#   - 查找最新的恢复点文件
#   - 解析恢复点中的备份阶段和目录信息
#   - 如果是今天的恢复点，提示用户可以从中断处继续
# 使用示例：
#   check_recovery_point
check_recovery_point() {
    log "INFO" "检查是否存在恢复点..."
    
    # 查找最新的恢复点文件
    local recovery_files=($(find "$BACKUP_ROOT" -name "recovery_*.json" -type f | sort -r))
    
    if [ ${#recovery_files[@]} -eq 0 ]; then
        log "INFO" "没有找到恢复点，将进行完整备份"
        return 0
    fi
    
    local latest_recovery="${recovery_files[0]}"
    log "INFO" "找到最新的恢复点: $latest_recovery"
    
    # 解析恢复点文件（简单解析，不使用jq等工具以减少依赖）
    local recovery_timestamp=$(grep -o '"timestamp": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    local recovery_stage=$(grep -o '"stage": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    local recovery_dir=$(grep -o '"backup_dir": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    
    # 检查恢复点是否是今天的
    local today=$(date +"%Y-%m-%d")
    if [[ "$recovery_timestamp" == "$today"* ]]; then
        log "INFO" "发现今天的恢复点，上次备份在 '$recovery_stage' 阶段中断"
        log "INFO" "将从中断点继续备份"
        
        # 设置备份目录为恢复点中的目录
        if [ -d "$recovery_dir" ]; then
            BACKUP_DIR="$recovery_dir"
            log "INFO" "使用现有备份目录: $BACKUP_DIR"
            
            # 根据恢复点阶段设置跳过标志
            SKIP_SYSTEM_CONFIG=false
            SKIP_USER_CONFIG=false
            SKIP_CUSTOM_PATHS=false
            SKIP_PACKAGES=false
            SKIP_LOGS=false
            
            case "$recovery_stage" in
                "system_config")
                    SKIP_SYSTEM_CONFIG=true
                    ;;
                "user_config")
                    SKIP_SYSTEM_CONFIG=true
                    SKIP_USER_CONFIG=true
                    ;;
                "custom_paths")
                    SKIP_SYSTEM_CONFIG=true
                    SKIP_USER_CONFIG=true
                    SKIP_CUSTOM_PATHS=true
                    ;;
                "packages")
                    SKIP_SYSTEM_CONFIG=true
                    SKIP_USER_CONFIG=true
                    SKIP_CUSTOM_PATHS=true
                    SKIP_PACKAGES=true
                    ;;
                "logs")
                    SKIP_SYSTEM_CONFIG=true
                    SKIP_USER_CONFIG=true
                    SKIP_CUSTOM_PATHS=true
                    SKIP_PACKAGES=true
                    SKIP_LOGS=true
                    ;;
            esac
            
            return 0
        else
            log "WARN" "恢复点中的备份目录不存在: $recovery_dir，将创建新的备份"
        fi
    else
        log "INFO" "找到的恢复点不是今天的，将进行新的完整备份"
    fi
    
    return 0
}

# 检查文件完整性
# 功能：检查指定文件是否存在且非空，并验证文件权限
# 参数：
#   $1 - 要检查的文件路径
#   $2 - 文件描述（用于日志记录）
#   $3 - 是否检查文件权限（可选，默认为true）
# 返回值：
#   0 - 文件存在且非空
#   1 - 文件不存在
#   2 - 文件存在但为空
#   3 - 文件存在但权限不正确
# 错误处理：
#   如果文件不存在或为空，会记录错误并返回相应的状态码
#   如果指定检查权限，会验证文件是否可读
# 使用示例：
#   check_file_integrity "/path/to/file" "配置文件"
#   if ! check_file_integrity "/path/to/backup" "备份文件"; then
#     log "ERROR" "备份文件完整性检查失败"
#   fi
check_file_integrity() {
    local file_path=$1
    local desc=$2
    local check_permissions=${3:-true}
    local status=0
    
    if [ ! -e "$file_path" ]; then
        log "ERROR" "完整性检查失败: $desc 文件不存在: $file_path"
        return 1
    fi
    
    if [ -f "$file_path" ] && [ ! -s "$file_path" ]; then
        log "ERROR" "完整性检查失败: $desc 文件大小为零: $file_path"
        return 2
    fi
    
    # 检查文件权限
    if [ "$check_permissions" = true ] && [ ! -r "$file_path" ]; then
        log "ERROR" "完整性检查失败: $desc 文件不可读: $file_path"
        return 3
    fi
    
    log "DEBUG" "完整性检查通过: $desc"
    return 0
}
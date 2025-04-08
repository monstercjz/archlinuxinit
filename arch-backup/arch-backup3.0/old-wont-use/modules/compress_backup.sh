# 压缩备份
# 功能：将备份目录压缩为单个归档文件
# 参数：无
# 返回值：
#   0 - 压缩成功
#   1 - 压缩失败
# 错误处理：
#   检查压缩命令是否存在
#   如果压缩过程中出现错误，会记录并返回非零状态码
# 压缩方法：
#   - 根据COMPRESS_METHOD配置选择压缩工具（gzip, bzip2, xz）
# 特性：
#   - 先创建tar归档，再使用选定的压缩工具压缩
#   - 压缩成功后删除原始备份目录
# 使用示例：
#   compress_backup || log "ERROR" "备份压缩失败"
compress_backup() {
    if [ "$COMPRESS_BACKUP" != "true" ]; then
        log "INFO" "跳过备份压缩"
        return 0
    fi
    
    log "INFO" "开始压缩备份 (使用 $COMPRESS_METHOD)..."
    
    local compress_cmd=""
    local ext=""
    
    case "$COMPRESS_METHOD" in
        "gzip")
            compress_cmd="gzip"
            ext=".gz"
            ;;
        "bzip2")
            compress_cmd="bzip2"
            ext=".bz2"
            ;;
        "xz")
            compress_cmd="xz"
            ext=".xz"
            ;;
        *)
            log "ERROR" "未知的压缩方法: $COMPRESS_METHOD，跳过压缩"
            return 1
            ;;
    esac
    
    # 检查压缩命令是否存在
    if ! command -v "$compress_cmd" >/dev/null 2>&1; then
        log "ERROR" "压缩命令 $compress_cmd 未安装，跳过压缩"
        return 1
    fi
    
    # 创建压缩文件
    log "INFO" "创建备份压缩文件..."
    
    # 创建压缩文件名
    local archive_file="${BACKUP_ROOT}/${DATE_FORMAT}_backup.tar"
    
    # 创建 tar 归档
    if tar -cf "$archive_file" -C "$BACKUP_ROOT" "${DATE_FORMAT}" >> "$LOG_FILE" 2>&1; then
        log "INFO" "备份归档创建成功: $archive_file"
        
        # 压缩归档
        if "$compress_cmd" "$archive_file" >> "$LOG_FILE" 2>&1; then
            log "INFO" "备份压缩成功: ${archive_file}${ext}"
            
            # 如果压缩成功，删除原始备份目录
            rm -rf "$BACKUP_DIR"
            log "INFO" "已删除原始备份目录: $BACKUP_DIR"
        else
            log "ERROR" "备份压缩失败"
            return 1
        fi
    else
        log "ERROR" "创建备份归档失败"
        return 1
    fi
    
    return 0
}
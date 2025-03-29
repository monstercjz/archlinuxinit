#!/bin/bash

# 依赖: logging.sh (log 函数), utils.sh (check_command)

# 压缩备份
# 功能：将备份目录压缩为单个归档文件
# 参数：无
# 全局变量依赖:
#   COMPRESS_BACKUP, COMPRESS_METHOD, BACKUP_ROOT, DATE_FORMAT, BACKUP_DIR, LOG_FILE
# 返回值：
#   0 - 压缩成功或跳过压缩
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
    if [ "${COMPRESS_BACKUP:-false}" != "true" ]; then
        log "INFO" "跳过备份压缩 (根据配置)"
        return 0
    fi

    log "INFO" "开始压缩备份 (使用 ${COMPRESS_METHOD:-gzip})..."

    local compress_cmd=""
    local ext=""

    case "${COMPRESS_METHOD:-gzip}" in
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
            log "ERROR" "未知的压缩方法: ${COMPRESS_METHOD:-gzip}，跳过压缩"
            return 1
            ;;
    esac

    # 检查压缩命令是否存在
    if ! check_command "$compress_cmd"; then
        log "ERROR" "压缩命令 $compress_cmd 未安装，跳过压缩"
        return 1
    fi

    # 检查 tar 命令是否存在
    if ! check_command "tar"; then
         log "ERROR" "tar 命令未安装，无法创建归档，跳过压缩"
         return 1
    fi

    # 检查原始备份目录是否存在
    if [ ! -d "$BACKUP_DIR" ]; then
        log "ERROR" "原始备份目录 $BACKUP_DIR 不存在，无法压缩"
        return 1
    fi

    # 创建压缩文件名
    # 使用备份根目录和日期格式
    local archive_base="${BACKUP_ROOT}/${DATE_FORMAT}_backup"
    local tar_file="${archive_base}.tar"
    local compressed_file="${tar_file}${ext}"

    log "INFO" "创建备份归档文件: ${tar_file}..."

    # 使用 tar 创建归档
    # -C 选项让 tar 在指定的目录（备份根目录）下操作，避免路径中包含 BACKUP_ROOT
    # 只归档当天的备份目录（DATE_FORMAT）
    # 使用 --remove-files 可以在归档成功后删除源文件，但为了安全，我们分步进行
    if tar -cf "$tar_file" -C "$BACKUP_ROOT" "$DATE_FORMAT" >> "$LOG_FILE" 2>&1; then
        log "INFO" "备份归档创建成功: $tar_file"

        # 压缩归档
        log "INFO" "压缩归档文件: ${compressed_file}..."
        # 使用 exec_with_retry 进行压缩，增加可靠性
        if exec_with_retry "$compress_cmd \"$tar_file\"" "压缩归档文件" 2 5 true; then
            log "INFO" "备份压缩成功: ${compressed_file}"

            # 如果压缩成功，删除原始备份目录
            log "INFO" "删除原始备份目录: $BACKUP_DIR"
            if rm -rf "$BACKUP_DIR"; then
                 log "INFO" "原始备份目录已删除"
                 return 0
            else
                 log "ERROR" "删除原始备份目录失败: $BACKUP_DIR"
                 return 1 # 压缩成功但清理失败
            fi
        else
            log "ERROR" "备份压缩失败"
            # 压缩失败，尝试删除未完成的 tar 文件
            rm -f "$tar_file"
            return 1
        fi
    else
        log "ERROR" "创建备份归档失败: $tar_file"
        return 1
    fi
}

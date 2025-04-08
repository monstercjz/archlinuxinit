# 创建备份摘要
# 功能：创建包含备份信息的摘要文件
# 参数：
#   $1 - 备份总耗时 (秒, duration)
#   $2 - 备份过程中遇到的错误数 (errors)
# 返回值：无
# 错误处理：
#   如果摘要文件创建失败，会记录在日志中，但不会中断脚本执行
# 摘要内容：
#   - 备份时间和主机信息
#   - 备份内容概述
#   - 系统信息（内核版本、Arch版本等）
#   - 备份配置信息
#   - 自定义路径备份状态（如果启用）
# 使用示例：
#   create_backup_summary
create_backup_summary() {
    local duration="${1:-N/A}" # 默认为 N/A
    local errors="${2:-N/A}"   # 默认为 N/A
    log "INFO" "创建备份摘要..."
    
    local summary_file="${BACKUP_DIR}/backup-summary.txt"
    
    cat > "$summary_file" << EOF
# Arch Linux 备份摘要

备份时间: $(date '+%Y-%m-%d %H:%M:%S')
主机名: $(hostname)
用户: $REAL_USER
备份耗时: ${duration} 秒
总体状态: $([ "$errors" -eq 0 ] && echo "成功" || echo "失败 (错误数: $errors)")

## 备份内容

$([ "$BACKUP_SYSTEM_CONFIG" == "true" ] && echo "- 系统配置文件 (/etc)" || echo "- 系统配置文件 (已跳过)")
$([ "$BACKUP_USER_CONFIG" == "true" ] && echo "- 用户配置文件 (~/.*)" || echo "- 用户配置文件 (已跳过)")
$([ "$BACKUP_CUSTOM_PATHS" == "true" ] && echo "- 自定义路径备份" || echo "- 自定义路径备份 (已跳过)")
$([ "$BACKUP_PACKAGES" == "true" ] && echo "- 软件包列表" || echo "- 软件包列表 (已跳过)")
$([ "$BACKUP_LOGS" == "true" ] && echo "- 系统日志" || echo "- 系统日志 (已跳过)")
$([ "$COMPRESS_BACKUP" == "true" ] && echo "- 备份已压缩 (使用 $COMPRESS_METHOD)" || echo "- 备份未压缩")
$([ "$DIFF_BACKUP" == "true" ] && echo "- 差异备份模式" || echo "- 完整备份模式")
$([ "$VERIFY_BACKUP" == "true" ] && echo "- 备份已验证" || echo "- 备份未验证")
$([ "$VERIFY_CHECKSUM" == "true" ] && echo "- 校验和验证已启用" || echo "- 校验和验证已禁用")

## 系统信息

- 内核版本: $(uname -r)
- Arch 版本: $(pacman -Q core/filesystem | cut -d' ' -f2)
- 已安装软件包数量: $(pacman -Q | wc -l)
- 手动安装软件包数量: $(pacman -Qe | wc -l)
- 外部软件包数量: $(pacman -Qm | wc -l)

## 备份配置

- 备份根目录: $BACKUP_ROOT
- 备份保留数量: $BACKUP_RETENTION_COUNT
- 日志保留天数: $LOG_RETENTION_DAYS

## 备份统计 (估算)

- 总大小: $(du -sh "$BACKUP_DIR" 2>/dev/null | cut -f1) ($(du -sb "$BACKUP_DIR" 2>/dev/null | cut -f1) 字节)
- 总文件数: $(find "$BACKUP_DIR" -type f 2>/dev/null | wc -l)

## 验证结果统计 (来自日志)

$(
    # 检查日志文件是否存在且可读
    if [ -z "$LOG_FILE" ] || [ ! -r "$LOG_FILE" ]; then
        echo "- 无法读取日志文件 ($LOG_FILE)，无法统计验证结果。"
    else
        # 统计验证成功/失败次数
        stats_success=$(grep -c '备份验证成功：文件大小和数量差异在可接受范围内' "$LOG_FILE")
        stats_fail=$(grep -c '备份验证失败：文件大小或数量差异超出可接受范围' "$LOG_FILE")
        checksum_success=$(grep -c '校验和验证成功:' "$LOG_FILE")
        checksum_fail=$(grep -c '校验和验证失败，已达到最大重试次数:' "$LOG_FILE")
        checksum_skipped=$(grep -c '根据配置跳过校验和验证:' "$LOG_FILE")

        echo "- 统计验证 (大小/数量): 成功 $stats_success 次, 失败 $stats_fail 次"
        if [[ "$VERIFY_CHECKSUM" == "true" ]]; then
            echo "- 校验和验证: 成功 $checksum_success 次, 失败 $checksum_fail 次"
        else
            echo "- 校验和验证: 跳过 $checksum_skipped 次 (已禁用)"
        fi
    fi
)
EOF
    
    log "INFO" "备份摘要已创建: $summary_file"
    
    # 添加自定义路径备份信息
    if [ "$BACKUP_CUSTOM_PATHS" == "true" ] && [ -n "$CUSTOM_PATHS" ]; then
        echo -e "\n## 已备份的自定义路径\n" >> "$summary_file"
        
        IFS=' ' read -r -a custom_paths <<< "$CUSTOM_PATHS"
        for path in "${custom_paths[@]}"; do
            if [ -e "$path" ]; then
                # 使用更准确的相对路径来检查存在性
                local relative_path="${path#/}"
                local dest_path="$dest_base/$relative_path"
                dest_path=$(echo "$dest_path" | sed 's|//|/|g') # 移除双斜杠

                if [ -e "$dest_path" ]; then
                    echo "- $path (已备份)" >> "$summary_file"
                else
                    # 注意：这里可能因为权限问题或其他原因导致备份失败，仅检查存在性不够准确
                    echo "- $path (备份目标不存在或失败)" >> "$summary_file"
                fi
            else
                echo "- $path (源路径不存在)" >> "$summary_file"
            fi
        done
    fi
}
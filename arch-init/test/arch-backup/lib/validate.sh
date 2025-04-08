#!/bin/bash

# 依赖: logging.sh (log 函数), utils.sh (exec_with_retry, check_file_integrity)

# 验证备份
# 功能：验证备份的完整性和一致性
# 参数：无
# 全局变量依赖:
#   VERIFY_BACKUP, COMPRESS_BACKUP, COMPRESS_METHOD, BACKUP_ROOT, DATE_FORMAT,
#   BACKUP_DIR, BACKUP_DIRS, LOG_FILE, TIMESTAMP
# 返回值：
#   0 - 验证成功或跳过验证
#   非0 - 验证失败
# 错误处理：
#   如果验证过程中发现错误，会记录并返回非零状态码
#   对于不同类型的错误提供详细的错误信息
# 验证内容：
#   - 对于压缩备份：检查压缩文件是否存在、大小是否合理、内容是否完整、校验和是否匹配
#   - 对于未压缩备份：检查备份目录结构、关键目录是否存在、关键文件是否存在、文件权限是否正确
# 特性：
#   - 根据备份类型（压缩或未压缩）选择不同的验证方法
#   - 使用重试机制验证压缩文件
#   - 对于未压缩备份，进行抽样文件内容验证
#   - 生成校验和文件用于后续验证
#   - 提供详细的验证报告
# 使用示例：
#   verify_backup || log "ERROR" "备份验证失败"
verify_backup() {
    if [ "${VERIFY_BACKUP:-false}" != "true" ]; then
        log "INFO" "跳过备份验证 (根据配置)"
        return 0
    fi

    log "INFO" "开始验证备份..."
    local start_time=$(date +%s)
    local verify_errors=0
    local verify_warnings=0
    local max_errors=5 # 允许的最大错误数，超过则认为验证失败

    # 确定校验和工具
    local checksum_tool=""
    local checksum_ext=""
    if command -v sha256sum &>/dev/null; then
        checksum_tool="sha256sum"
        checksum_ext="sha256"
    elif command -v md5sum &>/dev/null; then
        checksum_tool="md5sum"
        checksum_ext="md5"
    elif command -v cksum &>/dev/null; then
        checksum_tool="cksum"
        checksum_ext="cksum"
    fi

    if [ -z "$checksum_tool" ]; then
        log "WARN" "未找到校验和工具 (sha256sum, md5sum, cksum)，将使用基本文件属性进行验证"
        verify_warnings=$((verify_warnings + 1))
    else
        log "INFO" "使用 $checksum_tool 进行文件完整性验证"
    fi

    # --- 验证压缩备份 ---
    if [ "${COMPRESS_BACKUP:-false}" == "true" ]; then
        local archive_base="${BACKUP_ROOT}/${DATE_FORMAT}_backup"
        local tar_file="${archive_base}.tar" # 基础 tar 文件名
        local ext=""
        case "${COMPRESS_METHOD:-gzip}" in
            "gzip") ext=".gz" ;;
            "bzip2") ext=".bz2" ;;
            "xz") ext=".xz" ;;
            *) log "ERROR" "未知的压缩方法，无法验证"; return 1 ;;
        esac
        local full_archive_path="${tar_file}${ext}"
        local checksum_file="${archive_base}.${checksum_ext}" # 校验和文件名与归档名对应

        log "INFO" "验证压缩备份文件: $full_archive_path"

        # 1. 检查压缩文件是否存在
        if ! check_file_integrity "$full_archive_path" "压缩备份文件"; then
            return 1 # 文件不存在是致命错误
        fi

        # 2. 检查文件大小是否合理（至少 1KB，避免完全空文件）
        local file_size=$(stat -c%s "$full_archive_path" 2>/dev/null || echo "0")
        local min_size=1024 # 1KB
        if [ "$file_size" -lt "$min_size" ]; then
            log "WARN" "验证警告: 压缩文件大小可能过小: $file_size 字节"
            verify_warnings=$((verify_warnings + 1))
        fi

        # 3. 计算并存储/验证校验和
        if [ -n "$checksum_tool" ]; then
            # 如果校验和文件已存在，则验证；否则，创建
            if [ -f "$checksum_file" ]; then
                 log "INFO" "验证现有校验和文件: $checksum_file"
                 # 使用校验和工具的 -c 选项进行检查
                 if $checksum_tool -c "$checksum_file" --status >> "$LOG_FILE" 2>&1; then
                     log "INFO" "校验和验证成功"
                 else
                     log "ERROR" "校验和验证失败: $full_archive_path"
                     verify_errors=$((verify_errors + 1))
                 fi
            else
                log "INFO" "计算并保存备份文件校验和..."
                # 计算校验和并保存到文件，确保相对路径
                if (cd "$BACKUP_ROOT" && $checksum_tool "$(basename "$full_archive_path")" > "$(basename "$checksum_file")"); then
                    log "INFO" "校验和已保存到: $checksum_file"
                    check_file_integrity "$checksum_file" "校验和文件" || verify_warnings=$((verify_warnings + 1))
                else
                    log "WARN" "无法计算或保存校验和: $full_archive_path"
                    verify_warnings=$((verify_warnings + 1))
                fi
            fi
        fi

        # 4. 使用压缩工具的测试功能验证归档完整性
        local verify_cmd=""
        case "${COMPRESS_METHOD:-gzip}" in
            "gzip") verify_cmd="gzip -t \"${full_archive_path}\"" ;;
            "bzip2") verify_cmd="bzip2 -t \"${full_archive_path}\"" ;;
            "xz") verify_cmd="xz -t \"${full_archive_path}\"" ;;
        esac
        verify_cmd+=" >> \"$LOG_FILE\" 2>&1"

        if exec_with_retry "$verify_cmd" "压缩文件完整性测试" 3 5 true; then
            log "INFO" "压缩文件完整性测试成功"

            # 5. 尝试列出归档内容以进一步验证 (可选但推荐)
            local list_cmd=""
            case "${COMPRESS_METHOD:-gzip}" in
                "gzip") list_cmd="tar -tzf \"${full_archive_path}\"";;
                "bzip2") list_cmd="tar -tjf \"${full_archive_path}\"" ;;
                "xz") list_cmd="tar -tJf \"${full_archive_path}\"" ;;
            esac
            # 只列出少量内容并丢弃输出，只检查命令是否成功
            list_cmd+=" | head -n 5 > /dev/null 2>> \"$LOG_FILE\""

            if exec_with_retry "$list_cmd" "归档内容列表测试" 2 3 true; then
                log "INFO" "归档内容列表测试成功"
            else
                log "ERROR" "归档内容列表测试失败，归档可能已损坏"
                verify_errors=$((verify_errors + 1))
            fi
        else
            log "ERROR" "压缩文件完整性测试失败，即使在多次尝试后"
            verify_errors=$((verify_errors + 1))
        fi

    # --- 验证未压缩备份 ---
    else
        log "INFO" "验证未压缩备份目录: $BACKUP_DIR"
        local checksum_file="${BACKUP_DIR}/checksums.${checksum_ext}" # 校验和文件在备份目录内

        # 1. 检查备份目录是否存在
        if ! check_file_integrity "$BACKUP_DIR" "备份目录"; then
            return 1 # 目录不存在是致命错误
        fi

        # 2. 检查关键子目录是否存在并验证内容
        read -ra backup_dirs_array <<< "${BACKUP_DIRS:-}"
        for dir in "${backup_dirs_array[@]}"; do
            local current_dir="${BACKUP_DIR}/${dir}"
            if [ ! -d "$current_dir" ]; then
                 # 检查是否该模块被禁用了
                 local config_var="BACKUP_${dir^^}" # e.g., BACKUP_ETC
                 if [[ "${!config_var:-true}" == "true" ]]; then
                     log "ERROR" "验证失败: ${dir} 目录不存在，但备份已启用"
                     verify_errors=$((verify_errors + 1))
                 else
                     log "INFO" "${dir} 目录不存在，但备份已禁用，跳过验证"
                 fi
                 continue
            fi

            # 检查目录是否为空（如果备份已启用）
            if [[ "${!config_var:-true}" == "true" ]] && [ -z "$(ls -A "$current_dir" 2>/dev/null)" ]; then
                log "WARN" "验证警告: ${dir} 目录为空"
                verify_warnings=$((verify_warnings + 1))
            fi

            # 使用 find 检查空文件和不可读文件
            local empty_files=$(find "$current_dir" -type f -size 0 -print -quit 2>/dev/null) # 找到一个就退出
            if [ -n "$empty_files" ]; then
                log "WARN" "在 ${dir} 目录中发现空文件 (例如: $empty_files)"
                verify_warnings=$((verify_warnings + 1))
            fi
            local unreadable_files=$(find "$current_dir" -type f ! -readable -print -quit 2>/dev/null) # 找到一个就退出
            if [ -n "$unreadable_files" ]; then
                log "WARN" "在 ${dir} 目录中发现不可读文件 (例如: $unreadable_files)"
                verify_warnings=$((verify_warnings + 1))
            fi

            # 如果错误太多，提前退出
            if [ $verify_errors -ge $max_errors ]; then
                log "ERROR" "验证失败: 发现太多错误 ($verify_errors)"
                return 1
            fi
        done

        # 3. 检查备份摘要文件
        if ! check_file_integrity "${BACKUP_DIR}/backup-summary.txt" "备份摘要文件"; then
            verify_errors=$((verify_errors + 1))
        else
            # 检查摘要文件是否包含必要信息
            if ! grep -q "备份时间" "${BACKUP_DIR}/backup-summary.txt" || \
               ! grep -q "备份内容" "${BACKUP_DIR}/backup-summary.txt"; then
                log "WARN" "验证警告: 备份摘要文件可能不完整"
                verify_warnings=$((verify_warnings + 1))
            fi
        fi

        # 4. 生成/验证校验和文件
        if [ -n "$checksum_tool" ]; then
            if [ -f "$checksum_file" ]; then
                log "INFO" "验证现有校验和文件: $checksum_file"
                # 使用校验和工具的 -c 选项进行检查
                # --quiet or --status suppresses normal output
                if (cd "$BACKUP_DIR" && $checksum_tool -c "$(basename "$checksum_file")" --status) >> "$LOG_FILE" 2>&1; then
                     log "INFO" "校验和验证成功"
                else
                     log "ERROR" "校验和验证失败"
                     verify_errors=$((verify_errors + 1))
                fi
            else
                log "INFO" "生成备份目录校验和文件..."
                # 只对部分文件类型和大小计算校验和，避免处理大型或二进制文件
                # 使用 find 和 xargs，在 BACKUP_DIR 内执行 checksum_tool 以获取相对路径
                if (cd "$BACKUP_DIR" && find . -type f \( -name "*.txt" -o -name "*.conf" -o -name "*.sh" -o -name "*.json" -o -name "*.xml" -o -name "*.ini" \) -size -5M -print0 | xargs -0 -r $checksum_tool > "$(basename "$checksum_file")"); then
                    if [ -s "$checksum_file" ]; then
                        log "INFO" "校验和文件已生成: $checksum_file"
                    else
                        log "WARN" "校验和文件生成成功但为空 (可能没有匹配的文件)"
                        # rm -f "$checksum_file" # 删除空文件
                        verify_warnings=$((verify_warnings + 1))
                    fi
                else
                    log "WARN" "校验和文件生成失败"
                    verify_warnings=$((verify_warnings + 1))
                fi
            fi
        fi
    fi # End of uncompressed backup verification

    # --- 生成验证报告 ---
    local report_file="${BACKUP_ROOT}/verification-report_${DATE_FORMAT}.txt"
    # 如果是压缩备份，报告放在根目录；如果未压缩，放在备份目录内
    if [ "${COMPRESS_BACKUP:-false}" != "true" ]; then
        report_file="${BACKUP_DIR}/verification-report.txt"
    fi

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    local final_status=$([ $verify_errors -eq 0 ] && echo "通过" || echo "失败")
    local backup_target=$([ "${COMPRESS_BACKUP:-false}" == "true" ] && echo "$full_archive_path" || echo "$BACKUP_DIR")
    local total_size=$([ -e "$backup_target" ] && du -sh "$backup_target" | cut -f1 || echo "N/A")
    local file_count=$([ "${COMPRESS_BACKUP:-false}" != "true" ] && find "$BACKUP_DIR" -type f 2>/dev/null | wc -l || echo "N/A (压缩)")
    local dir_count=$([ "${COMPRESS_BACKUP:-false}" != "true" ] && find "$BACKUP_DIR" -type d 2>/dev/null | wc -l || echo "N/A (压缩)")

    # 创建报告文件
    cat > "$report_file" << EOF
# 备份验证报告

验证时间: $(date '+%Y-%m-%d %H:%M:%S')
备份目标: $backup_target
备份类型: $([ "${COMPRESS_BACKUP:-false}" == "true" ] && echo "压缩 (${COMPRESS_METHOD:-gzip})" || echo "未压缩")

## 验证结果

- 错误数量: $verify_errors
- 警告数量: $verify_warnings
- 验证状态: $final_status
- 验证耗时: ${duration} 秒

## 备份统计 (近似值)

- 总大小: $total_size
- 总文件数: $file_count
- 总目录数: $dir_count

## 校验和信息

$([ -n "$checksum_tool" ] && echo "校验和文件: $checksum_file\n校验和算法: ${checksum_tool}" || echo "未使用校验和验证")

## 注意事项

$([ $verify_warnings -gt 0 ] && echo "- 发现 $verify_warnings 个警告，建议查看日志 $LOG_FILE 获取详细信息。" || echo "- 未发现警告。")
$([ $verify_errors -gt 0 ] && echo "- 发现 $verify_errors 个错误，备份可能不完整或已损坏！" || echo "- 未发现错误，备份验证通过。")

EOF

    log "INFO" "验证报告已生成: $report_file"

    # --- 返回最终状态 ---
    if [ $verify_errors -gt 0 ]; then
        log "ERROR" "备份验证失败，发现 $verify_errors 个错误 (耗时: ${duration}秒)"
        return 1
    else
        if [ $verify_warnings -gt 0 ]; then
            log "INFO" "备份验证成功，但有 $verify_warnings 个警告 (耗时: ${duration}秒)"
        else
            log "INFO" "备份验证成功，未发现问题 (耗时: ${duration}秒)"
        fi
        return 0
    fi
}

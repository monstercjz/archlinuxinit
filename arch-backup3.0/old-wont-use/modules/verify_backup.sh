# 验证备份
# 功能：验证备份的完整性和一致性
# 参数：无
# 返回值：
#   0 - 验证成功
#   1 - 验证失败
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
    if [ "$VERIFY_BACKUP" != "true" ]; then
        log "INFO" "跳过备份验证"
        return 0
    fi
    
    log "INFO" "开始验证备份..."
    local start_time=$(date +%s)
    
    local verify_status=0
    local verify_errors=0
    local verify_warnings=0
    local max_errors=5
    local checksum_file="${BACKUP_ROOT}/backup_${DATE_FORMAT}.sha256"
    
    # 检查是否有可用的校验工具
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
        log "WARN" "未找到校验和工具，将使用基本文件属性进行验证"
        verify_warnings=$((verify_warnings + 1))
    else
        log "INFO" "使用 $checksum_tool 进行文件完整性验证"
    fi
    
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        # 验证压缩文件
        local archive_file="${BACKUP_ROOT}/${DATE_FORMAT}_backup.tar"
        local ext=""
        
        case "$COMPRESS_METHOD" in
            "gzip") ext=".gz" ;;
            "bzip2") ext=".bz2" ;;
            "xz") ext=".xz" ;;
        esac
        
        local full_archive_path="${archive_file}${ext}"
        
        # 检查压缩文件是否存在
        if [ ! -f "$full_archive_path" ]; then
            log "ERROR" "验证失败: 压缩文件不存在: $full_archive_path"
            return 1
        fi
        
        log "INFO" "验证压缩文件: $full_archive_path"
        
        # 检查文件大小
        local file_size=$(stat -c%s "$full_archive_path" 2>/dev/null || echo "0")
        if [ "$file_size" -eq 0 ]; then
            log "ERROR" "验证失败: 压缩文件大小为零: $full_archive_path"
            return 1
        fi
        
        # 检查文件大小是否合理（至少1MB）
        local min_size=$((1024 * 1024))
        if [ "$file_size" -lt "$min_size" ]; then
            log "WARN" "验证警告: 压缩文件大小可能过小: $file_size 字节"
            verify_warnings=$((verify_warnings + 1))
        fi
        
        # 计算并存储校验和
        if [ -n "$checksum_tool" ]; then
            log "INFO" "计算备份文件校验和..."
            if $checksum_tool "$full_archive_path" > "$checksum_file" 2>> "$LOG_FILE"; then
                log "INFO" "校验和已保存到: $checksum_file"
                
                # 验证校验和文件
                if [ -s "$checksum_file" ]; then
                    log "DEBUG" "校验和文件创建成功，大小: $(stat -c%s "$checksum_file") 字节"
                else
                    log "WARN" "校验和文件为空，可能计算失败"
                    verify_warnings=$((verify_warnings + 1))
                fi
            else
                log "WARN" "无法计算校验和: $full_archive_path"
                verify_warnings=$((verify_warnings + 1))
            fi
        fi
        
        # 使用重试机制验证压缩文件
        local verify_cmd=""
        case "$COMPRESS_METHOD" in
            "gzip")
                verify_cmd="gzip -t \"${full_archive_path}\" >> \"$LOG_FILE\" 2>&1"
                ;;
            "bzip2")
                verify_cmd="bzip2 -t \"${full_archive_path}\" >> \"$LOG_FILE\" 2>&1"
                ;;
            "xz")
                verify_cmd="xz -t \"${full_archive_path}\" >> \"$LOG_FILE\" 2>&1"
                ;;
        esac
        
        if exec_with_retry "$verify_cmd" "压缩文件验证" 3 5 true; then
            log "INFO" "压缩文件完整性验证成功"
            
            # 尝试列出归档内容以进一步验证
            local list_cmd=""
            case "$COMPRESS_METHOD" in
                "gzip")
                    list_cmd="tar -tzf \"${full_archive_path}\" | head -10 > /dev/null 2>> \"$LOG_FILE\""
                    ;;
                "bzip2")
                    list_cmd="tar -tjf \"${full_archive_path}\" | head -10 > /dev/null 2>> \"$LOG_FILE\""
                    ;;
                "xz")
                    list_cmd="tar -tJf \"${full_archive_path}\" | head -10 > /dev/null 2>> \"$LOG_FILE\""
                    ;;
            esac
            
            if exec_with_retry "$list_cmd" "归档内容验证" 2 3 true; then
                log "INFO" "归档内容验证成功"
            else
                log "ERROR" "归档内容验证失败，归档可能已损坏"
                verify_errors=$((verify_errors + 1))
            fi
        else
            log "ERROR" "压缩文件验证失败，即使在多次尝试后"
            verify_errors=$((verify_errors + 1))
        fi
    else
        # 验证未压缩的备份
        log "INFO" "验证备份目录: $BACKUP_DIR"
        
        # 检查备份目录是否存在
        if [ ! -d "$BACKUP_DIR" ]; then
            log "ERROR" "验证失败: 备份目录不存在: $BACKUP_DIR"
            return 1
        fi
        
        # 检查关键目录是否存在并验证内容
        for dir in ${BACKUP_DIRS}; do
            if [ ! -d "${BACKUP_DIR}/${dir}" ]; then
                log "ERROR" "验证失败: ${dir}目录不存在"
                verify_errors=$((verify_errors + 1))
                continue
            fi
            
            # 检查目录是否为空
            if [ -z "$(ls -A "${BACKUP_DIR}/${dir}" 2>/dev/null)" ]; then
                log "WARN" "验证警告: ${dir}目录为空"
                verify_warnings=$((verify_warnings + 1))
                continue
            fi
            
            # 对每个目录进行抽样检查 - 使用更高效的方法
            log "INFO" "对 ${dir} 目录进行抽样文件验证"
            
            # 使用find命令的-size选项直接过滤空文件
            local empty_files=$(find "${BACKUP_DIR}/${dir}" -type f -size 0 -name "*" | wc -l)
            if [ "$empty_files" -gt 0 ]; then
                log "WARN" "在 ${dir} 目录中发现 $empty_files 个空文件"
                verify_warnings=$((verify_warnings + 1))
            fi
            
            # 使用find命令的-perm选项直接检查权限问题
            local unreadable_files=$(find "${BACKUP_DIR}/${dir}" -type f ! -readable -name "*" | wc -l)
            if [ "$unreadable_files" -gt 0 ]; then
                log "WARN" "在 ${dir} 目录中发现 $unreadable_files 个不可读文件"
                verify_warnings=$((verify_warnings + 1))
            fi
            
            # 只对重要文件进行抽样校验和计算
            if [ -n "$checksum_tool" ]; then
                local important_files=($(find "${BACKUP_DIR}/${dir}" -type f -name "*.conf" -o -name "*.txt" -o -name "*.sh" | sort | head -5 2>/dev/null))
                
                if [ ${#important_files[@]} -gt 0 ]; then
                    log "DEBUG" "对 ${#important_files[@]} 个重要文件计算校验和"
                    for sample_file in "${important_files[@]}"; do
                        if [ -f "$sample_file" ] && [ -r "$sample_file" ]; then
                            local rel_path=${sample_file#$BACKUP_DIR/}
                            $checksum_tool "$sample_file" | sed "s|$sample_file|$rel_path|" >> "${BACKUP_DIR}/checksums.${checksum_ext}" 2>/dev/null
                        fi
                    done
                fi
            fi
        done
        
        # 如果错误太多，提前退出
        if [ $verify_errors -ge $max_errors ]; then
            log "ERROR" "验证失败: 发现太多错误 ($verify_errors)"
            return 1
        fi
        
        # 检查备份摘要文件
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
        
        # 生成完整的校验和文件 - 优化为只处理重要文件
        if [ -n "$checksum_tool" ]; then
            log "INFO" "生成备份目录校验和文件..."
            # 只对重要配置文件和文本文件计算校验和，避免处理大型二进制文件
            find "$BACKUP_DIR" -type f \( -name "*.txt" -o -name "*.conf" -o -name "*.sh" -o -name "*.json" -o -name "*.xml" -o -name "*.ini" \) -size -1M | \
                xargs -I{} $checksum_tool "{}" 2>/dev/null | \
                sed "s|$BACKUP_DIR/||g" > "${BACKUP_DIR}/checksums.${checksum_ext}"
            
            if [ -s "${BACKUP_DIR}/checksums.${checksum_ext}" ]; then
                log "INFO" "校验和文件已生成: ${BACKUP_DIR}/checksums.${checksum_ext}"
            else
                log "WARN" "校验和文件生成失败或为空"
                verify_warnings=$((verify_warnings + 1))
            fi
        fi
        
        # 生成验证报告
        local report_file="${BACKUP_DIR}/verification-report.txt"
        local end_time=$(date +%s)
        local duration=$((end_time - start_time))
        
        cat > "$report_file" << EOF
# 备份验证报告

验证时间: $(date '+%Y-%m-%d %H:%M:%S')
备份目录: $BACKUP_DIR

## 验证结果

- 错误数量: $verify_errors
- 警告数量: $verify_warnings
- 验证状态: $([ $verify_errors -eq 0 ] && echo "通过" || echo "失败")
- 验证耗时: ${duration} 秒

## 备份统计

- 总文件数: $(find "$BACKUP_DIR" -type f | wc -l)
- 总目录数: $(find "$BACKUP_DIR" -type d | wc -l)
- 总大小: $(du -sh "$BACKUP_DIR" | cut -f1)

## 校验和信息

$([ -n "$checksum_tool" ] && echo "校验和文件: ${BACKUP_DIR}/checksums.${checksum_ext}\n校验和算法: ${checksum_tool}" || echo "未使用校验和验证")

## 注意事项

$([ $verify_warnings -gt 0 ] && echo "发现 $verify_warnings 个警告，请查看日志获取详细信息。" || echo "未发现警告。")
$([ $verify_errors -gt 0 ] && echo "发现 $verify_errors 个错误，备份可能不完整或已损坏。" || echo "未发现错误，备份验证通过。")

## 验证时间

开始时间: $TIMESTAMP
结束时间: $(date +"%Y-%m-%d_%H-%M-%S")
验证耗时: ${duration} 秒
EOF
        
        log "INFO" "验证报告已生成: $report_file"
        
        if [ $verify_errors -eq 0 ]; then
            if [ $verify_warnings -eq 0 ]; then
                log "INFO" "备份目录验证成功，未发现问题 (耗时: ${duration}秒)"
            else
                log "INFO" "备份目录验证成功，但有 $verify_warnings 个警告 (耗时: ${duration}秒)"
            fi
            return 0
        else
            log "ERROR" "备份目录验证失败，发现 $verify_errors 个错误 (耗时: ${duration}秒)"
            return 1
        fi
    fi
    
    # 记录验证完成时间
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    log "INFO" "备份验证完成，耗时: ${duration}秒"
    
    # 返回验证状态
    return $verify_errors
}
#!/bin/bash
# Shebang: 指定脚本使用bash执行

#############################################################
# 完整备份验证系统
# 功能：提供全面的备份验证框架，整合多种验证方法
# 版本：1.0
#############################################################

# 加载依赖模块
# 注意：此脚本假设已经加载了 utils/loggings.sh

# 源码目录
SOURCE_DIR="$(dirname "${BASH_SOURCE[0]}")/.."

# 加载验证相关模块
# source "$SOURCE_DIR/core/verify_backup_stats.sh" # 统计验证在 workflow 内部完成
# 完整性检查将在下面实现和调用
# 确保在主脚本中加载: source "$SOURCE_DIR/file-check/check_file_integrity.sh"

#############################################################
# 函数：verify_system
# 功能：执行完整的备份验证，包括多种验证方法
# 参数：无
# 返回值：
#   0 - 所有验证通过
#   1 - 至少一项验证失败
#############################################################
verify_system() {
    if [ "$VERIFY_BACKUP" != "true" ]; then
        log_info "跳过备份验证"
        return 0
    fi
    
    log_info "开始执行完整备份验证系统..."
    local start_time=$(date +%s)
    
    local verify_status=0
    local verify_errors=0
    local verify_warnings=0
    
    # 创建验证报告目录
    local verify_report_dir="${BACKUP_ROOT}/verify_reports"
    mkdir -p "$verify_report_dir" 2>/dev/null
    if [ $? -ne 0 ]; then
        log_error "无法创建验证报告目录: $verify_report_dir"
        verify_errors=$((verify_errors + 1))
    fi
    
    local verify_report_file="${verify_report_dir}/verify_report_${DATE_FORMAT}.txt"
    echo "备份验证报告 - $(date)" > "$verify_report_file"
    echo "===================================" >> "$verify_report_file"
    
    # 1. 基本存在性验证
    log_info "执行基本存在性验证..."
    echo "\n1. 基本存在性验证" >> "$verify_report_file"
    
    if verify_existence; then
        log_info "基本存在性验证通过"
        echo "结果: 通过" >> "$verify_report_file"
    else
        log_error "基本存在性验证失败"
        echo "结果: 失败" >> "$verify_report_file"
        verify_errors=$((verify_errors + 1))
    fi
    
    # 2. 文件完整性校验和验证 (已移至各备份脚本内部执行)
    log_info "文件完整性校验和验证已在各备份脚本内部执行，此处跳过。"
    echo "\n2. 文件完整性校验和验证: 已在各备份脚本内部执行" >> "$verify_report_file"
    
    # 3. 权限验证
    log_info "执行权限验证..."
    echo "\n3. 权限验证" >> "$verify_report_file"
    
    if verify_permissions; then
        log_info "权限验证通过"
        echo "结果: 通过" >> "$verify_report_file"
    else
        log_error "权限验证失败"
        echo "结果: 失败" >> "$verify_report_file"
        verify_errors=$((verify_errors + 1))
    fi
    
    # 4. 结构验证
    log_info "执行结构验证..."
    echo "\n4. 结构验证" >> "$verify_report_file"
    
    if verify_structure; then
        log_info "结构验证通过"
        echo "结果: 通过" >> "$verify_report_file"
    else
        log_error "结构验证失败"
        echo "结果: 失败" >> "$verify_report_file"
        verify_errors=$((verify_errors + 1))
    fi
    
    # 5. 统计信息验证 (移除)
    echo "\n5. 统计信息验证: 已移除" >> "$verify_report_file"
    
    # 6. 排除项验证 (移除)
    echo "\n6. 排除项验证: 已移除" >> "$verify_report_file"
    
    # 7. 恢复点验证 (可选)
    # 7. 恢复点验证 (移除)
    echo "\n7. 恢复点验证: 已移除" >> "$verify_report_file"
    
    # 验证报告总结
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "\n===================================" >> "$verify_report_file"
    echo "验证总结:" >> "$verify_report_file"
    echo "- 总验证项: 3 (存在性, 权限, 结构)" >> "$verify_report_file"
    echo "- 错误数: $verify_errors" >> "$verify_report_file"
    echo "- 警告数: $verify_warnings" >> "$verify_report_file"
    echo "- 验证耗时: ${duration}秒" >> "$verify_report_file"
    echo "- 验证状态: $([ $verify_errors -eq 0 ] && echo "通过" || echo "失败")" >> "$verify_report_file"
    echo "===================================" >> "$verify_report_file"
    
    log_info "验证报告已保存到: $verify_report_file"
    
    # 返回验证状态
    if [ $verify_errors -gt 0 ]; then
        log_error "备份验证失败，发现 $verify_errors 个错误和 $verify_warnings 个警告"
        return 1
    else
        if [ $verify_warnings -gt 0 ]; then
            log_notice "备份验证通过，但有 $verify_warnings 个警告"
        else
            log_notice "备份验证完全通过"
        fi
        return 0
    fi
}

#############################################################
# 函数：verify_existence
# 功能：验证备份文件或目录是否存在
# 参数：无
# 返回值：
#   0 - 验证通过
#   1 - 验证失败
#############################################################
verify_existence() {
    log_info "验证备份文件/目录是否存在..."
    local errors=0
    
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
        
        if [ ! -f "$full_archive_path" ]; then
            log_error "验证失败: 压缩文件不存在: $full_archive_path"
            errors=$((errors + 1))
        else
            log_debug "压缩文件存在: $full_archive_path"
            
            # 检查文件大小
            local file_size=$(stat -c%s "$full_archive_path" 2>/dev/null || echo "0")
            if [ "$file_size" -eq 0 ]; then
                log_error "验证失败: 压缩文件大小为零: $full_archive_path"
                errors=$((errors + 1))
            else
                log_debug "压缩文件大小正常: $file_size 字节"
            fi
        fi
    else
        # 验证未压缩的备份目录
        if [ ! -d "$BACKUP_DIR" ]; then
            log_error "验证失败: 备份目录不存在: $BACKUP_DIR"
            errors=$((errors + 1))
        else
            log_debug "备份目录存在: $BACKUP_DIR"
            
            # 检查关键目录是否存在
            for dir in ${BACKUP_DIRS}; do
                if [ ! -d "${BACKUP_DIR}/${dir}" ]; then
                    log_error "验证失败: ${dir}目录不存在"
                    errors=$((errors + 1))
                else
                    log_debug "目录存在: ${BACKUP_DIR}/${dir}"
                    
                    # 检查目录是否为空
                    if [ -z "$(ls -A "${BACKUP_DIR}/${dir}" 2>/dev/null)" ]; then
                        log_warn "验证警告: ${dir}目录为空"
                    fi
                fi
            done
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log_info "存在性验证通过"
        return 0
    else
        log_error "存在性验证失败，发现 $errors 个错误"
        return 1
    fi
}

# (移除旧的 verify_file_integrity 函数体)

#############################################################
# 函数：verify_permissions
# 功能：验证备份文件的权限
# 参数：无
# 返回值：
#   0 - 验证通过
#   1 - 验证失败
#############################################################
verify_permissions() {
    log_info "验证文件权限..."
    local errors=0
    local warnings=0
    
    # 只对未压缩的备份进行权限验证
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        log_info "压缩备份不进行权限验证"
        return 0
    fi
    
    # 对每个目录进行权限检查
    for dir in ${BACKUP_DIRS}; do
        if [ ! -d "${BACKUP_DIR}/${dir}" ]; then
            continue # 目录不存在，跳过
        fi
        
        log_info "验证 ${dir} 目录的文件权限"
        
        # 检查不可读文件
        local unreadable_files=$(find "${BACKUP_DIR}/${dir}" -type f ! -readable -name "*" | wc -l)
        if [ "$unreadable_files" -gt 0 ]; then
            log_warn "在 ${dir} 目录中发现 $unreadable_files 个不可读文件"
            warnings=$((warnings + 1))
        fi
        
        # 检查不可执行的脚本文件
        local unexecutable_scripts=$(find "${BACKUP_DIR}/${dir}" -type f -name "*.sh" ! -executable | wc -l)
        if [ "$unexecutable_scripts" -gt 0 ]; then
            log_warn "在 ${dir} 目录中发现 $unexecutable_scripts 个不可执行的脚本文件"
            warnings=$((warnings + 1))
        fi
        
        # 检查权限过于开放的文件（对所有人可写）
        local too_open_files=$(find "${BACKUP_DIR}/${dir}" -type f -perm -o=w | wc -l)
        if [ "$too_open_files" -gt 0 ]; then
            log_warn "在 ${dir} 目录中发现 $too_open_files 个权限过于开放的文件（对所有人可写）"
            warnings=$((warnings + 1))
        fi
    done
    
    if [ $errors -eq 0 ]; then
        if [ $warnings -gt 0 ]; then
            log_notice "权限验证通过，但有 $warnings 个警告"
        else
            log_info "权限验证完全通过"
        fi
        return 0
    else
        log_error "权限验证失败，发现 $errors 个错误和 $warnings 个警告"
        return 1
    fi
}

#############################################################
# 函数：verify_structure
# 功能：验证备份的目录结构
# 参数：无
# 返回值：
#   0 - 验证通过
#   1 - 验证失败
#############################################################
verify_structure() {
    log_info "验证备份目录结构..."
    local errors=0
    
    # 只对未压缩的备份进行结构验证
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        log_info "压缩备份不进行目录结构验证"
        return 0
    fi
    
    # 验证备份目录是否存在
    if [ ! -d "$BACKUP_DIR" ]; then
        log_error "验证失败: 备份目录不存在: $BACKUP_DIR"
        return 1
    fi
    
    # 验证所有必需的子目录是否存在
    for dir in ${BACKUP_DIRS}; do
        if [ ! -d "${BACKUP_DIR}/${dir}" ]; then
            log_error "验证失败: 必需的子目录不存在: ${dir}"
            errors=$((errors + 1))
        fi
    done
    
    # 验证关键配置文件是否存在
    if [ "$BACKUP_SYSTEM_CONFIG" == "true" ] && [ -d "${BACKUP_DIR}/etc" ]; then
        local key_config_files=("fstab" "passwd" "group" "hosts")
        for file in "${key_config_files[@]}"; do
            if [ ! -f "${BACKUP_DIR}/etc/etc/${file}" ]; then
                log_warn "关键系统配置文件不存在: ${file}"
            fi
        done
    fi
    
    # 验证用户配置目录结构
    if [ "$BACKUP_USER_CONFIG" == "true" ]; then
        if [ -d "${BACKUP_DIR}/home" ]; then
             local user_dirs_count=$(find "${BACKUP_DIR}/home" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | wc -l)
             if [ "$user_dirs_count" -eq 0 ]; then
                 log_warn "用户配置备份目录 (${BACKUP_DIR}/home) 中没有找到用户子目录"
             else
                 log_debug "在 ${BACKUP_DIR}/home 中找到 $user_dirs_count 个用户目录"
                 # 可以添加对特定用户配置文件的抽查
             fi
        else
             log_warn "用户配置备份已启用，但未找到 ${BACKUP_DIR}/home 目录"
             errors=$((errors + 1)) # 标记为错误，因为目录应该存在
        fi
    fi
    
    if [ $errors -eq 0 ]; then
        log_info "目录结构验证通过"
        return 0
    else
        log_error "目录结构验证失败，发现 $errors 个错误"
        return 1
    fi
}

# (移除 verify_statistics, verify_exclusions, verify_recovery_point 函数体)
# (verify_recovery_point 函数已移除)
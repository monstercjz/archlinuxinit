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
source "$SOURCE_DIR/modules/verify_backup_stats.sh"
source "$SOURCE_DIR/modules/check_file_integrity.sh"

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
    
    # 2. 文件完整性验证
    log_info "执行文件完整性验证..."
    echo "\n2. 文件完整性验证" >> "$verify_report_file"
    
    if verify_file_integrity; then
        log_info "文件完整性验证通过"
        echo "结果: 通过" >> "$verify_report_file"
    else
        log_error "文件完整性验证失败"
        echo "结果: 失败" >> "$verify_report_file"
        verify_errors=$((verify_errors + 1))
    fi
    
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
    
    # 5. 统计信息验证
    log_info "执行统计信息验证..."
    echo "\n5. 统计信息验证" >> "$verify_report_file"
    
    if verify_statistics; then
        log_info "统计信息验证通过"
        echo "结果: 通过" >> "$verify_report_file"
    else
        log_error "统计信息验证失败"
        echo "结果: 失败" >> "$verify_report_file"
        verify_errors=$((verify_errors + 1))
    fi
    
    # 6. 排除项验证
    log_info "执行排除项验证..."
    echo "\n6. 排除项验证" >> "$verify_report_file"
    
    if verify_exclusions; then
        log_info "排除项验证通过"
        echo "结果: 通过" >> "$verify_report_file"
    else
        log_error "排除项验证失败"
        echo "结果: 失败" >> "$verify_report_file"
        verify_errors=$((verify_errors + 1))
    fi
    
    # 7. 恢复点验证 (可选)
    if [ "$VERIFY_RECOVERY_POINT" == "true" ]; then
        log_info "执行恢复点验证..."
        echo "\n7. 恢复点验证" >> "$verify_report_file"
        
        if verify_recovery_point; then
            log_info "恢复点验证通过"
            echo "结果: 通过" >> "$verify_report_file"
        else
            log_error "恢复点验证失败"
            echo "结果: 失败" >> "$verify_report_file"
            verify_errors=$((verify_errors + 1))
        fi
    else
        log_info "跳过恢复点验证 (未启用)"
        echo "\n7. 恢复点验证: 已跳过 (未启用)" >> "$verify_report_file"
    fi
    
    # 验证报告总结
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "\n===================================" >> "$verify_report_file"
    echo "验证总结:" >> "$verify_report_file"
    echo "- 总验证项: 7" >> "$verify_report_file"
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

#############################################################
# 函数：verify_file_integrity
# 功能：验证备份文件的完整性
# 参数：无
# 返回值：
#   0 - 验证通过
#   1 - 验证失败
#############################################################
verify_file_integrity() {
    log_info "验证文件完整性..."
    local errors=0
    local warnings=0
    
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
        log_warn "未找到校验和工具，将使用基本文件属性进行验证"
        warnings=$((warnings + 1))
    else
        log_info "使用 $checksum_tool 进行文件完整性验证"
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
        local checksum_file="${BACKUP_ROOT}/backup_${DATE_FORMAT}.${checksum_ext}"
        
        # 如果存在校验和文件，验证校验和
        if [ -n "$checksum_tool" ] && [ -f "$checksum_file" ]; then
            log_info "验证备份文件校验和..."
            if ! $checksum_tool -c "$checksum_file" &>/dev/null; then
                log_error "校验和验证失败: $full_archive_path"
                errors=$((errors + 1))
            else
                log_info "校验和验证通过: $full_archive_path"
            fi
        fi
        
        # 使用压缩工具验证压缩文件
        local verify_cmd=""
        case "$COMPRESS_METHOD" in
            "gzip")
                verify_cmd="gzip -t \"${full_archive_path}\" &>/dev/null"
                ;;
            "bzip2")
                verify_cmd="bzip2 -t \"${full_archive_path}\" &>/dev/null"
                ;;
            "xz")
                verify_cmd="xz -t \"${full_archive_path}\" &>/dev/null"
                ;;
        esac
        
        if [ -n "$verify_cmd" ]; then
            log_info "使用压缩工具验证文件完整性..."
            if ! eval "$verify_cmd"; then
                log_error "压缩文件验证失败: $full_archive_path"
                errors=$((errors + 1))
            else
                log_info "压缩文件验证通过: $full_archive_path"
            fi
        fi
    else
        # 验证未压缩的备份
        log_info "验证未压缩备份的文件完整性..."
        
        # 对每个目录进行抽样检查
        for dir in ${BACKUP_DIRS}; do
            if [ ! -d "${BACKUP_DIR}/${dir}" ]; then
                continue # 目录不存在，跳过
            fi
            
            log_info "对 ${dir} 目录进行抽样文件验证"
            
            # 检查空文件
            local empty_files=$(find "${BACKUP_DIR}/${dir}" -type f -size 0 -name "*" | wc -l)
            if [ "$empty_files" -gt 0 ]; then
                log_warn "在 ${dir} 目录中发现 $empty_files 个空文件"
                warnings=$((warnings + 1))
            fi
            
            # 检查不可读文件
            local unreadable_files=$(find "${BACKUP_DIR}/${dir}" -type f ! -readable -name "*" | wc -l)
            if [ "$unreadable_files" -gt 0 ]; then
                log_warn "在 ${dir} 目录中发现 $unreadable_files 个不可读文件"
                warnings=$((warnings + 1))
            fi
            
            # 对重要文件进行校验和计算
            if [ -n "$checksum_tool" ]; then
                local important_files=($(find "${BACKUP_DIR}/${dir}" -type f -name "*.conf" -o -name "*.txt" -o -name "*.sh" | sort | head -5 2>/dev/null))
                
                if [ ${#important_files[@]} -gt 0 ]; then
                    log_debug "对 ${#important_files[@]} 个重要文件计算校验和"
                    
                    for file in "${important_files[@]}"; do
                        if ! check_file_integrity "$file" "重要文件"; then
                            log_error "文件完整性检查失败: $file"
                            errors=$((errors + 1))
                        fi
                    done
                fi
            fi
        done
    fi
    
    if [ $errors -eq 0 ]; then
        if [ $warnings -gt 0 ]; then
            log_notice "文件完整性验证通过，但有 $warnings 个警告"
        else
            log_info "文件完整性验证完全通过"
        fi
        return 0
    else
        log_error "文件完整性验证失败，发现 $errors 个错误和 $warnings 个警告"
        return 1
    fi
}

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
            if [ ! -f "${BACKUP_DIR}/etc/${file}" ]; then
                log_warn "关键系统配置文件不存在: ${file}"
            fi
        done
    fi
    
    # 验证用户配置目录结构
    if [ "$BACKUP_USER_CONFIG" == "true" ] && [ -d "${BACKUP_DIR}/home" ]; then
        # 检查是否至少有一个用户目录
        local user_dirs=$(find "${BACKUP_DIR}/home" -mindepth 1 -maxdepth 1 -type d | wc -l)
        if [ "$user_dirs" -eq 0 ]; then
            log_warn "用户配置目录为空，没有用户目录"
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

#############################################################
# 函数：verify_statistics
# 功能：验证备份的统计信息
# 参数：无
# 返回值：
#   0 - 验证通过
#   1 - 验证失败
#############################################################
verify_statistics() {
    log_info "验证备份统计信息..."
    local errors=0
    
    # 只对未压缩的备份进行统计验证
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        log_info "压缩备份不进行统计信息验证"
        return 0
    fi
    
    # 验证系统配置备份统计
    if [ "$BACKUP_SYSTEM_CONFIG" == "true" ]; then
        local source_dir="/etc"
        local target_dir="${BACKUP_DIR}/etc"
        local excludes="$EXCLUDE_SYSTEM_CONFIGS"
        
        # 将排除项数组转换为换行符分隔的字符串
        local excludes_string=""
        for item in $excludes; do
            excludes_string+="${item}\n"
        done
        
        if ! verify_backup_stats "$source_dir" "$target_dir" "系统配置" "$excludes_string"; then
            log_error "系统配置备份统计验证失败"
            errors=$((errors + 1))
        fi
    fi
    
    # 验证用户配置备份统计
    if [ "$BACKUP_USER_CONFIG" == "true" ]; then
        # 对每个用户目录进行验证
        local user_dirs=($(find "${BACKUP_DIR}/home" -mindepth 1 -maxdepth 1 -type d 2>/dev/null))
        
        for user_dir in "${user_dirs[@]}"; do
            local user=$(basename "$user_dir")
            local source_dir="/home/${user}"
            local target_dir="${BACKUP_DIR}/home/${user}"
            local excludes="$EXCLUDE_USER_CONFIGS"
            
            # 将排除项数组转换为换行符分隔的字符串
            local excludes_string=""
            for item in $excludes; do
                excludes_string+="${item}\n"
            done
            
            if ! verify_backup_stats "$source_dir" "$target_dir" "用户配置 ($user)" "$excludes_string"; then
                log_error "用户配置备份统计验证失败: $user"
                errors=$((errors + 1))
            fi
        done
    fi
    
    # 验证自定义路径备份统计
    if [ "$BACKUP_CUSTOM_PATHS" == "true" ] && [ -d "${BACKUP_DIR}/custom" ]; then
        local custom_paths=($CUSTOM_PATHS)
        local exclude_paths=($EXCLUDE_CUSTOM_PATHS)
        
        for path in "${custom_paths[@]}"; do
            # 跳过不存在的路径
            if [ ! -e "$path" ]; then
                continue
            fi
            
            local path_name=$(echo "$path" | sed 's/[\/]/_/g' | sed 's/^_//')
            local target_dir="${BACKUP_DIR}/custom/${path_name}"
            
            # 如果目标目录不存在，跳过
            if [ ! -d "$target_dir" ]; then
                continue
            fi
            
            # 将排除项数组转换为换行符分隔的字符串
            local excludes_string=""
            for item in "${exclude_paths[@]}"; do
                excludes_string+="${item}\n"
            done
            
            if ! verify_backup_stats "$path" "$target_dir" "自定义路径 ($path)" "$excludes_string"; then
                log_error "自定义路径备份统计验证失败: $path"
                errors=$((errors + 1))
            fi
        done
    fi
    
    if [ $errors -eq 0 ]; then
        log_info "统计信息验证通过"
        return 0
    else
        log_error "统计信息验证失败，发现 $errors 个错误"
        return 1
    fi
}

#############################################################
# 函数：verify_exclusions
# 功能：验证排除项是否正确排除
# 参数：无
# 返回值：
#   0 - 验证通过
#   1 - 验证失败
#############################################################
verify_exclusions() {
    log_info "验证排除项..."
    local errors=0
    
    # 只对未压缩的备份进行排除项验证
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        log_info "压缩备份不进行排除项验证"
        return 0
    fi
    
    # 验证系统配置排除项
    if [ "$BACKUP_SYSTEM_CONFIG" == "true" ] && [ -d "${BACKUP_DIR}/etc" ]; then
        log_info "验证系统配置排除项..."
        local exclude_items=($EXCLUDE_SYSTEM_CONFIGS)
        
        for item in "${exclude_items[@]}"; do
            # 跳过空项
            if [ -z "$item" ]; then
                continue
            fi
            
            # 检查排除项是否确实不在备份中
            local full_path="${BACKUP_DIR}/etc/${item}"
            if [ -e "$full_path" ]; then
                log_error "排除项验证失败: 系统配置排除项 '$item' 存在于备份中: $full_path"
                errors=$((errors + 1))
            else
                log_debug "排除项验证通过: 系统配置排除项 '$item' 不在备份中"
            fi
        done
    fi
    
    # 验证用户配置排除项
    if [ "$BACKUP_USER_CONFIG" == "true" ] && [ -d "${BACKUP_DIR}/home" ]; then
        log_info "验证用户配置排除项..."
        local exclude_items=($EXCLUDE_USER_CONFIGS)
        local user_dirs=($(find "${BACKUP_DIR}/home" -mindepth 1 -maxdepth 1 -type d 2>/dev/null))
        
        for user_dir in "${user_dirs[@]}"; do
            local user=$(basename "$user_dir")
            
            for item in "${exclude_items[@]}"; do
                # 跳过空项
                if [ -z "$item" ]; then
                    continue
                fi
                
                # 检查排除项是否确实不在备份中
                local full_path="${BACKUP_DIR}/home/${user}/${item}"
                if [ -e "$full_path" ]; then
                    log_error "排除项验证失败: 用户配置排除项 '$item' 存在于用户 '$user' 的备份中: $full_path"
                    errors=$((errors + 1))
                else
                    log_debug "排除项验证通过: 用户配置排除项 '$item' 不在用户 '$user' 的备份中"
                fi
            done
        done
    fi
    
    # 验证自定义路径排除项
    if [ "$BACKUP_CUSTOM_PATHS" == "true" ] && [ -d "${BACKUP_DIR}/custom" ]; then
        log_info "验证自定义路径排除项..."
        local exclude_items=($EXCLUDE_CUSTOM_PATHS)
        
        for item in "${exclude_items[@]}"; do
            # 跳过空项
            if [ -z "$item" ]; then
                continue
            fi
            
            # 对于自定义路径的排除项，需要检查所有可能的位置
            local found=false
            find "${BACKUP_DIR}/custom" -type d | while read custom_dir; do
                local rel_path="${custom_dir}/${item}"
                if [ -e "$rel_path" ]; then
                    log_error "排除项验证失败: 自定义路径排除项 '$item' 存在于备份中: $rel_path"
                    errors=$((errors + 1))
                    found=true
                    break
                fi
            done
            
            if [ "$found" == "false" ]; then
                log_debug "排除项验证通过: 自定义路径排除项 '$item' 不在备份中"
            fi
        done
    fi
    
    if [ $errors -eq 0 ]; then
        log_info "排除项验证通过"
        return 0
    else
        log_error "排除项验证失败，发现 $errors 个错误"
        return 1
    fi
}

#############################################################
# 函数：verify_recovery_point
# 功能：验证恢复点的有效性
# 参数：无
# 返回值：
#   0 - 验证通过
#   1 - 验证失败
#############################################################
verify_recovery_point() {
    log_info "验证恢复点..."
    local errors=0
    
    # 查找最新的恢复点文件
    local recovery_files=($(find "$BACKUP_ROOT" -name "recovery_*.json" -type f | sort -r))
    
    if [ ${#recovery_files[@]} -eq 0 ]; then
        log_info "没有找到恢复点，跳过恢复点验证"
        return 0
    fi
    
    local latest_recovery="${recovery_files[0]}"
    log_info "验证最新的恢复点: $latest_recovery"
    
    # 检查恢复点文件是否存在且非空
    if ! check_file_integrity "$latest_recovery" "恢复点文件"; then
        log_error "恢复点文件完整性检查失败: $latest_recovery"
        errors=$((errors + 1))
    fi
    
    # 解析恢复点文件（简单解析，不使用jq等工具以减少依赖）
    local recovery_timestamp=$(grep -o '"timestamp": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    local recovery_stage=$(grep -o '"stage": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    local recovery_dir=$(grep -o '"backup_dir": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    
    # 验证恢复点信息是否完整
    if [ -z "$recovery_timestamp" ] || [ -z "$recovery_stage" ] || [ -z "$recovery_dir" ]; then
        log_error "恢复点文件格式不正确或信息不完整: $latest_recovery"
        errors=$((errors + 1))
    else
        log_debug "恢复点信息: 时间戳=$recovery_timestamp, 阶段=$recovery_stage, 备份目录=$recovery_dir"
        
        # 验证恢复点中的备份目录是否存在
        if [ ! -d "$recovery_dir" ]; then
            log_error "恢复点中的备份目录不存在: $recovery_dir"
            errors=$((errors + 1))
        fi
        
        # 验证恢复点阶段是否有效
        case "$recovery_stage" in
            "system_config"|"user_config"|"custom_paths"|"packages"|"logs")
                log_debug "恢复点阶段有效: $recovery_stage"
                ;;
            *)
                log_error "恢复点阶段无效: $recovery_stage"
                errors=$((errors + 1))
                ;;
        esac
    fi
    
    if [ $errors -eq 0 ]; then
        log_info "恢复点验证通过"
        return 0
    else
        log_error "恢复点验证失败，发现 $errors 个错误"
        return 1
    fi
}CONFIG" == "true" ] && [ -d "${BACKUP_DIR}/etc" ]; then
        log_info "验证系统配置排除项..."
        local exclude_items=($EXCLUDE_SYSTEM_CONFIGS)
        
        for item in "${exclude_items[@]}"; do
            # 跳过空项
            if [ -z "$item" ]; then
                continue
            fi
            
            # 检查排除项是否确实不在备份中
            local full_path="${BACKUP_DIR}/etc/${item}"
            if [ -e "$full_path" ]; then
                log_error "排除项验证失败: 系统配置排除项 '$item' 存在于备份中: $full_path"
                errors=$((errors + 1))
            else
                log_debug "排除项验证通过: 系统配置排除项 '$item' 不在备份中"
            fi
        done
    fi
    
    # 验证用户配置排除项
    if [ "$BACKUP_USER_CONFIG" == "true" ] && [ -d "${BACKUP_DIR}/home" ]; then
        log_info "验证用户配置排除项..."
        local exclude_items=($EXCLUDE_USER_CONFIGS)
        local user_dirs=($(find "${BACKUP_DIR}/home" -mindepth 1 -maxdepth 1 -type d 2>/dev/null))
        
        for user_dir in "${user_dirs[@]}"; do
            local user=$(basename "$user_dir")
            
            for item in "${exclude_items[@]}"; do
                # 跳过空项
                if [ -z "$item" ]; then
                    continue
                fi
                
                # 检查排除项是否确实不在备份中
                local full_path="${BACKUP_DIR}/home/${user}/${item}"
                if [ -e "$full_path" ]; then
                    log_error "排除项验证失败: 用户配置排除项 '$item' 存在于用户 '$user' 的备份中: $full_path"
                    errors=$((errors + 1))
                else
                    log_debug "排除项验证通过: 用户配置排除项 '$item' 不在用户 '$user' 的备份中"
                fi
            done
        done
    fi
    
    # 验证自定义路径排除项
    if [ "$BACKUP_CUSTOM_PATHS" == "true" ] && [ -d "${BACKUP_DIR}/custom" ]; then
        log_info "验证自定义路径排除项..."
        local exclude_items=($EXCLUDE_CUSTOM_PATHS)
        
        for item in "${exclude_items[@]}"; do
            # 跳过空项
            if [ -z "$item" ]; then
                continue
            fi
            
            # 对于自定义路径的排除项，需要检查所有可能的位置
            local found=false
            find "${BACKUP_DIR}/custom" -type d | while read custom_dir; do
                local rel_path="${custom_dir}/${item}"
                if [ -e "$rel_path" ]; then
                    log_error "排除项验证失败: 自定义路径排除项 '$item' 存在于备份中: $rel_path"
                    errors=$((errors + 1))
                    found=true
                    break
                fi
            done
            
            if [ "$found" == "false" ]; then
                log_debug "排除项验证通过: 自定义路径排除项 '$item' 不在备份中"
            fi
        done
    fi
    
    if [ $errors -eq 0 ]; then
        log_info "排除项验证通过"
        return 0
    else
        log_error "排除项验证失败，发现 $errors 个错误"
        return 1
    fi
}

#############################################################
# 函数：verify_recovery_point
# 功能：验证恢复点的有效性
# 参数：无
# 返回值：
#   0 - 验证通过
#   1 - 验证失败
#############################################################
verify_recovery_point() {
    log_info "验证恢复点..."
    local errors=0
    
    # 查找最新的恢复点文件
    local recovery_files=($(find "$BACKUP_ROOT" -name "recovery_*.json" -type f | sort -r))
    
    if [ ${#recovery_files[@]} -eq 0 ]; then
        log_info "没有找到恢复点，跳过恢复点验证"
        return 0
    fi
    
    local latest_recovery="${recovery_files[0]}"
    log_info "验证最新的恢复点: $latest_recovery"
    
    # 检查恢复点文件是否存在且非空
    if ! check_file_integrity "$latest_recovery" "恢复点文件"; then
        log_error "恢复点文件完整性检查失败: $latest_recovery"
        errors=$((errors + 1))
    fi
    
    # 解析恢复点文件（简单解析，不使用jq等工具以减少依赖）
    local recovery_timestamp=$(grep -o '"timestamp": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    local recovery_stage=$(grep -o '"stage": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    local recovery_dir=$(grep -o '"backup_dir": "[^"]*"' "$latest_recovery" | cut -d '"' -f 4)
    
    # 验证恢复点信息是否完整
    if [ -z "$recovery_timestamp" ] || [ -z "$recovery_stage" ] || [ -z "$recovery_dir" ]; then
        log_error "恢复点文件格式不正确或信息不完整: $latest_recovery"
        errors=$((errors + 1))
    else
        log_debug "恢复点信息: 时间戳=$recovery_timestamp, 阶段=$recovery_stage, 备份目录=$recovery_dir"
        
        # 验证恢复点中的备份目录是否存在
        if [ ! -d "$recovery_dir" ]; then
            log_error "恢复点中的备份目录不存在: $recovery_dir"
            errors=$((errors + 1))
        fi
        
        # 验证恢复点阶段是否有效
        case "$recovery_stage" in
            "system_config"|"user_config"|"custom_paths"|"packages"|"logs")
                log_debug "恢复点阶段有效: $recovery_stage"
                ;;
            *)
                log_error "恢复点阶段无效: $recovery_stage"
                errors=$((errors + 1))
                ;;
        esac
    fi
    
    if [ $errors -eq 0 ]; then
        log_info "恢复点验证通过"
        return 0
    else
        log_error "恢复点验证失败，发现 $errors 个错误"
        return 1
    fi
}
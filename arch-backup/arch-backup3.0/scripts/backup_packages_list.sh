# 备份软件包列表
# 功能：备份系统中安装的软件包列表
# 参数：无
# 返回值：
#   0 - 备份成功
#   1 - 备份失败
# 错误处理：
#   检查pacman命令是否可用
#   使用重试机制执行pacman命令
#   验证备份文件完整性
# 备份内容：
#   - 手动安装的软件包列表
#   - 所有安装的软件包列表
#   - 外部软件包列表（非官方仓库）
#   - pacman日志
# 特性：
#   - 使用临时目录进行备份，成功后移动到最终位置
#   - 备份完成后创建恢复点
# 使用示例：
#   backup_packages || log "ERROR" "软件包列表备份失败"
backup_packages() {
    if [ "$BACKUP_PACKAGES" != "true" ]; then
        log "INFO" "跳过软件包列表备份"
        return 0
    fi
    
    log "INFO" "开始备份软件包列表..."
    
    # 检查 pacman 是否可用
    if ! command -v pacman &> /dev/null; then
        log "ERROR" "pacman 命令不可用，无法备份软件包列表"
        return 1
    fi
    
    # 创建临时目录用于存储软件包列表
    local temp_dir="${BACKUP_DIR}/packages.tmp"
    mkdir -p "$temp_dir"
    
    # 定义备份文件路径
    local manually_installed_file="${temp_dir}/manually-installed.txt"
    local all_packages_file="${temp_dir}/all-packages.txt"
    local foreign_packages_file="${temp_dir}/foreign-packages.txt"
    local pacman_log_file="${temp_dir}/pacman.log"
    
    # 备份手动安装的软件包列表
    if exec_with_retry "pacman -Qe > \"${manually_installed_file}\"" "手动安装的软件包列表备份"; then
        log "INFO" "手动安装的软件包列表备份完成"
        check_file_integrity "$manually_installed_file" "手动安装的软件包列表"
    else
        log "ERROR" "手动安装的软件包列表备份失败"
    fi
    
    # 备份所有安装的软件包列表
    if exec_with_retry "pacman -Q > \"${all_packages_file}\"" "所有软件包列表备份"; then
        log "INFO" "所有软件包列表备份完成"
        check_file_integrity "$all_packages_file" "所有软件包列表"
    else
        log "ERROR" "所有软件包列表备份失败"
    fi
    
    # 备份外部软件包列表（非官方仓库）
    if exec_with_retry "pacman -Qm > \"${foreign_packages_file}\"" "外部软件包列表备份"; then
        log "INFO" "外部软件包列表备份完成"
        check_file_integrity "$foreign_packages_file" "外部软件包列表"
    else
        log "ERROR" "外部软件包列表备份失败"
    fi
    
    # 备份 pacman 日志
    if [ -f "/var/log/pacman.log" ]; then
        if exec_with_retry "sudo cp /var/log/pacman.log \"${pacman_log_file}\"" "Pacman 日志备份"; then
            log "INFO" "Pacman 日志备份完成"
            check_file_integrity "$pacman_log_file" "Pacman 日志"
        else
            log "ERROR" "Pacman 日志备份失败"
        fi
    else
        log "WARN" "Pacman 日志文件不存在"
    fi
    
    # 移动临时目录到最终目录
    if [ -d "$temp_dir" ]; then
        if mv "$temp_dir"/* "${BACKUP_DIR}/packages/" 2>> "$LOG_FILE"; then
            log "INFO" "软件包列表备份文件移动成功"
            rm -rf "$temp_dir"
            # create_recovery_point "packages"
            return 0
        else
            log "ERROR" "软件包列表备份文件移动失败"
            return 1
        fi
    else
        log "ERROR" "软件包列表临时目录不存在"
        return 1
    fi
}
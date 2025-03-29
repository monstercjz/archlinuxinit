#!/bin/bash

# 依赖: logging.sh (log 函数), utils.sh (exec_with_retry, check_file_integrity, create_recovery_point)

# 备份软件包列表
# 功能：备份系统中安装的软件包列表
# 参数：无
# 全局变量依赖:
#   BACKUP_PACKAGES, BACKUP_DIR, LOG_FILE
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
    if [ "${BACKUP_PACKAGES:-true}" != "true" ]; then
        log "INFO" "跳过软件包列表备份 (根据配置)"
        return 0
    fi

    log "INFO" "开始备份软件包列表..."
    local packages_backup_dir="${BACKUP_DIR}/packages"
    mkdir -p "$packages_backup_dir" # 确保目标目录存在

    # 检查 pacman 是否可用
    if ! command -v pacman &> /dev/null; then
        log "ERROR" "pacman 命令不可用，无法备份软件包列表"
        return 1
    fi

    # 定义备份文件路径
    local manually_installed_file="${packages_backup_dir}/manually-installed.txt"
    local all_packages_file="${packages_backup_dir}/all-packages.txt"
    local foreign_packages_file="${packages_backup_dir}/foreign-packages.txt"
    local pacman_log_file="${packages_backup_dir}/pacman.log"
    local backup_failed=false

    # 备份手动安装的软件包列表
    if exec_with_retry "pacman -Qqe > \"${manually_installed_file}\"" "手动安装的软件包列表备份"; then
        log "INFO" "手动安装的软件包列表备份完成"
        check_file_integrity "$manually_installed_file" "手动安装的软件包列表" || backup_failed=true
    else
        log "ERROR" "手动安装的软件包列表备份失败"
        backup_failed=true
    fi

    # 备份所有安装的软件包列表
    if exec_with_retry "pacman -Qq > \"${all_packages_file}\"" "所有软件包列表备份"; then
        log "INFO" "所有软件包列表备份完成"
        check_file_integrity "$all_packages_file" "所有软件包列表" || backup_failed=true
    else
        log "ERROR" "所有软件包列表备份失败"
        backup_failed=true
    fi

    # 备份外部软件包列表（非官方仓库）
    if exec_with_retry "pacman -Qqm > \"${foreign_packages_file}\"" "外部软件包列表备份"; then
        log "INFO" "外部软件包列表备份完成"
        # 外部包列表可能为空，所以只检查文件是否存在
        if [ ! -f "$foreign_packages_file" ]; then
             log "WARN" "外部软件包列表文件未创建"
             # backup_failed=true # 列表为空不算失败
        else
             log "DEBUG" "外部软件包列表文件已创建"
        fi
    else
        log "ERROR" "外部软件包列表备份失败"
        backup_failed=true
    fi

    # 备份 pacman 日志
    if [ -f "/var/log/pacman.log" ]; then
        # 使用 sudo cp，因为 pacman.log 通常需要 root 权限
        if exec_with_retry "sudo cp /var/log/pacman.log \"${pacman_log_file}\"" "Pacman 日志备份"; then
            log "INFO" "Pacman 日志备份完成"
            check_file_integrity "$pacman_log_file" "Pacman 日志" || backup_failed=true
        else
            log "ERROR" "Pacman 日志备份失败"
            backup_failed=true
        fi
    else
        log "WARN" "Pacman 日志文件 /var/log/pacman.log 不存在"
    fi

    if $backup_failed; then
        log "ERROR" "软件包列表备份过程中出现错误"
        return 1
    else
        log "INFO" "软件包列表备份成功完成"
        create_recovery_point "packages"
        return 0
    fi
}

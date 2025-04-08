#!/bin/bash

#############################################################
# Arch Linux 自动备份脚本
# 根据 arch-back-list.md 中的建议创建
# 功能：备份系统配置、用户配置、自定义路径、软件包列表和系统日志
# 支持压缩备份、差异备份和备份验证
# 3.0 版本：支持可配置的备份目录结构
#   可自定义的用户配置文件列表
#   灵活的备份选项
# 4.0 版本优化日志优化显示排除项
# 5.0 版本更新：可自定义的备份路径
# 5.1 版本
#   - 增强的错误处理机制：
#   - 自动重试功能（失败操作自动重试）
#   - 文件完整性检查（确保备份文件的完整性）
#   - 恢复点功能（在关键步骤创建检查点以便从故障中恢复）
# 5.2 版本
#   - 备份进度显示（支持进度条或百分比显示）
# 5.3 版本
#   - 并行备份功能（支持多任务同时执行，提高备份速度）
#   - 新增配置选项：PARALLEL_BACKUP 和 PARALLEL_JOBS
#   - 支持 GNU Parallel 工具（如已安装）或使用内置的后台进程实现
# 5.4 版本
#   - 依赖性检查增强：更全面地检查所有必要的依赖项
#   - 添加工具版本检查功能，确保工具版本满足最低要求
#   - 分类检查核心依赖、压缩工具、网络工具、加密工具和恢复测试工具
#   - 提供更详细的错误信息和安装建议
# 5.45 版本
#   - 添加注释
# 由5.46版本拆分而来，也就是newarch2.0版本
#############################################################

# 获取脚本所在目录
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Source utility scripts
for util_script in "$SCRIPT_DIR"/core/*.sh; do
    if [ -f "$util_script" ]; then
        # shellcheck source=utils/config.sh
        # shellcheck source=utils/load_config.sh
        # shellcheck source=utils/loggings.sh
        # shellcheck source=utils/check_command_version.sh
        # shellcheck source=utils/check_command.sh
        # shellcheck source=utils/create_backup_dirs.sh 
        source "$util_script"
    fi
done

# Source module scripts
for module_script in "$SCRIPT_DIR"/modules/*.sh; do
    if [ -f "$module_script" ]; then
        # shellcheck source=modules/check_dependencies.sh
        # shellcheck source=modules/check_file_integrity.sh
        # shellcheck source=modules/check_recovery_point.sh
        # shellcheck source=modules/clean_old_backups.sh
        # shellcheck source=modules/compress_backup.sh
        # shellcheck source=modules/create_backup_summary.sh
        # shellcheck source=modules/create_recovery_point.sh
        # shellcheck source=modules/exec_with_retry.sh
        # shellcheck source=modules/find_last_backup.sh
        # shellcheck source=modules/run_parallel_backup.sh
        # shellcheck source=modules/verify_backup.sh
        source "$module_script"
    fi
done

# Source backup task scripts
for backup_script in "$SCRIPT_DIR"/scripts/*.sh; do
    if [ -f "$backup_script" ]; then
        # shellcheck source=backup-scripts/backup_custom_config.sh
        # shellcheck source=backup-scripts/backup_logs.sh
        # shellcheck source=backup-scripts/backup_packages_list.sh
        # shellcheck source=backup-scripts/backup_system_config.sh
        # shellcheck source=backup-scripts/backup_usr_config.sh
        source "$backup_script"
    fi
done


# 主函数
main() {
    # 加载配置
    load_config || { log "FATAL" "加载配置失败，无法继续"; exit 1; }
    
    log_section "开始 Arch Linux 备份 (${TIMESTAMP})"  $LOG_LEVEL_NOTICE
    
    # 设置错误处理陷阱
    trap 'log "ERROR" "备份过程被中断，请检查日志: $LOG_FILE"; exit 1' INT TERM

    log_section "第一步：必备软件是否安装检测"  $LOG_LEVEL_NOTICE

    # 检查是否为 root 用户
    if [ "$(id -u)" -ne 0 ]; then
        log "WARN" "脚本未以 root 用户运行，某些系统文件可能无法备份"
        log "WARN" "建议使用 sudo 运行此脚本以获得完整的备份权限"
    fi
    
    # 检查依赖
    check_dependencies || { log "FATAL" "依赖检查失败，无法继续"; exit 1; }
    
    log_section "第二步：备份目录检测与创建"  $LOG_LEVEL_NOTICE

    # 检查备份目录是否可写，0为真，1为假
    if check_and_create_directory "$BACKUP_ROOT"; then
        log "INFO" "目录检查正常，继续执行后续操作..."
    else
        log "ERROR" "目录检查和创建失败，退出程序..."
        exit 1
    fi
    
    log_section "第三步：恢复点检测与设置"  $LOG_LEVEL_NOTICE

    # 检查是否存在恢复点
    check_recovery_point
    
    # 查找最近的备份目录（用于差异备份）
    find_last_backup
    
    # 创建备份目录（如果不是从恢复点继续）
    log "INFO" "开始检查并创建备份子文件夹..."
    if ! create_backup_dirs ; then
        # create_backup_dirs || { log "FATAL" "创建备份目录失败，无法继续"; exit 1; }
        log "FATAL" "创建备份目录失败，无法继续"
        exit 1
    fi
    
    # 初始化跳过标志（如果未从恢复点设置）
    log "INFO" "重置恢复点设置..."
    SKIP_SYSTEM_CONFIG=${SKIP_SYSTEM_CONFIG:-false}
    SKIP_USER_CONFIG=${SKIP_USER_CONFIG:-false}
    SKIP_CUSTOM_PATHS=${SKIP_CUSTOM_PATHS:-false}
    SKIP_PACKAGES=${SKIP_PACKAGES:-false}
    SKIP_LOGS=${SKIP_LOGS:-false}
    
    log_section "第四步：开始进行备份..."  $LOG_LEVEL_NOTICE

    # 执行备份，根据跳过标志和配置决定是否执行
    local backup_errors=0
    
    # 判断是否使用并行备份
    if [ "$PARALLEL_BACKUP" == "true" ]; then
        log "INFO" "启用并行备份模式，最大并行任务数: $PARALLEL_JOBS"
        
        # 准备并行任务列表
        local parallel_tasks=()
        
        # 添加备份任务到列表
        if [ "$SKIP_SYSTEM_CONFIG" != "true" ] && [ "$BACKUP_SYSTEM_CONFIG" == "true" ]; then
            parallel_tasks+=("backup_system_config")
        fi
        log "NOTICE" "备份系统配置文件结束..."
        if [ "$SKIP_USER_CONFIG" != "true" ] && [ "$BACKUP_USER_CONFIG" == "true" ]; then
            parallel_tasks+=("backup_user_config")
        fi
        
        if [ "$SKIP_CUSTOM_PATHS" != "true" ] && [ "$BACKUP_CUSTOM_PATHS" == "true" ]; then
            parallel_tasks+=("backup_custom_paths")
        fi
        
        if [ "$SKIP_PACKAGES" != "true" ] && [ "$BACKUP_PACKAGES" == "true" ]; then
            parallel_tasks+=("backup_packages")
        fi
        
        if [ "$SKIP_LOGS" != "true" ] && [ "$BACKUP_LOGS" == "true" ]; then
            parallel_tasks+=("backup_logs")
        fi
        
        # 执行并行备份
        if [ ${#parallel_tasks[@]} -gt 0 ]; then
            log "INFO" "开始执行 ${#parallel_tasks[@]} 个并行备份任务"
            if ! run_parallel_backup "${parallel_tasks[@]}"; then
                backup_errors=$((backup_errors + 1))
                log "WARN" "并行备份任务部分失败，请检查日志获取详细信息"
            else
                log "INFO" "并行备份任务全部成功完成"
            fi
        else
            log "INFO" "没有需要执行的备份任务"
        fi
    else
        # 顺序执行备份任务
        log "INFO" "配置选项 PARALLEL_BACKUP 为 "$PARALLEL_BACKUP" ，使用顺序备份模式"
        
        # 备份系统配置
        if [ "$SKIP_SYSTEM_CONFIG" != "true" ] && [ "$BACKUP_SYSTEM_CONFIG" == "true" ]; then
            backup_system_config || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过系统配置备份 (已完成或已禁用)"
        fi
        log "NOTICE" "备份系统配置文件结束..."
        
        # 备份用户配置
        if [ "$SKIP_USER_CONFIG" != "true" ] && [ "$BACKUP_USER_CONFIG" == "true" ]; then
            backup_user_config || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过用户配置备份 (已完成或已禁用)"
        fi
        
        # 备份自定义路径
        if [ "$SKIP_CUSTOM_PATHS" != "true" ] && [ "$BACKUP_CUSTOM_PATHS" == "true" ]; then
            backup_custom_paths || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过自定义路径备份 (已完成或已禁用)"
        fi
        
        # 备份软件包列表
        if [ "$SKIP_PACKAGES" != "true" ] && [ "$BACKUP_PACKAGES" == "true" ]; then
            backup_packages || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过软件包列表备份 (已完成或已禁用)"
        fi
        
        # 备份系统日志
        if [ "$SKIP_LOGS" != "true" ] && [ "$BACKUP_LOGS" == "true" ]; then
            backup_logs || backup_errors=$((backup_errors + 1))
        else
            log "INFO" "跳过系统日志备份 (已完成或已禁用)"
        fi
    fi
        

    log_section "第五步：报告备份错误"  $LOG_LEVEL_NOTICE

    # 报告备份错误
    if [ $backup_errors -gt 0 ]; then
        log "WARN" "备份过程中发生 $backup_errors 个错误，请检查日志获取详细信息"
    fi
    
    log_section "第六步：创建备份摘要"  $LOG_LEVEL_NOTICE

    # 创建备份摘要
    create_backup_summary || log "WARN" "创建备份摘要失败"
    
    log_section "第七步：压缩备份与验证备份"  $LOG_LEVEL_NOTICE
    
    # 压缩备份
    if [ "$COMPRESS_BACKUP" == "true" ]; then
        compress_backup || log "WARN" "压缩备份失败"
    fi
    
    # 验证备份
    if [ "$VERIFY_BACKUP" == "true" ]; then
        verify_backup || log "WARN" "验证备份失败，备份可能不完整"
    fi
    
    log_section "第八步：清理旧备份与临时文件"  $LOG_LEVEL_NOTICE

    # 清理旧备份
    cleanup_old_backups || log "WARN" "清理旧备份失败"
    
    # 清理恢复点文件
    find "$BACKUP_ROOT" -name "recovery_*.json" -type f -delete
    
    # 重置陷阱
    trap - INT TERM
    
    if [ $backup_errors -eq 0 ]; then
        log "INFO" "备份成功完成！备份目录: ${BACKUP_DIR}"
    else
        log "WARN" "备份完成，但有 $backup_errors 个错误，请检查日志获取详细信息"
    fi
    
    log "INFO" "日志文件: ${LOG_FILE}"
    return $backup_errors
}

# 执行主函数
main
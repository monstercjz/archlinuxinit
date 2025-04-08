#!/bin/bash

# 测试备份用户设置的简单脚本

# 获取脚本所在目录
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")

# Source utility scripts from core directory
log "DEBUG" "Sourcing core utility scripts..."
for util_script in "$SCRIPT_DIR"/core/*.sh; do
    if [ -f "$util_script" ]; then
        # shellcheck source=/dev/null
        source "$util_script"
        log "DEBUG" "Sourced: $util_script"
    fi
done

# Source backup task scripts from scripts directory
log "DEBUG" "Sourcing backup task scripts..."
for backup_script in "$SCRIPT_DIR"/scripts/*.sh; do
    if [ -f "$backup_script" ]; then
        # shellcheck source=/dev/null
        source "$backup_script"
        log "DEBUG" "Sourced: $backup_script"
    fi
done

# Source file-check utility scripts from file-check directory
log "DEBUG" "Sourcing file-check utility scripts..."
for check_script in "$SCRIPT_DIR"/file-check/*.sh; do
    if [ -f "$check_script" ]; then
        # shellcheck source=/dev/null
        source "$check_script"
        log "DEBUG" "Sourced: $check_script"
    fi
done

# 主测试函数
test_main() {
    # 加载配置 - 使用默认配置文件 arch-backup.conf
    # load_config 会设置 LOG_FILE, BACKUP_ROOT 等变量
    load_config || { echo "FATAL: 加载配置失败"; exit 1; }

    # 初始化日志系统 (使用 core/loggings.sh)
    # load_config 应该已经设置了 LOG_FILE 和 LOG_LEVEL
    # log 函数现在可用

    log_section "开始用户设置备份测试" $LOG_LEVEL_NOTICE

    # 1. 检查并创建备份根目录
    log "INFO" "检查备份根目录: $BACKUP_ROOT"
    if check_and_create_directory "$BACKUP_ROOT"; then
        log "INFO" "备份根目录检查/创建成功。"
    else
        log "ERROR" "备份根目录检查/创建失败。"
        exit 1
    fi

    # 2. 创建本次备份的具体目录
    # 需要设置 TIMESTAMP 和 BACKUP_DIR 变量
    # TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
    # BACKUP_DIR="${BACKUP_ROOT}/${TIMESTAMP}"
    log "INFO" "创建本次备份目录: $BACKUP_DIR"
    # create_backup_dirs 会创建 BACKUP_DIR 及内部结构 (如 user_config)
    # 它依赖 BACKUP_DIR, BACKUP_USER_CONFIG 等变量 (由 load_config 设置)
    if ! create_backup_dirs ; then
        log "FATAL" "创建备份目录 $BACKUP_DIR 失败"
        exit 1
    fi
    log "INFO" "备份目录创建成功: $BACKUP_DIR"


    # 3. 执行用户设置备份
    log_section "执行用户设置备份" $LOG_LEVEL_NOTICE
    # backup_user_config 需要 BACKUP_DIR, RSYNC_OPTIONS, USER_CONFIG_DIRS, USER_CONFIG_EXCLUDE 等变量
    # 这些变量应该由 load_config 加载
    if backup_custom_config; then
        log "INFO" "用户设置备份成功完成。"
    else
        log "ERROR" "用户设置备份失败。"
        # 决定是否在这里退出
        # exit 1
    fi

    # 4. 验证备份 (简化验证)
    log_section "验证备份 (创建摘要)" $LOG_LEVEL_NOTICE
    if create_backup_summary; then
        log "INFO" "备份摘要创建成功: ${BACKUP_DIR}/backup_summary.txt"
    else
        log "WARN" "创建备份摘要失败。"
    fi

    # 添加更具体的验证：检查 user_config 目录和内容
    log "INFO" "检查备份的用户配置文件目录是否存在..."
    local user_config_backup_path="${BACKUP_DIR}/home"
    if [ -d "${user_config_backup_path}" ]; then
         log "INFO" "用户配置文件目录 ${user_config_backup_path} 存在。"
         log "INFO" "列出备份的用户配置文件内容:"
         ls -alh "${user_config_backup_path}" # 使用 ls -alh 提供更详细信息
         # 可以进一步使用 verify_backup_stats 验证大小和数量
         log "INFO" "尝试使用 verify_backup_stats 验证用户配置..."
         # verify_backup_stats 需要源路径和备份路径中的统计信息文件
         # backup_user_config 应该生成了 ${user_config_backup_path}.stats
         verify_system
    else
         log "WARN" "用户配置文件目录 ${user_config_backup_path} 未找到！"
    fi


    log_section "用户设置备份测试完成" $LOG_LEVEL_NOTICE
    log "INFO" "备份目录: ${BACKUP_DIR}"
    log "INFO" "完整日志文件: ${LOG_FILE}"
}

# 执行测试主函数
test_main

exit $? # 返回主函数的退出状态
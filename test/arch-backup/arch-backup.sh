#!/bin/bash

# Arch Linux Backup Script - Modular Version

# --- 基本设置 ---
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
CONFIG_DIR="${SCRIPT_DIR}/config"
LIB_DIR="${SCRIPT_DIR}/lib"
BACKUP_LIB_DIR="${LIB_DIR}/backup"

# 日期和时间戳
DATE_FORMAT=$(date +"%Y-%m-%d")
TIMESTAMP=$(date +"%Y-%m-%d_%H-%M-%S")

# 获取实际用户和主目录（处理sudo）
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    # 尝试获取用户主目录，如果失败则回退
    REAL_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
    if [ -z "$REAL_HOME" ] || [ ! -d "$REAL_HOME" ]; then
        REAL_HOME="/home/$SUDO_USER" # 备用方案
    fi
else
    REAL_USER=$(whoami)
    REAL_HOME="$HOME"
fi
export REAL_USER REAL_HOME # 导出以便库文件使用

# --- 早期配置和日志初始化 ---
# 设置默认备份根目录，以便尽早定义日志文件路径
# config_loader.sh 稍后会根据配置文件覆盖此值（如果存在）
BACKUP_ROOT="/mnt/backup/arch-backup"
# 定义日志文件路径
LOG_FILE="${BACKUP_ROOT}/backup_${TIMESTAMP}.log"
export LOG_FILE # 导出以便库文件使用

# --- 加载库文件 ---
# 注意加载顺序，有依赖关系的需要先加载

# 基础库 (日志库必须先加载)
source "${LIB_DIR}/logging.sh" || { echo "FATAL: Failed to source logging.sh" >&2; exit 1; }

# 初始化日志文件 (现在 LOG_FILE 已定义)
init_log

# 加载其他基础库
source "${LIB_DIR}/utils.sh" || { log "FATAL" "Failed to source utils.sh"; exit 1; }

# 配置和依赖 (现在可以安全地调用 log 函数了)
source "${LIB_DIR}/config_loader.sh" || { log "FATAL" "Failed to source config_loader.sh"; exit 1; }
source "${LIB_DIR}/dependencies.sh" || { log "FATAL" "Failed to source dependencies.sh"; exit 1; }

# 备份模块
source "${BACKUP_LIB_DIR}/system.sh" || { log "FATAL" "Failed to source backup/system.sh"; exit 1; }
source "${BACKUP_LIB_DIR}/user.sh" || { log "FATAL" "Failed to source backup/user.sh"; exit 1; }
source "${BACKUP_LIB_DIR}/packages.sh" || { log "FATAL" "Failed to source backup/packages.sh"; exit 1; }
source "${BACKUP_LIB_DIR}/logs.sh" || { log "FATAL" "Failed to source backup/logs.sh"; exit 1; }
source "${BACKUP_LIB_DIR}/custom.sh" || { log "FATAL" "Failed to source backup/custom.sh"; exit 1; }

# 其他流程模块
source "${LIB_DIR}/compress.sh" || { log "FATAL" "Failed to source compress.sh"; exit 1; }
source "${LIB_DIR}/validate.sh" || { log "FATAL" "Failed to source validate.sh"; exit 1; }
source "${LIB_DIR}/cleanup.sh" || { log "FATAL" "Failed to source cleanup.sh"; exit 1; }
source "${LIB_DIR}/parallel.sh" || { log "FATAL" "Failed to source parallel.sh"; exit 1; }

# --- 主函数 ---
main() {
    # 定义默认配置文件路径
    local default_config_file="${CONFIG_DIR}/arch-backup.conf"
    # 允许通过命令行参数指定配置文件 (示例)
    local user_config_file="${1:-$default_config_file}"

    # 加载配置 (会设置默认值)
    # load_config 内部会调用 set_default_config 来设置所有默认值
    # 然后尝试加载用户配置文件，覆盖默认值
    load_config "$user_config_file"
    # 注意：此时 BACKUP_ROOT 可能已被配置文件覆盖，但 LOG_FILE 路径保持不变

    log "INFO" "开始 Arch Linux 备份 (${TIMESTAMP})"
    log "INFO" "脚本目录: $SCRIPT_DIR"
    log "INFO" "配置文件: $user_config_file"
    log "INFO" "备份根目录: $BACKUP_ROOT"
    log "INFO" "运行用户: $REAL_USER ($REAL_HOME)"

    # 设置错误处理陷阱
    trap 'log "FATAL" "备份过程被意外中断，请检查日志: $LOG_FILE"; cleanup_recovery_points; exit 1' INT TERM

    # 检查是否为 root 用户 (或有 sudo 权限)
    if [ "$(id -u)" -ne 0 ]; then
        log "WARN" "脚本未以 root 用户运行，某些系统文件/日志可能无法备份或需要 sudo 密码"
        # 检查 sudo 是否可用
        if ! command -v sudo &> /dev/null; then
             log "ERROR" "sudo 命令未找到，且脚本未以 root 运行，系统备份可能失败"
        fi
    fi

    # 检查依赖
    check_dependencies || { log "FATAL" "依赖检查失败，无法继续"; exit 1; }

    # 检查备份目录是否可写
    if [ ! -d "$BACKUP_ROOT" ]; then
        log "INFO" "备份根目录 $BACKUP_ROOT 不存在，尝试创建..."
        if ! mkdir -p "$BACKUP_ROOT"; then
            log "FATAL" "无法创建备份根目录: $BACKUP_ROOT，请检查权限"
            exit 1
        fi
        log "INFO" "备份根目录创建成功"
    elif [ ! -w "$BACKUP_ROOT" ]; then
        log "FATAL" "备份根目录不可写: $BACKUP_ROOT，请检查权限"
        exit 1
    fi
    # 创建临时文件目录（如果 exec_with_retry 需要）
    mkdir -p "${BACKUP_ROOT}/tmp" && chmod 700 "${BACKUP_ROOT}/tmp" || {
        log "FATAL" "无法创建或设置临时目录 ${BACKUP_ROOT}/tmp 的权限"
        exit 1
    }


    # 检查是否存在恢复点 (原脚本逻辑复杂且可能不完善，暂不实现恢复)
    # check_recovery_point

    # 查找最近的备份目录（用于差异备份）
    find_last_backup # 会设置 LAST_BACKUP_DIR

    # 定义本次备份目录
    BACKUP_DIR="${BACKUP_ROOT}/${DATE_FORMAT}"
    export BACKUP_DIR # 导出以便库文件使用

    # 创建备份目录
    if [ ! -d "$BACKUP_DIR" ]; then
        log "INFO" "创建本次备份目录: ${BACKUP_DIR}"
        mkdir -p "$BACKUP_DIR" || { log "FATAL" "创建备份目录失败: $BACKUP_DIR"; exit 1; }
    else
        log "INFO" "使用已存在的备份目录: $BACKUP_DIR (可能是恢复或重复运行)"
    fi

    # 创建备份子目录 (根据配置)
    log "INFO" "创建备份子目录结构..."
    read -ra backup_dirs_array <<< "${BACKUP_DIRS:-}"
    for dir in "${backup_dirs_array[@]}"; do
        mkdir -p "${BACKUP_DIR}/${dir}" || log "WARN" "无法创建子目录: ${BACKUP_DIR}/${dir}"
    done

    # --- 执行备份任务 ---
    local backup_errors=0
    local backup_tasks=()

    # 根据配置将需要执行的备份任务函数名添加到数组
    [ "${BACKUP_SYSTEM_CONFIG:-true}" == "true" ] && backup_tasks+=("backup_system_config")
    [ "${BACKUP_USER_CONFIG:-true}" == "true" ] && backup_tasks+=("backup_user_config")
    [ "${BACKUP_CUSTOM_PATHS:-true}" == "true" ] && backup_tasks+=("backup_custom_paths")
    [ "${BACKUP_PACKAGES:-true}" == "true" ] && backup_tasks+=("backup_packages")
    [ "${BACKUP_LOGS:-true}" == "true" ] && backup_tasks+=("backup_logs")

    if [ ${#backup_tasks[@]} -eq 0 ]; then
        log "WARN" "没有配置任何备份任务，脚本结束"
        exit 0
    fi

    # 判断是否使用并行备份
    if [ "${PARALLEL_BACKUP:-false}" == "true" ]; then
        log "INFO" "启用并行备份模式"
        # 导出需要并行执行的函数，以便 parallel 或子 shell 可以调用
        export -f backup_system_config backup_user_config backup_custom_paths backup_packages backup_logs
        # 导出必要的全局变量
        export LOG_FILE BACKUP_DIR REAL_HOME EXCLUDE_USER_CONFIGS DIFF_BACKUP LAST_BACKUP_DIR USE_PROGRESS_BAR EXCLUDE_SYSTEM_CONFIGS CUSTOM_PATHS EXCLUDE_CUSTOM_PATHS

        if ! run_parallel_backup "${backup_tasks[@]}"; then
            backup_errors=$? # 获取失败任务的数量
            log "WARN" "并行备份任务部分或全部失败 ($backup_errors 失败)"
        else
            log "INFO" "并行备份任务全部成功完成"
        fi
    else
        # 顺序执行备份任务
        log "INFO" "使用顺序备份模式"
        for task_func in "${backup_tasks[@]}"; do
            log "INFO" "--- 开始执行任务: $task_func ---"
            if ! "$task_func"; then
                log "ERROR" "任务 $task_func 执行失败"
                backup_errors=$((backup_errors + 1))
            else
                 log "INFO" "--- 任务 $task_func 完成 ---"
            fi
        done
    fi

    # 报告备份错误
    if [ $backup_errors -gt 0 ]; then
        log "WARN" "备份过程中共发生 $backup_errors 个任务错误，请检查日志获取详细信息"
    fi

    # --- 后续处理 ---

    # 创建备份摘要
    create_backup_summary || log "WARN" "创建备份摘要失败"

    # 压缩备份 (如果启用且未压缩)
    if [ "${COMPRESS_BACKUP:-false}" == "true" ]; then
        compress_backup || log "WARN" "压缩备份失败"
    fi

    # 验证备份 (如果启用)
    if [ "${VERIFY_BACKUP:-false}" == "true" ]; then
        verify_backup || log "WARN" "验证备份失败，备份可能不完整或已损坏"
    fi

    # 清理旧备份
    cleanup_old_backups || log "WARN" "清理旧备份失败"

    # 清理恢复点文件 (无论成功失败都清理本次运行可能产生的)
    cleanup_recovery_points

    # 清理临时文件目录
    rm -rf "${BACKUP_ROOT}/tmp"

    # 重置陷阱
    trap - INT TERM EXIT

    # --- 最终状态 ---
    if [ $backup_errors -eq 0 ]; then
        log "INFO" "备份成功完成！"
        log "INFO" "备份位置: ${BACKUP_DIR}"
        [ "${COMPRESS_BACKUP:-false}" == "true" ] && log "INFO" "压缩文件: ${BACKUP_ROOT}/${DATE_FORMAT}_backup.tar${ext}" # ext 需要从 compress.sh 获取或重新判断
    else
        log "ERROR" "备份完成，但有 $backup_errors 个任务失败，请检查日志！"
    fi

    log "INFO" "日志文件: ${LOG_FILE}"
    return $backup_errors # 返回错误数量作为退出码
}

# --- 脚本执行入口 ---
# 将所有操作放入 main 函数，允许脚本被 source 而不立即执行
# 通过 "$@" 将命令行参数传递给 main 函数
main "$@"

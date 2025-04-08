#!/bin/bash

############################################################
# 备份系统配置脚本 (/etc)
# 功能：调用核心备份工作流来备份 /etc 目录。
#       从配置文件读取相关设置。
############################################################

# --- 脚本初始化 ---
# 获取脚本自身所在的目录
# SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
# # 获取项目根目录 (scripts/../)
# PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
# CORE_DIR="$PROJECT_ROOT/core"

# --- 主函数定义 ---
# 当被 source 时，调用者需要确保核心库已加载
backup_system_config() {
    # 注意：当作为库函数调用时，假定 load_config 已经被调用者执行
    # 因此日志系统应该已经初始化

    log_section "备份系统配置 (/etc)" $LOG_LEVEL_NOTICE

    # 检查备份开关
    if [[ "$BACKUP_SYSTEM_CONFIG" != "true" ]]; then
        log_notice "根据配置，跳过备份系统配置。"
        return 0 # 返回成功，因为是按配置跳过
    fi

    # 定义备份参数
    local src="/etc"
    # 目标目录是日期目录下的 'etc' 子目录
    local dest="${BACKUP_DIR}/etc" # 修改目标目录
    # 将空格分隔的排除项转换为逗号分隔
    local exclude_patterns
    exclude_patterns=$(echo "$EXCLUDE_SYSTEM_CONFIGS" | tr ' ' ',')

    # 调用核心工作流函数 (假设已被 source)
    # 检查 backup_workflow 函数是否存在，以提高稳健性
    if ! command -v backup_workflow > /dev/null 2>&1; then
        # 尝试 source backup_workflow.sh (作为后备，主要应由调用者处理)
        if [ -f "$CORE_DIR/backup_workflow.sh" ]; then
            log_warn "backup_workflow 函数未找到，尝试 source $CORE_DIR/backup_workflow.sh"
            . "$CORE_DIR/backup_workflow.sh"
            if ! command -v backup_workflow > /dev/null 2>&1; then
                 log_error "无法加载或找到 backup_workflow 函数，系统配置备份失败。"
                 return 1
            fi
        else
            log_error "backup_workflow 函数未找到，且无法找到 $CORE_DIR/backup_workflow.sh，系统配置备份失败。"
            return 1
        fi
    fi

    # --- 生成源校验和清单 ---
    # 清单文件直接存储在 BACKUP_DIR 下
    local manifest_file="${BACKUP_DIR}/system_etc.sha256"
    # 调用清单生成函数，传递源、清单路径和排除模式
    log_info "调用 generate_source_checksum_manifest \"$src\" \"$manifest_file\" \"$exclude_patterns\""
    if ! generate_source_checksum_manifest "$src" "$manifest_file" "$exclude_patterns"; then
        log_error "为源 $src 生成校验和清单失败 (已考虑排除项)，备份中止。"
        return 1
    fi

    log_info "调用 backup_workflow 函数: \"$src\" -> \"$dest\" (排除: \"$exclude_patterns\")"
    # 调用核心工作流（现在只有3个参数）
    if backup_workflow "$src" "$dest" "$exclude_patterns"; then
        log_info "系统配置备份 (rsync+stats) 成功完成。"
        # --- 在备份成功后立即进行校验和验证 ---
        # --- 调用封装好的校验函数 ---
        if ! verify_backup_checksum "$src" "$dest" "$manifest_file"; then
            # 校验失败
            # verify_backup_checksum 内部已记录详细错误
            return 1 # 校验失败，整个系统配置备份视为失败
        else
            # 校验成功或被跳过
            return 0 # 备份和校验（如果执行了）都成功
        fi
    else
        log_error "系统配置备份失败 (rsync 或 stats 步骤)。"
        return 1
    fi
}

# --- 直接执行块 ---
# 仅当脚本被直接执行时运行
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # --- 脚本初始化 (for direct execution) ---
    SCRIPT_DIR=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
    PROJECT_ROOT=$(dirname "$SCRIPT_DIR")
    CORE_DIR="$PROJECT_ROOT/core"
    file_check_dir="$PROJECT_ROOT/file-check" # 定义 file-check 目录

    # --- 加载核心库 (for direct execution) ---
    # 需要加载 backup_workflow 及其所有依赖项定义的函数
    _libs_loaded_sys_direct=true
    _core_libs=(
        "$CORE_DIR/config.sh"
        "$CORE_DIR/loggings.sh" # loggings 需要先加载
        "$CORE_DIR/load_config.sh" # load_config 会调用 init_logging
        "$CORE_DIR/check_dependencies.sh" # <--- 添加依赖检查脚本
        "$CORE_DIR/check_and_create_directory.sh" # rsync_backup 依赖
        "$CORE_DIR/calculate_size_and_count.sh" # check_backup_feasibility 依赖
        "$CORE_DIR/check_disk_space.sh"         # check_backup_feasibility 依赖
        "$CORE_DIR/check_backup_feasibility.sh"
        "$CORE_DIR/rsync_backup.sh"
        "$CORE_DIR/verify_backup_stats.sh"
        "$CORE_DIR/backup_workflow.sh" # 最后加载 workflow 本身
        "$file_check_dir/check_file_integrity.sh" # 包含 verify_checksum_manifest
        "$file_check_dir/verify_backup_checksum.sh" # 包含封装的校验函数 (已移动)
    )
    for lib in "${_core_libs[@]}"; do
        if [ -f "$lib" ]; then
            . "$lib" # 使用 . source 脚本
        else
            echo "错误：无法加载核心库 $lib" >&2
            _libs_loaded_sys_direct=false
        fi
    done

    if ! $_libs_loaded_sys_direct; then
        echo "错误：直接执行系统配置备份脚本时未能加载所有核心依赖库，无法继续。" >&2
        exit 1
    fi

    # --- 检查外部依赖 ---
    if ! check_dependencies; then
         exit 1 # check_dependencies 内部会记录错误
    fi

    # --- 加载配置并初始化日志 (for direct execution) ---
    # load_config 应该在上面 source 时被加载了
    # 调用它来确保配置被读取且日志被初始化
    if command -v load_config > /dev/null 2>&1; then
        load_config
    else
        echo "错误：load_config 函数未定义，无法初始化配置和日志。" >&2
        exit 1
    fi

    # --- 执行主函数 (for direct execution) ---
    backup_system_config
    exit $? # 退出脚本，使用函数的返回码
fi
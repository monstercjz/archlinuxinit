#!/bin/bash

#############################################################
# rsync 备份执行脚本
#
# 功能:
#   使用 rsync 命令执行实际的文件备份操作。
#   包含错误重试机制。
#   处理逗号分隔的排除模式列表。
#
# 适配性:
#   - 可直接执行: `./rsync_backup.sh <src> <dest> [exclude_patterns]`
#   - 可被 source: `source ./rsync_backup.sh` 后调用 `rsync_backup <src> <dest> [exclude_patterns]`
#     (调用方需确保 log 和 check_and_create_directory 函数可用)
#
# 参数:
#   $1 - 源路径 (文件或目录)
#   $2 - 目标路径 (目录)
#   $3 - 排除模式 (可选, 格式为逗号分隔的字符串, 如 "*.tmp,cache/*")
#
# 返回值:
#   0 - rsync 备份成功 (包括 rsync 退出码 24 的情况)
#   1 - 备份失败 (参数错误, 依赖缺失, 目录创建失败, rsync 多次重试后仍失败)
#
# 依赖项:
#   - 外部命令: rsync
#   - 核心脚本 (被 source 时需由调用方提供):
#     - core/loggings.sh (提供 log 函数)
#     - core/check_and_create_directory.sh (提供 check_and_create_directory 函数)
#
# 使用示例 (直接执行):
#   $ ./file-check/rsync_backup.sh /home/user/data /var/backups "*.log,*.bak"
#
# 使用示例 (被 source):
#   source ./core/loggings.sh
#   source ./core/check_and_create_directory.sh
#   source ./file-check/rsync_backup.sh
#   rsync_backup "/path/to/source" "/path/to/destination" "pattern1,pattern2"
#
#############################################################




# (删除此处的 SCRIPT_DIR, PARENT_DIR 定义和 source 逻辑)
# 依赖的 source 和初始化移至直接执行的 if 块中

# 主函数
rsync_backup() {
    local src="$1"
    local dest="$2"
    local exclude_patterns="$3"
    # 添加 -R 选项以保留相对路径
    local rsync_base_opts=("-aRh" "--delete" "--numeric-ids" "--stats")
    local rsync_exclude_opts_array=() # 使用数组存储排除选项
    local retry_count=3
    local retry_delay=5
    local success=false
    
    # 增量备份支持
    local link_dest_opt=()
    if [ "$DIFF_BACKUP" = "true" ] && [ -n "$LAST_BACKUP_DIR" ] && [ -d "$LAST_BACKUP_DIR" ]; then
        link_dest_opt=("--link-dest=$LAST_BACKUP_DIR")
        log "INFO" "启用增量备份，参考目录: $LAST_BACKUP_DIR"
    fi
    
    # 检查外部命令依赖
    if ! command -v rsync > /dev/null 2>&1; then
        log "ERROR" "命令 'rsync' 未找到，请安装它 (例如: sudo pacman -S rsync)"
        return 1
    fi

    # 检查参数
    if [ -z "$src" ]; then
        log "ERROR" "未提供源路径"
        return 1
    fi
    
    if [ -z "$dest" ]; then
        log "ERROR" "未提供目标路径"
        return 1
    fi
    
    # 检查源路径是否存在
    if [ ! -e "$src" ]; then
        log "ERROR" "源路径不存在: $src"
        return 1
    fi
    
    # 确保目标目录存在
    # 确保目标目录存在，并引用参数
    if ! check_and_create_directory "$dest"; then
        log "ERROR" "无法访问或创建目标目录: $dest"
        return 1
    fi
    
    # 处理排除模式
    if [ -n "$exclude_patterns" ]; then
        IFS=',' read -ra EXCLUDE_ARRAY <<< "$exclude_patterns"
        for pattern in "${EXCLUDE_ARRAY[@]}"; do
            # 将每个排除选项添加到数组中
            rsync_exclude_opts_array+=(--exclude="$pattern")
        done
        log "INFO" "排除模式: $exclude_patterns"
    fi
    
    # 记录开始备份的信息
    log "INFO" "开始备份: $src -> $dest"
    
    # 执行rsync备份，带重试机制
    for ((i=1; i<=retry_count; i++)); do
        log "INFO" "执行rsync备份 (尝试 $i/$retry_count)"
        
        # 构建参数数组
        # local rsync_args=("${rsync_base_opts[@]}" "${rsync_exclude_opts_array[@]}" "$src" "$dest")
        local rsync_args=("${rsync_base_opts[@]}" "${link_dest_opt[@]}" "${rsync_exclude_opts_array[@]}" "$src" "$dest")
        
        # 直接执行rsync命令，避免使用eval
        log "DEBUG" "执行命令: rsync ${rsync_args[*]}" # 可选的调试日志
        rsync "${rsync_args[@]}"
        local rsync_exit_code=$?
        
        # 检查rsync退出码
        # 0 = 成功，24 = 文件列表中的某些文件在传输过程中消失了（通常是正常的）
        if [ $rsync_exit_code -eq 0 ] || [ $rsync_exit_code -eq 24 ]; then
            success=true
            break
        else
            log "WARN" "rsync备份失败，退出码: $rsync_exit_code"
            if [ $i -lt $retry_count ]; then
                log "INFO" "将在 $retry_delay 秒后重试..."
                sleep $retry_delay
            fi
        fi
    done
    
    # 检查备份是否成功
    if [ "$success" = true ]; then
        log "INFO" "rsync备份成功完成"
        return 0
    else
        log "ERROR" "rsync备份失败，已达到最大重试次数"
        return 1
    fi
}

# 如果直接运行此脚本（非被其他脚本source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # --- 直接执行时的设置 ---
    # 获取脚本所在目录
    
    parent_dir="$(dirname "${BASH_SOURCE[0]}")/.."

    # 加载配置和日志脚本
    config_script="$parent_dir/core/config.sh"
    load_config_script="$parent_dir/core/load_config.sh"
    logging_script="$parent_dir/core/loggings.sh" # load_config 依赖 loggings
    check_dir_script="$parent_dir/core/check_and_create_directory.sh" # rsync_backup 依赖

    _libs_loaded_rsync=true
    # 先加载日志和目录检查，因为 load_config 会调用 init_logging
    if [ -f "$logging_script" ]; then . "$logging_script"; else echo "错误：无法加载 $logging_script" >&2; _libs_loaded_rsync=false; fi
    if [ -f "$check_dir_script" ]; then . "$check_dir_script"; else echo "错误：无法加载 $check_dir_script" >&2; _libs_loaded_rsync=false; fi
    if [ -f "$config_script" ]; then . "$config_script"; else echo "错误：无法加载 $config_script" >&2; _libs_loaded_rsync=false; fi
    if [ -f "$load_config_script" ]; then . "$load_config_script"; else echo "错误：无法加载 $load_config_script" >&2; _libs_loaded_rsync=false; fi

    if ! $_libs_loaded_rsync; then
        exit 1 # 依赖加载失败
    fi

    # 加载配置文件并初始化日志
    load_config
    # init_logging 会在 load_config 内部被调用，无需再次调用
    
    # 执行主函数
    # 执行主函数，确保参数被正确引用
    rsync_backup "$1" "$2" "$3"
    exit $?
fi
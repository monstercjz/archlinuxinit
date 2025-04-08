#!/bin/bash

#############################################################
# 增量备份实现脚本
#
# 功能:
#   实现真正的增量备份功能，只备份自上次备份以来变化的文件
#   与差异备份不同，增量备份基于最近一次备份（无论是完整备份还是增量备份）
#   使用rsync的--link-dest选项实现硬链接机制，节省存储空间
#
# 参数:
#   $1 - 源路径 (文件或目录)
#   $2 - 目标路径 (目录)
#   $3 - 排除模式 (可选, 格式为逗号分隔的字符串)
#
# 返回值:
#   0 - 增量备份成功
#   1 - 增量备份失败
#
# 依赖项:
#   - 外部命令: rsync, find, date
#   - 核心脚本:
#     - core/loggings.sh (提供 log 函数)
#     - core/check_and_create_directory.sh
#     - file-check/find_last_backup.sh
#
# 使用示例:
#   $ incremental_backup "/home/user" "/var/backups/home" "*.tmp,*.log"
#
#############################################################

# 增量备份主函数
incremental_backup() {
    local src="$1"
    local dest="$2"
    local exclude_patterns="$3"
    local rsync_base_opts=("-aRh" "--delete" "--numeric-ids" "--stats")
    local rsync_exclude_opts_array=() # 使用数组存储排除选项
    local retry_count=3
    local retry_delay=5
    local success=false
    local incremental_dir=""
    
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
    if ! check_and_create_directory "$dest"; then
        log "ERROR" "无法访问或创建目标目录: $dest"
        return 1
    fi
    
    # 处理排除模式
    if [ -n "$exclude_patterns" ]; then
        IFS=',' read -ra EXCLUDE_ARRAY <<< "$exclude_patterns"
        for pattern in "${EXCLUDE_ARRAY[@]}"; do
            rsync_exclude_opts_array+=(--exclude="$pattern")
        done
        log "INFO" "排除模式: $exclude_patterns"
    fi
    
    # 查找最近的备份目录作为增量基础
    log "INFO" "查找最近的备份目录作为增量基础..."
    
    # 获取所有备份目录并按日期排序（最新的在最后）
    local all_backups=($(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" | sort))
    local backup_count=${#all_backups[@]}
    
    if [ $backup_count -gt 0 ]; then
        # 获取最新的备份目录
        incremental_dir="${all_backups[$((backup_count-1))]}"
        log "INFO" "找到最近的备份目录作为增量基础: $incremental_dir"
        
        # 添加--link-dest选项，指向最近的备份目录
        rsync_base_opts+=("--link-dest=$incremental_dir")
        log "INFO" "启用增量备份，基于目录: $incremental_dir"
    else
        log "INFO" "没有找到以前的备份，将进行完整备份"
    fi
    
    # 记录开始备份的信息
    log "INFO" "开始增量备份: $src -> $dest"
    
    # 执行rsync备份，带重试机制
    for ((i=1; i<=retry_count; i++)); do
        log "INFO" "执行增量备份 (尝试 $i/$retry_count)"
        
        # 构建参数数组
        local rsync_args=("${rsync_base_opts[@]}" "${rsync_exclude_opts_array[@]}" "$src" "$dest")
        
        # 直接执行rsync命令
        log "DEBUG" "执行命令: rsync ${rsync_args[*]}"
        rsync "${rsync_args[@]}"
        local rsync_exit_code=$?
        
        # 检查rsync退出码
        if [ $rsync_exit_code -eq 0 ] || [ $rsync_exit_code -eq 24 ]; then
            success=true
            break
        else
            log "WARN" "增量备份失败，退出码: $rsync_exit_code"
            if [ $i -lt $retry_count ]; then
                log "INFO" "将在 $retry_delay 秒后重试..."
                sleep $retry_delay
            fi
        fi
    done
    
    # 检查备份是否成功
    if [ "$success" = true ]; then
        log "INFO" "增量备份成功完成"
        return 0
    else
        log "ERROR" "增量备份失败，已达到最大重试次数"
        return 1
    fi
}

# 如果直接运行此脚本（非被其他脚本source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 获取脚本所在目录
    parent_dir="$(dirname "${BASH_SOURCE[0]}")/.."

    # 加载配置和日志脚本
    config_script="$parent_dir/core/config.sh"
    load_config_script="$parent_dir/core/load_config.sh"
    logging_script="$parent_dir/core/loggings.sh"
    check_dir_script="$parent_dir/core/check_and_create_directory.sh"

    _libs_loaded_incremental=true
    # 加载依赖脚本
    if [ -f "$logging_script" ]; then . "$logging_script"; else echo "错误：无法加载 $logging_script" >&2; _libs_loaded_incremental=false; fi
    if [ -f "$check_dir_script" ]; then . "$check_dir_script"; else echo "错误：无法加载 $check_dir_script" >&2; _libs_loaded_incremental=false; fi
    if [ -f "$config_script" ]; then . "$config_script"; else echo "错误：无法加载 $config_script" >&2; _libs_loaded_incremental=false; fi
    if [ -f "$load_config_script" ]; then . "$load_config_script"; else echo "错误：无法加载 $load_config_script" >&2; _libs_loaded_incremental=false; fi

    if ! $_libs_loaded_incremental; then
        exit 1 # 依赖加载失败
    fi

    # 加载配置文件并初始化日志
    load_config
    
    # 执行主函数
    incremental_backup "$1" "$2" "$3"
    exit $?
fi
#!/bin/bash

#############################################################
# 获取磁盘可用空间
# 功能：获取指定目录所在文件系统的可用空间
# 参数：
#   $1 - 目标目录路径
# 返回值：
#   0 - 成功获取空间信息
#   1 - 获取失败（如目录不存在或无法访问）
# 输出：
#   标准输出 - 磁盘空间信息，格式为KEY=VALUE，包含以下内容：
#     AVAILABLE_SPACE=<可用字节数> - 目标目录所在文件系统的可用空间（以字节为单位）
#     HUMAN_AVAILABLE=<可读大小> - 人类可读格式的可用空间（如1.2GiB）
#
# 使用示例：
#   $ ./check_disk_space.sh /path/to/directory
#   AVAILABLE_SPACE=10240000
#   HUMAN_AVAILABLE=9.8MiB
#
# 最佳实践：
#   - 在调用此脚本时，应捕获其返回值和标准输出
#   - 使用grep和cut命令解析输出结果，例如：
#     available=$(echo "$output" | grep "AVAILABLE_SPACE=" | cut -d'=' -f2)
#
# 依赖项：
#   - 外部命令：
#     - df: 用于获取文件系统可用空间 (-B1 以字节为单位, --output=avail 只输出可用空间)
#     - numfmt: 用于转换大小为人类可读格式 (--to=iec-i 使用二进制前缀)
#   - 内部函数：
#     - log: 来自core/loggings.sh，用于记录不同级别的日志信息
#       格式: log "级别" "消息"，级别可以是INFO、ERROR等
#     - init_logging: 来自core/loggings.sh，用于初始化日志系统
#       在脚本直接执行时会调用此函数
#############################################################

# 主函数
check_disk_space() {
    local target_dir="$1"
    
    # 检查参数
    if [ -z "$target_dir" ]; then
        log "ERROR" "未提供目标目录路径"
        return 1
    fi
    
    # 检查目录是否存在
    if [ ! -e "$target_dir" ]; then
        log "ERROR" "目标目录不存在: $target_dir"
        return 1
    fi
    
    # 获取目标目录所在文件系统的可用空间
    local available_space=$(df -B1 --output=avail "$target_dir" | tail -n 1)
    
    # 转换为人类可读格式
    local human_available=$(numfmt --to=iec-i --suffix=B "$available_space")
    
    log "INFO" "检查磁盘空间: $target_dir"
    log "INFO" "可用空间: $human_available ($available_space 字节)"
    
    # 输出结果（可以被其他脚本捕获）
    echo "AVAILABLE_SPACE=$available_space"
    echo "HUMAN_AVAILABLE=$human_available"
    
    return 0
}

# 如果直接运行此脚本（非被其他脚本source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # --- 直接执行时的设置 ---
    # 获取脚本所在目录 (使用简化方式)
    script_dir=$(dirname "$0")
    parent_dir=$(dirname "$script_dir")

    # 加载配置和日志脚本
    config_script="$parent_dir/core/config.sh"
    load_config_script="$parent_dir/core/load_config.sh"
    logging_script="$parent_dir/core/loggings.sh" # load_config 依赖 loggings

    _libs_loaded_disk=true
    # 先加载日志，因为 load_config 会调用 init_logging
    if [ -f "$logging_script" ]; then . "$logging_script"; else echo "错误：无法加载 $logging_script" >&2; _libs_loaded_disk=false; fi
    if [ -f "$config_script" ]; then . "$config_script"; else echo "错误：无法加载 $config_script" >&2; _libs_loaded_disk=false; fi
    if [ -f "$load_config_script" ]; then . "$load_config_script"; else echo "错误：无法加载 $load_config_script" >&2; _libs_loaded_disk=false; fi

    if ! $_libs_loaded_disk; then
        exit 1 # 依赖加载失败
    fi

    # 加载配置文件并初始化日志
    load_config
    # init_logging 会在 load_config 内部被调用，无需再次调用
    # 执行主函数
    check_disk_space "$1"
    exit $?
fi
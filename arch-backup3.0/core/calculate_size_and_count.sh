#!/bin/bash

#############################################################
# 计算备份项目的大小和数量
# 功能：计算指定备份项目的大小和文件数量
# 参数：
#   $1 - 备份项目路径（可以是文件或目录）
# 返回值：
#   0 - 成功，表示脚本执行完成并成功计算了大小和数量
#   1 - 失败，表示脚本执行过程中遇到错误（如路径不存在或参数缺失）
# 输出：
#   标准输出 - 项目大小和文件数量信息，格式为KEY=VALUE，包含以下内容：
#     SIZE=<总字节数> - 备份项目的总大小（以字节为单位的整数）
#     COUNT=<文件数量> - 备份项目包含的文件总数
#     HUMAN_SIZE=<可读大小> - 人类可读格式的大小（如1.2GiB）
# 使用示例：
#   $ ./calculate_size_and_count.sh /path/to/backup
#   SIZE=1024000
#   COUNT=42
#   HUMAN_SIZE=1.0MiB
#
# 最佳实践：
#   - 在调用此脚本时，应捕获其返回值和标准输出
#   - 使用grep和cut命令解析输出结果，例如：
#     size=$(echo "$output" | grep "SIZE=" | cut -d'=' -f2)
#
# 依赖项：
#   - 外部命令：
#     - du: 用于计算目录大小 (-s 汇总, -b 以字节为单位)
#     - find: 用于查找并计数文件 (与 wc -l 配合使用)
#     - stat: 用于获取单个文件大小 (-c %s 格式指定符返回字节大小)
#     - numfmt: 用于转换大小为人类可读格式 (--to=iec-i 使用二进制前缀)
#     - wc: 用于计数行数 (-l 选项)
#     - awk: 用于提取du命令输出中的大小值
#   - 内部函数：
#     - log: 来自core/loggings.sh，用于记录不同级别的日志信息
#       格式: log "级别" "消息"，级别可以是INFO、ERROR等
#     - init_logging: 来自core/loggings.sh，用于初始化日志系统
#       在脚本直接执行时会调用此函数
#
# 调用示例 (从backup_workflow.sh中提取)：
#   local size_count_output=$("$SCRIPT_DIR"/calculate_size_and_count.sh "$src")
#   local required_space=$(echo "$size_count_output" | grep "SIZE=" | cut -d'=' -f2)
#   local file_count=$(echo "$size_count_output" | grep "COUNT=" | cut -d'=' -f2)
#   local human_size=$(echo "$size_count_output" | grep "HUMAN_SIZE=" | cut -d'=' -f2)
#############################################################

# 主函数定义
# 注意：此函数依赖于core目录中的工具脚本，特别是loggings.sh中的log函数

# 主函数
calculate_size_and_count() {
    local item_path="$1"
    local total_size=0
    local total_count=0
    
    # 检查参数
    if [ -z "$item_path" ]; then
        log "ERROR" "未提供备份项目路径"
        # 返回错误码1，表示参数缺失错误
        return 1
    fi
    
    # 检查路径是否存在
    if [ ! -e "$item_path" ]; then
        log "ERROR" "备份项目路径不存在: $item_path"
        # 返回错误码1，表示路径不存在错误
        return 1
    fi
    
    log "INFO" "开始计算备份项目大小和数量: $item_path"
    
    # 计算大小和数量
    if [ -d "$item_path" ]; then
        # 如果是目录，使用du命令计算总大小（-s表示汇总，-b表示以字节为单位）
        total_size=$(du -sb "$item_path" | awk '{print $1}')
        # 计算文件数量（使用find命令查找所有文件并计数）
        total_count=$(find "$item_path" -type f | wc -l)
    else
        # 如果是文件，使用stat命令获取文件大小（%s格式指定符返回字节大小）
        total_size=$(stat -c %s "$item_path")
        # 单个文件的数量为1
        total_count=1
    fi
    
    # 转换大小为人类可读格式（使用numfmt工具，--to=iec-i表示使用二进制前缀，如KiB、MiB等）
    local human_size=$(numfmt --to=iec-i --suffix=B "$total_size")
    
    # 记录计算结果到日志
    log "INFO" "备份项目: $item_path"
    log "INFO" "总大小: $human_size ($total_size 字节)"
    log "INFO" "文件数量: $total_count"
    
    # 输出结果（可以被其他脚本捕获）
    # 这些输出遵循KEY=VALUE格式，便于其他脚本使用grep和cut命令解析
    # SIZE - 备份项目的总大小（以字节为单位）
    echo "SIZE=$total_size"
    # COUNT - 备份项目包含的文件总数
    echo "COUNT=$total_count"
    # HUMAN_SIZE - 人类可读格式的大小（如1.2GiB）
    echo "HUMAN_SIZE=$human_size"
    
    # 返回成功状态码0，表示脚本执行成功
    return 0
}

# 如果直接运行此脚本（非被其他脚本source）
# 通过比较BASH_SOURCE[0]（当前脚本的路径）和$0（正在执行的脚本路径）来判断
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 获取脚本所在目录
    
    PARENT_DIR="$(dirname "${BASH_SOURCE[0]}")/.."
    
    # 加载配置和日志脚本
    config_script="$PARENT_DIR/core/config.sh"
    load_config_script="$PARENT_DIR/core/load_config.sh"
    logging_script="$PARENT_DIR/core/loggings.sh" # load_config 依赖 loggings

    _libs_loaded_calc=true
    # 先加载日志，因为 load_config 会调用 init_logging
    if [ -f "$logging_script" ]; then . "$logging_script"; else echo "错误：无法加载 $logging_script" >&2; _libs_loaded_calc=false; fi
    if [ -f "$config_script" ]; then . "$config_script"; else echo "错误：无法加载 $config_script" >&2; _libs_loaded_calc=false; fi
    if [ -f "$load_config_script" ]; then . "$load_config_script"; else echo "错误：无法加载 $load_config_script" >&2; _libs_loaded_calc=false; fi

    if ! $_libs_loaded_calc; then
        exit 1 # 依赖加载失败
    fi
    
    #  加载必要的工具脚本
    # for util_script in "$PARENT_DIR"/core/*.sh; do
    #     if [ -f "$util_script" ]; then
    #         source "$util_script"
    #     fi
    # done

    # 加载配置文件并初始化日志
    load_config
    # init_logging 会在 load_config 内部被调用，无需再次调用
    
    # 执行主函数，传入第一个命令行参数作为备份项目路径
    calculate_size_and_count "$1"
    # 使用$?获取主函数的返回值并作为脚本的退出状态码
    # 这确保了脚本的退出状态与函数的返回值一致
    exit $?
fi
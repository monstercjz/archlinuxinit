#!/bin/bash

#############################################################
# 备份可行性检查脚本
#
# 功能:
#   检查执行备份所需的前提条件是否满足：
#   1. 计算源文件/目录的大小和文件数量。
#   2. 检查目标目录所在文件系统的可用空间。
#   3. 比较所需空间（含安全系数）与可用空间。
#
# 适配性:
#   - 可直接执行: `./check_backup_feasibility.sh <src> <dest>`
#   - 可被 source: `source ./check_backup_feasibility.sh` 后调用 `check_backup_feasibility <src> <dest>`
#     (调用方需确保 log, calculate_size_and_count.sh, check_disk_space.sh 函数/脚本可用)
#
# 参数:
#   $1 - 源路径 (文件或目录)
#   $2 - 目标路径 (目录, 用于检查其所在文件系统的空间)
#   $3 - 排除模式 (可选, 逗号分隔, 如 "*.log,cache/*")
#
# 返回值 (Exit Code):
#   0 - 检查通过，备份可行
#   1 - 参数错误或依赖缺失
#   2 - 计算源大小或数量失败
#   3 - 检查目标磁盘空间失败
#   4 - 目标磁盘空间不足
# 标准输出 (仅当返回值为 0 时):
#   NET_SIZE=<净字节数>
#   NET_COUNT=<净文件数>
#
# 依赖项:
#   - 外部命令: bc, awk, numfmt
#   - 核心脚本 (被 source 时需由调用方提供, 直接执行时会自动加载):
#     - core/loggings.sh (提供 log 函数)
#     - core/calculate_size_and_count.sh (用于计算源大小)
#     - core/check_disk_space.sh (用于检查目标空间)
#
# 使用示例 (直接执行):
#   $ ./core/check_backup_feasibility.sh /home/user/data /var/backups "*.tmp,vendor/*"
#
# 使用示例 (被 source):
#   source ./core/loggings.sh
#   source ./core/calculate_size_and_count.sh # 如果它是脚本而非函数
#   source ./core/check_disk_space.sh     # 如果它是脚本而非函数
#   source ./core/check_backup_feasibility.sh
#   if check_backup_feasibility "/path/to/source" "/path/to/destination"; then
#       echo "备份可行"
#   else
#       echo "备份不可行，退出码: $?"
#   fi
#
#############################################################

# --- 辅助函数 ---

# [备份方法] 使用 find | du 计算排除项大小 (效率较高，保留作为参考)
_calculate_excluded_size_find_du() {
    local src="$1"
    local exclude_patterns="$2"
    local excluded_size=0

    log "DEBUG" "(find_du 方法) 计算排除项 '$exclude_patterns' 的大小..."
    local find_exclude_args=()
    IFS=',' read -ra EXCLUDE_ARRAY <<< "$exclude_patterns"
    local first_pattern=true
    for pattern in "${EXCLUDE_ARRAY[@]}"; do
        pattern=$(echo "$pattern" | xargs) # 去除前后空格
        if [ -n "$pattern" ]; then
            # 构建 find 命令参数。要完美处理所有情况比较复杂。
            # 对相对路径使用 -path，对简单通配符使用 -name。
            # 这可能需要根据预期的模式类型进行调整。
            # 我们想要查找源路径下匹配模式的项目。
            if [[ "$pattern" == *"/"* ]]; then
                # 模式看起来像路径 (例如 cache/*, dir/file.log)
                # 需要加上源路径前缀, 处理 src 可能存在的尾部斜杠
                local search_path="${src%/}/$pattern"
                if $first_pattern; then
                    find_exclude_args+=(-path "$search_path")
                    first_pattern=false
                else
                    find_exclude_args+=(-o -path "$search_path")
                fi
            else
                # 模式看起来像文件名 (例如 *.log, temp?)
                if $first_pattern; then
                     find_exclude_args+=(-name "$pattern")
                     first_pattern=false
                else
                     find_exclude_args+=(-o -name "$pattern")
                fi
            fi
        fi
    done

    if [ ${#find_exclude_args[@]} -gt 0 ]; then
        # 查找匹配排除模式的项目并使用 du 计算它们的大小总和
        # 使用 find ... -print0 | du --files0-from=- -cbs
        # -c 输出总计, -b 字节单位, -s 汇总 (重要!)
        local excluded_output
        excluded_output=$(find "$src" \( "${find_exclude_args[@]}" \) -print0 2>/dev/null | du --files0-from=- -cbs 2>/dev/null)
        local du_exit_code=$?

        if [ $du_exit_code -eq 0 ] && [ -n "$excluded_output" ]; then
            # 从 du -c 输出中获取总计行
            excluded_size=$(echo "$excluded_output" | grep -E '\stotal$' | awk '{print $1}')
            if [ -z "$excluded_size" ]; then
                excluded_size=0 # 处理 grep/awk 失败的情况
                log "WARN" "(find_du 方法) 无法从 du 输出解析排除项总大小，假设为 0。"
                log "DEBUG" "(find_du 方法) du 输出: $excluded_output"
            fi
        else
            log "WARN" "(find_du 方法) 计算排除项大小时出错 (find/du 退出码: $du_exit_code)，将假设排除大小为 0。"
            excluded_size=0
        fi
    else
         log "INFO" "(find_du 方法) 未找到有效的排除模式来计算大小。"
         excluded_size=0
    fi
    echo "$excluded_size" # 输出结果
}

# [当前使用方法] 通过循环调用 calculate_size_and_count.sh 计算排除项大小
# [当前使用方法] 通过循环调用 calculate_size_and_count.sh 计算排除项大小和数量
# 返回: echo "<excluded_size> <excluded_count>"
_calculate_excluded_size_loop() {
    local src="$1"
    local exclude_patterns="$2"
    local size_count_script_path="$3" # 需要传入 calculate_size_and_count.sh 的路径
    local total_excluded_size=0
    local total_excluded_count=0 # 新增：计算排除的数量

    log "INFO" "可行性检查：(循环方法) 计算排除项 '$exclude_patterns' 的大小..." >&2

    # 检查依赖函数是否存在 (假设已 source)
    if ! command -v calculate_size_and_count > /dev/null 2>&1; then
         log "ERROR" "(循环方法) 依赖函数 'calculate_size_and_count' 不可用" >&2
         echo "0 0" # 返回大小和数量
         return 1 # 指示内部错误
    fi

    local find_exclude_args=()
    local abs_source_path
    abs_source_path=$(readlink -f "$src") # Get absolute path of src

    IFS=',' read -ra EXCLUDE_ARRAY <<< "$exclude_patterns"
    for pattern_orig in "${EXCLUDE_ARRAY[@]}"; do
        local pattern find_arg find_val
        pattern=$(echo "$pattern_orig" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

        if [ -z "$pattern" ]; then
            continue
        fi

        if [[ "$pattern" == /* ]]; then
            # Absolute path pattern: Use it directly with -path
            find_arg="-path"
            find_val="$pattern"
            # find will naturally only find paths under $src that match this absolute path
        else
            # Relative path or wildcard pattern
            if [[ "$pattern" == *"/"* ]]; then
                # Relative path: Prepend the absolute src path for -path matching
                find_arg="-path"
                # Ensure no double slashes if abs_source_path ends with /
                find_val="${abs_source_path%/}/$pattern"
            else
                # Basename or wildcard: Use -name
                find_arg="-name"
                find_val="$pattern"
            fi
        fi

        # Add -o if not the first condition
        if [ ${#find_exclude_args[@]} -gt 0 ]; then
            find_exclude_args+=("-o")
        fi
        find_exclude_args+=("$find_arg" "$find_val")
        log "DEBUG" "(循环方法) 添加排除查找条件: $find_arg \"$find_val\" (来自 '$pattern_orig')" >&2
    done

    if [ ${#find_exclude_args[@]} -eq 0 ]; then
        log "INFO" "(循环方法) 未找到有效的排除模式。" >&2
        echo "0 0" # 返回大小和数量
        return 0
    fi

    # 执行 find 查找匹配排除模式的文件和目录
    # 使用 -print0 和 read -d $'\0' 安全处理各种文件名
    local total_items_found=0 # 重命名外部计数器
    local error_count=0
    # 使用进程替换 < <(find ...) 避免子 shell 问题，并移除 2>/dev/null 观察 find 错误
    while IFS= read -r -d $'\0' item; do
        ((total_items_found++)) # 增加外部计数器
        log "DEBUG" "(循环方法) 计算排除项 '$item' 的大小..." >&2
        local item_output
        item_output=$(calculate_size_and_count "$item") # 直接调用函数
        local item_exit_code=$?

        if [ $item_exit_code -eq 0 ]; then
            local item_size=$(echo "$item_output" | awk -F= '/^SIZE=/ {print $2}')
            local item_count=$(echo "$item_output" | awk -F= '/^COUNT=/ {print $2}') # 获取数量
            if [[ "$item_size" =~ ^[0-9]+$ && "$item_count" =~ ^[0-9]+$ ]]; then
                total_excluded_size=$((total_excluded_size + item_size))
                total_excluded_count=$((total_excluded_count + item_count)) # 累加数量
            else
                log "WARN" "(循环方法) 无法从 '$item' 的计算脚本输出中解析大小或数量: $item_output" >&2
                ((error_count++))
            fi
        else
            log "WARN" "(循环方法) 计算 '$item' 大小时出错，脚本退出码: $item_exit_code" >&2
            ((error_count++))
        fi
    # Note: find starts searching from $src. The patterns in find_exclude_args are constructed accordingly.
    done < <(find "$src" \( "${find_exclude_args[@]}" \) -print0)

    if [ $error_count -gt 0 ]; then
         log "WARN" "(循环方法) 计算排除项大小时遇到 $error_count 个错误。" >&2
    fi
     log "INFO" "(循环方法) 共找到 $total_items_found 个排除项，累加计算大小和数量。" >&2

    echo "$total_excluded_size $total_excluded_count" # 输出最终累加的大小和数量
    return 0 # 指示计算完成（可能有部分错误）
}


# --- 主检查函数 ---
check_backup_feasibility() {
    local src="$1"
    local dest="$2"
    local exclude_patterns="$3"
    local safety_factor=1.1 # 安全系数，预留10%额外空间

    # 获取此脚本文件所在的目录，确保无论如何调用都能找到依赖脚本
    local current_script_dir
    current_script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
    # 注意：如果此脚本被 source，依赖脚本需要由调用方确保路径正确或已加载

    # 检查参数
    if [ -z "$src" ]; then
        log "ERROR" "可行性检查：未提供源路径"
        return 1
    fi
    if [ -z "$dest" ]; then
        log "ERROR" "可行性检查：未提供目标路径"
        return 1
    fi
    if [ ! -e "$src" ]; then
        log "ERROR" "可行性检查：源路径不存在: $src"
        return 1
    fi
    if ! check_and_create_directory "$dest"; then
        log "ERROR" "无法访问或创建目标目录: $dest"
        return 1
    fi
    # 检查外部命令依赖
    if ! command -v bc > /dev/null 2>&1; then
        log "ERROR" "可行性检查：命令 'bc' 未找到，请安装它"
        return 1
    fi
     if ! command -v awk > /dev/null 2>&1; then
        log "ERROR" "可行性检查：命令 'awk' 未找到，请安装它"
        return 1
    fi
    if ! command -v numfmt > /dev/null 2>&1; then
        log "ERROR" "可行性检查：命令 'numfmt' 未找到，请安装它 (通常在 coreutils 包中)"
        return 1
    fi

    # 步骤1：检查备份项目的大小数量
    log "INFO" "可行性检查：计算源大小和数量: $src"
    # 检查依赖函数是否存在 (假设已 source)
    if ! command -v calculate_size_and_count > /dev/null 2>&1; then
         log "ERROR" "可行性检查：依赖函数 'calculate_size_and_count' 不可用"
         return 1
    fi
    local size_count_output
    # 直接调用函数，捕获其输出
    size_count_output=$(calculate_size_and_count "$src")
    local calc_exit_code=$?

    if [ $calc_exit_code -ne 0 ]; then
        log "ERROR" "可行性检查：执行 '$size_count_script $src' 失败，退出码: $calc_exit_code"
        return 2
    fi

    local required_space=$(echo "$size_count_output" | awk -F= '/^SIZE=/ {print $2}')
    local file_count=$(echo "$size_count_output" | awk -F= '/^COUNT=/ {print $2}')
    local human_size=$(echo "$size_count_output" | awk -F= '/^HUMAN_SIZE=/ {print $2}')

    if [ -z "$required_space" ] || [ -z "$file_count" ]; then
        log "ERROR" "可行性检查：无法从脚本输出解析备份项目的大小和数量"
        log "DEBUG" "脚本 '$size_count_script' 的输出: $size_count_output"
        return 2
    fi
    log "INFO" "可行性检查：源项目总大小 (未排除): $human_size ($required_space 字节), 文件数: $file_count"

    # 步骤 1.5: 如果有排除模式，计算排除项的大小
    local excluded_size=0
    if [ -n "$exclude_patterns" ]; then
        # 调用新的循环方法来计算排除大小
        # (不再需要传递脚本路径，因为是直接调用函数)
        local excluded_stats excluded_count
        excluded_stats=$(_calculate_excluded_size_loop "$src" "$exclude_patterns") # 调用循环方法
        # 解析返回的大小和数量
        read -r excluded_size excluded_count <<< "$excluded_stats"
        # 可以在这里检查 _calculate_excluded_size_loop 的退出码，但它内部已记录警告
        local human_excluded=$(numfmt --to=iec-i --suffix=B "$excluded_size")
        log "INFO" "可行性检查：(循环方法) 估算的排除项总大小: $human_excluded ($excluded_size 字节), 数量: $excluded_count"

        # 保留旧方法的调用（注释掉），用于调试或未来切换回
        # local excluded_size_find_du=$(_calculate_excluded_size_find_du "$src" "$exclude_patterns")
        # log "DEBUG" "(find_du 方法) 估算的排除项总大小: $(numfmt --to=iec-i --suffix=B "$excluded_size_find_du") ($excluded_size_find_du 字节)"
    fi

    # 计算净需求空间
    local net_required_space=$((required_space - excluded_size))
    # 确保净大小不为负 (以防排除大小计算异常)
    if [ "$net_required_space" -lt 0 ]; then
        net_required_space=0
    fi
    local human_net_required=$(numfmt --to=iec-i --suffix=B "$net_required_space")
    # 计算净文件数
    local net_file_count=$((file_count - excluded_count))
    if [ "$net_file_count" -lt 0 ]; then
        net_file_count=0
    fi
    log "INFO" "可行性检查：预计净备份大小 (总大小 - 排除项): $human_net_required ($net_required_space 字节), 净文件数: $net_file_count"

    # 步骤2：检查目标目录所在空间剩余
    log "INFO" "可行性检查：检查目标磁盘空间: $dest"
    # 检查依赖函数是否存在 (假设已 source)
    if ! command -v check_disk_space > /dev/null 2>&1; then
         log "ERROR" "可行性检查：依赖函数 'check_disk_space' 不可用"
         return 1
    fi
    local disk_space_output
    # 直接调用函数，捕获其输出
    disk_space_output=$(check_disk_space "$dest")
    local disk_exit_code=$?

     if [ $disk_exit_code -ne 0 ]; then
        log "ERROR" "可行性检查：执行 '$disk_space_script $dest' 失败，退出码: $disk_exit_code"
        return 3
    fi

    local available_space=$(echo "$disk_space_output" | awk -F= '/^AVAILABLE_SPACE=/ {print $2}')
    local human_available=$(echo "$disk_space_output" | awk -F= '/^HUMAN_AVAILABLE=/ {print $2}')

    if [ -z "$available_space" ]; then
        log "ERROR" "可行性检查：无法从脚本输出解析磁盘可用空间"
        log "DEBUG" "脚本 '$disk_space_script' 的输出: $disk_space_output"
        return 3
    fi
    log "INFO" "可行性检查：目标可用空间: $human_available ($available_space 字节)"

    # 步骤3：比较备份项目和目标剩余大小
    # 对净需求空间应用安全系数
    local actual_required_space=$(echo "$net_required_space * $safety_factor" | bc | awk '{printf "%.0f\n", $0}')
    local human_required=$(numfmt --to=iec-i --suffix=B "$actual_required_space")

    log "INFO" "可行性检查：所需空间 (净大小 x ${safety_factor} 安全系数): $human_required ($actual_required_space 字节)"

    # 比较可用空间和所需空间 (使用 bc 进行比较以处理大数字)
    local comparison
    comparison=$(echo "$available_space >= $actual_required_space" | bc)

    if [ "$comparison" -ne 1 ]; then
        log "ERROR" "可行性检查：磁盘空间不足！需要 $human_required，但只有 $human_available 可用。"
        return 4
    fi

    log "INFO" "可行性检查：磁盘空间充足。"
    # 检查通过，输出净大小和净数量到 stdout
    echo "NET_SIZE=$net_required_space"
    echo "NET_COUNT=$net_file_count"
    return 0 # 所有检查通过
}

# --- 直接执行时的设置 ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 获取脚本所在目录
    script_dir="$(dirname "${BASH_SOURCE[0]}")"

    # 加载必要的工具脚本 (日志 + 依赖的库)
    config_script="$script_dir/config.sh"
    load_config_script="$script_dir/load_config.sh"
    logging_script="$script_dir/loggings.sh"
    calc_script="$script_dir/calculate_size_and_count.sh"
    disk_script="$script_dir/check_disk_space.sh"
    check_dir_script="$script_dir/check_and_create_directory.sh" 
    
    _libs_loaded_feasibility=true
    for lib in "$config_script" "$load_config_script" "$logging_script" "$calc_script" "$disk_script" "$check_dir_script"; do
        if [ -f "$lib" ]; then
            . "$lib"
        else
            echo "错误：无法加载依赖库 $lib" >&2
            _libs_loaded_feasibility=false
        fi
    done

    if ! $_libs_loaded_feasibility; then
        exit 1 # 直接执行时，依赖必须加载
    fi
    if [ -f "$logging_script" ]; then
        source "$logging_script"
    else
        echo "错误：无法加载日志脚本 $logging_script" >&2
        exit 1 # 直接执行时，日志是必须的
    fi

    # 初始化日志 (只有直接执行时需要)
    init_logging

    # 执行主检查函数
    # 执行主检查函数, 传递所有参数
    check_backup_feasibility "$1" "$2" "$3"
    exit $? # 将函数的退出码作为脚本的退出码
fi
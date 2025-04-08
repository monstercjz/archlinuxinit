#!/bin/bash
# Shebang: 指定脚本使用bash执行

#############################################################
# 验证备份统计信息模块
# 功能：验证目标目录加上源目录中被排除项的总量是否等于源目录的总量。
#############################################################

# 函数：verify_backup_stats
# 功能：验证目标目录加上源目录中被排除项的总量是否等于源目录的总量。
# 参数：
#   $1 - 源目录路径
#   $2 - 目标目录路径
#   $3 - 描述信息 (例如 "系统配置", "用户配置")
#   $4 - 排除项相对路径列表 (以换行符 \n 分隔的单一字符串)
# 返回值：
#   0 - 统计信息匹配 (目标 + 排除 == 源)
#   1 - 统计信息不匹配
#   2 - 无法获取源或目标统计信息
#   3 - 无法计算排除项统计信息
# 注意：
#   - 此函数假设在备份完成后调用。
#   - 大小比较是基于 du -sb (总字节数)。
#   - 数量比较是基于 find ... -type f | wc -l (仅普通文件)。
#   - 对于非常大的目录或大量排除项，计算可能需要一些时间。
#   - 依赖 log_* 函数 (来自 utils/loggings.sh)
#   - 依赖 du, find, wc, mapfile (Bash 4+) 命令
#   - 目前假设排除项是明确的文件或目录路径，不支持通配符模式的精确计算。
verify_backup_stats() {
    local source_dir="$1"
    local target_dir="$2"
    local description="$3"
    local excludes_string="$4" # 接收以换行符分隔的字符串
    local error_occurred=0
    local calc_error=0

    log_info "开始验证备份统计信息 (目标+排除项 vs 源): $description"

    # --- 将接收到的字符串解析回数组 ---
    local exclude_relative_paths=()
    # 使用 mapfile (或 readarray) 将换行符分隔的字符串读入数组
    # 需要 Bash 4+
    if [[ -n "$excludes_string" ]]; then
        mapfile -t exclude_relative_paths <<< "$excludes_string"
        # 兼容旧版 Bash (如果 mapfile 不可用)
        # IFS=$'\n' read -r -d '' -a exclude_relative_paths < <(printf '%s\0' "$excludes_string")
    fi
    log_debug "解析后的排除项列表: (${exclude_relative_paths[*]})" # 调试

    # --- 检查目录是否存在 ---
    if [ ! -d "$source_dir" ]; then
        log_error "验证失败: 源目录不存在: $source_dir"
        return 2
    fi
    if [ ! -d "$target_dir" ]; then
        log_error "验证失败: 目标目录不存在: $target_dir"
        return 2
    fi

    # --- 获取源目录统计信息 ---
    local source_size source_count source_size_cmd source_count_cmd
    log_debug "正在计算源目录统计信息: $source_dir"
    source_size_cmd="du -sb \"$source_dir\" | cut -f1"
    source_count_cmd="find \"$source_dir\" -type f | wc -l"

    source_size=$(eval "$source_size_cmd" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$source_size" ]; then
        log_error "无法获取源目录大小: $source_dir"
        error_occurred=1
    fi

    source_count=$(eval "$source_count_cmd" 2>/dev/null)
     if [ $? -ne 0 ] || [ -z "$source_count" ]; then
        log_error "无法获取源目录文件数量: $source_dir"
        error_occurred=1
    fi

    # --- 获取目标目录统计信息 ---
    local target_size target_count target_size_cmd target_count_cmd
    log_debug "正在计算目标目录统计信息: $target_dir"
    target_size_cmd="du -sb \"$target_dir\" | cut -f1"
    target_count_cmd="find \"$target_dir\" -type f | wc -l"

    target_size=$(eval "$target_size_cmd" 2>/dev/null)
    if [ $? -ne 0 ] || [ -z "$target_size" ]; then
        log_error "无法获取目标目录大小: $target_dir"
        error_occurred=1
    fi

    target_count=$(eval "$target_count_cmd" 2>/dev/null)
     if [ $? -ne 0 ] || [ -z "$target_count" ]; then
        log_error "无法获取目标目录文件数量: $target_dir"
        error_occurred=1
    fi

    # 如果在获取源或目标统计信息时出错，则返回失败
    if [ $error_occurred -ne 0 ]; then
        log_error "验证失败: 无法获取源或目标统计信息 ($description)"
        return 2
    fi

    log_debug "源 ($description): 大小=$source_size, 数量=$source_count"
    log_debug "目标 ($description): 大小=$target_size, 数量=$target_count"

    # --- 计算排除项的总大小和总数量 ---
    local excluded_total_size=0
    local excluded_total_count=0
    log_debug "正在计算排除项统计信息..."

    for rel_path in "${exclude_relative_paths[@]}"; do
        # Trim leading/trailing whitespace just in case
        rel_path=$(echo "$rel_path" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$rel_path" ]; then
            log_debug "跳过空的排除项路径"
            continue
        fi

        local full_exclude_path="${source_dir}/${rel_path}"
        local current_exclude_size=0
        local current_exclude_count=0

        log_debug "处理排除项相对路径: '$rel_path', 完整路径: '$full_exclude_path'" # 调试

        if [ -e "$full_exclude_path" ]; then
            log_debug "计算排除项: $full_exclude_path (存在)"
            # 计算大小
            local size_cmd="du -sb \"$full_exclude_path\" | cut -f1"
            current_exclude_size=$(eval "$size_cmd" 2>/dev/null)
            if [ $? -ne 0 ] || [ -z "$current_exclude_size" ]; then
                log_warn "无法计算排除项大小: $full_exclude_path"
                calc_error=1
                current_exclude_size=0 # 设为0以继续，但标记错误
            fi

            # 计算文件数量 (仅普通文件)
            if [ -d "$full_exclude_path" ]; then # 如果是目录
                 local count_cmd="find \"$full_exclude_path\" -type f | wc -l"
                 current_exclude_count=$(eval "$count_cmd" 2>/dev/null)
                 if [ $? -ne 0 ] || [ -z "$current_exclude_count" ]; then
                     log_warn "无法计算排除目录文件数量: $full_exclude_path"
                     calc_error=1
                     current_exclude_count=0
                 fi
                 log_debug "排除项是目录: '$rel_path', 计算数量: $current_exclude_count" # 调试
            elif [ -f "$full_exclude_path" ]; then # 如果是文件
                 current_exclude_count=1
                 log_debug "排除项是文件: '$rel_path', 数量计为: 1" # 调试
            else # 其他类型（如符号链接）不计入文件数
                 current_exclude_count=0
                 log_debug "排除项是其他类型: '$rel_path', 数量计为: 0" # 调试
            fi
            log_debug "排除项 ('$rel_path'): 当前大小=$current_exclude_size, 当前数量=$current_exclude_count" # 调试
            excluded_total_size=$((excluded_total_size + current_exclude_size))
            excluded_total_count=$((excluded_total_count + current_exclude_count))
            log_debug "排除项 ('$rel_path'): 累加后总大小=$excluded_total_size, 总数量=$excluded_total_count" # 调试
        else
            log_debug "排除项在源目录不存在，跳过统计: $full_exclude_path"
        fi
    done

    if [ $calc_error -ne 0 ]; then
         log_error "验证失败: 计算部分排除项统计信息时出错 ($description)"
         return 3 # 返回特定错误码
    fi

    log_debug "排除项总计 ($description): 大小=$excluded_total_size, 数量=$excluded_total_count"

    # --- 验证: 目标 + 排除 == 源 ---
    local calculated_source_size=$((target_size + excluded_total_size))
    local calculated_source_count=$((target_count + excluded_total_count))

    log_debug "计算出的源 (目标+排除) ($description): 大小=$calculated_source_size, 数量=$calculated_source_count" # 修正日志描述

    local mismatch=0
    # 使用标准 shell 算术比较 (-eq)
    if [[ "$source_size" -ne "$calculated_source_size" ]]; then
        log_error "验证失败 ($description): 大小不匹配 (源: $source_size, 目标+排除: $calculated_source_size)"
        mismatch=1
    fi
     if [[ "$source_count" -ne "$calculated_source_count" ]]; then
        log_error "验证失败 ($description): 文件数量不匹配 (源: $source_count, 目标+排除: $calculated_source_count)"
        mismatch=1
    fi

    # --- 返回结果 ---
    if [ $mismatch -eq 0 ]; then
        log_notice "$description 备份统计信息验证:通过 (目标+排除项 vs 源)"
        return 0
    else
        # 错误信息已在上面记录
        return 1
    fi
}
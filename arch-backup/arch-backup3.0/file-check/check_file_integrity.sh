#!/bin/bash

############################################################
# 文件完整性校验脚本 (源清单验证模式)
# 功能：
#   - generate_source_checksum_manifest: 为源文件/目录生成校验和清单。
#   - verify_checksum_manifest: 使用源清单验证目标备份目录的文件。
############################################################

# --- 依赖检查 ---
# 确保 sha256sum 或 md5sum 可用
_checksum_tool=""
if command -v sha256sum &>/dev/null; then
    _checksum_tool="sha256sum"
elif command -v md5sum &>/dev/null; then
    _checksum_tool="md5sum"
else
    # 在函数调用时会进行更详细的错误处理
    :
fi

#############################################################
# 函数：generate_source_checksum_manifest
# 功能：为指定的源文件或目录生成校验和清单。
# 参数：
#   $1 - 源文件或目录路径 (source_path)
#   $2 - 清单文件的输出路径 (manifest_output_path)
#   $3 - 排除模式（可选，逗号分隔的字符串）(exclude_patterns_csv)
# 返回值：
#   0 - 清单生成成功
#   1 - 清单生成失败
#############################################################
generate_source_checksum_manifest() {
    local source_path="$1"
    local manifest_output_path="$2"
    local exclude_patterns_csv="$3" # 新增排除模式参数
    local checksum_tool_cmd="$_checksum_tool"
    local manifest_dir

    log_section "为源生成校验和清单: $source_path" $LOG_LEVEL_NOTICE

    if [ -z "$checksum_tool_cmd" ]; then
        log_error "文件完整性检查：未找到可用的校验和工具 (sha256sum 或 md5sum)。无法生成清单。"
        return 1
    fi
    if [ -z "$source_path" ]; then
        log_error "文件完整性检查：未提供源路径。"
        return 1
    fi
    if [ ! -e "$source_path" ]; then
        log_error "文件完整性检查：源路径不存在: $source_path"
        return 1
    fi
    if [ -z "$manifest_output_path" ]; then
        log_error "文件完整性检查：未提供清单输出路径。"
        return 1
    fi

    manifest_dir=$(dirname "$manifest_output_path")
    # 确保清单输出目录存在
    if ! mkdir -p "$manifest_dir"; then
        log_error "文件完整性检查：无法创建清单输出目录: $manifest_dir"
        return 1
    fi

    log_info "校验和工具: $checksum_tool_cmd"
    log_info "清单文件将保存到: $manifest_output_path"

    local start_time=$(date +%s)
    local result=0

    # 使用临时文件避免直接写入可能失败
    local tmp_manifest="${manifest_output_path}.tmp.$$"

    if [ -d "$source_path" ]; then
        # 如果是目录，cd 进入该目录，然后运行 find .
        log_info "正在计算目录 '$source_path' 内文件的校验和 (相对路径)..."
        # --- 构建 find 命令 ---
        local find_cmd_base="find ."
        local find_exclude_part=""
        local find_action_part="-type f -print0" # 查找常规文件并以 null 分隔打印

        # 处理排除模式
        if [ -n "$exclude_patterns_csv" ]; then
            log_info "应用排除模式: $exclude_patterns_csv"
            local exclude_conditions=()
            # 将逗号分隔的字符串转换为数组
            IFS=',' read -r -a exclude_array <<< "$exclude_patterns_csv"
            # 确保 source_path 是绝对路径且没有尾随 /
            local abs_source_path
            abs_source_path=$(readlink -f "$source_path")

            for pattern_orig in "${exclude_array[@]}"; do
                # 移除可能的前导/后导空格
                local pattern clean_pattern find_pattern_arg find_pattern_val
                pattern=$(echo "$pattern_orig" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

                if [ -z "$pattern" ]; then
                    continue
                fi

                # --- 转换模式为相对于 find 执行目录 (.) ---
                clean_pattern=""
                if [[ "$pattern" == /* ]]; then
                    # 如果排除模式是绝对路径
                    # 检查它是否在当前 source_path 下
                    if [[ "$pattern" == "$abs_source_path"* ]]; then
                         # 提取相对路径，移除开头的 source_path 和紧随的 /
                         clean_pattern="${pattern#$abs_source_path}"
                         clean_pattern="${clean_pattern#/}" # 移除开头的 /
                    else
                         # 绝对路径不在当前 source_path 下，忽略此模式
                         log_debug "排除模式 '$pattern' 不在当前源路径 '$abs_source_path' 下，忽略。"
                         continue
                    fi
                else
                    # 如果排除模式是相对路径或通配符
                    clean_pattern="$pattern"
                fi

                # --- 确定 find 的参数 (-path 或 -name) ---
                if [[ "$clean_pattern" == *"/"* ]]; then
                    # 如果清理后的模式包含 /，使用 -path 匹配相对路径
                    find_pattern_arg="-path"
                    find_pattern_val="./$clean_pattern"
                else
                    # 否则，使用 -name 匹配基本名称或通配符
                    find_pattern_arg="-name"
                    find_pattern_val="$clean_pattern"
                fi

                # 添加 -o（或）连接符，除了第一个模式
                if [ ${#exclude_conditions[@]} -gt 0 ]; then
                    exclude_conditions+=("-o")
                fi
                exclude_conditions+=("$find_pattern_arg" "$find_pattern_val")
                log_debug "添加排除条件: $find_pattern_arg \"$find_pattern_val\" (来自 '$pattern_orig')"
            done

            # 组合排除条件，并添加 -prune
            if [ ${#exclude_conditions[@]} -gt 0 ]; then
                # find . \( -path './pattern1' -o -name 'pattern2' \) -prune -o -type f -print0
                find_exclude_part=" \( ${exclude_conditions[*]} \) -prune -o"
            fi
        fi

        local final_find_cmd="$find_cmd_base$find_exclude_part $find_action_part"
        log_debug "执行 find 命令: $final_find_cmd"

        # 使用 find . ... -print0 | xargs -0 来安全处理包含特殊字符的文件名
        # 在子 shell 中执行 cd
        (cd "$source_path" && eval "$final_find_cmd" | xargs -0 "$checksum_tool_cmd") > "$tmp_manifest"
        result=$?
    elif [ -f "$source_path" ]; then
        # 如果是文件，cd 到其父目录，然后对文件名计算校验和
        local parent_dir source_basename
        parent_dir=$(dirname "$source_path")
        source_basename=$(basename "$source_path")
        log_info "正在计算文件 '$source_basename' 的校验和 (在其目录 '$parent_dir' 中)..."
        (cd "$parent_dir" && "$checksum_tool_cmd" "$source_basename") > "$tmp_manifest"
        result=$?
    else
        log_error "文件完整性检查：源路径既不是文件也不是目录: $source_path"
        rm -f "$tmp_manifest" 2>/dev/null
        return 1
    fi

    if [ $result -eq 0 ]; then
        # 如果成功，重命名临时文件
        if mv "$tmp_manifest" "$manifest_output_path"; then
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))
            local file_count=$(wc -l < "$manifest_output_path") # 统计清单中的文件数
            log_info "源校验和清单生成成功！共处理 $file_count 个文件，耗时 ${duration} 秒。"
            log_info "清单文件已保存到: $manifest_output_path"
            return 0
        else
            log_error "无法将临时清单重命名为最终文件: $manifest_output_path"
            rm -f "$tmp_manifest" 2>/dev/null
            return 1
        fi
    else
        log_error "生成源校验和清单失败 (退出码: $result)。"
        rm -f "$tmp_manifest" 2>/dev/null
        return 1
    fi
}

#############################################################
# 函数：verify_checksum_manifest
# 功能：使用（源）校验和清单文件验证目标目录中的文件完整性。
# 参数：
#   $1 - 校验和清单文件路径 (manifest_file_path)
#   $2 - 目标备份目录路径 (target_dir_path)
# 返回值：
#   0 - 所有文件验证通过
#   1 - 验证失败
#############################################################
verify_checksum_manifest() {
    local manifest_file_path="$1"
    local target_dir_path="$2"
    local checksum_tool_cmd=""

    log_section "使用清单验证目标文件完整性" $LOG_LEVEL_NOTICE
    log_info "清单文件: $manifest_file_path"
    log_info "目标目录: $target_dir_path"

    if [ ! -f "$manifest_file_path" ]; then
        log_error "文件完整性检查：校验和清单文件不存在: $manifest_file_path"
        return 1
    fi
    if [ ! -d "$target_dir_path" ]; then
        log_error "文件完整性检查：目标目录不存在: $target_dir_path"
        return 1
    fi

    # 从清单文件名推断校验和工具 (或直接使用全局变量)
    if [[ "$manifest_file_path" == *.sha256 ]]; then
        checksum_tool_cmd="sha256sum"
    elif [[ "$manifest_file_path" == *.md5 ]]; then
        checksum_tool_cmd="md5sum"
    elif [ -n "$_checksum_tool" ]; then
         log_warn "无法从清单文件名推断类型，将使用全局检测到的工具: $_checksum_tool"
         checksum_tool_cmd="$_checksum_tool"
    else
        log_error "文件完整性检查：无法确定校验和工具。"
        return 1
    fi

    # 检查校验和工具是否可用
    if ! command -v "$checksum_tool_cmd" &>/dev/null; then
        log_error "文件完整性检查：校验和工具 '$checksum_tool_cmd' 不可用。"
        return 1
    fi
    log_info "校验和工具: $checksum_tool_cmd"

    # 进入目标目录执行校验和检查
    local start_time=$(date +%s)
    log_info "正在验证校验和..."
    local verify_output=""
    local verify_exit_code=0

    # 切换到目标目录执行验证
    pushd "$target_dir_path" > /dev/null || { log_error "无法切换到目标验证目录: $target_dir_path"; return 1; }
    log_debug "当前验证目录: $(pwd)"
    # 使用 --check 选项进行检查。需要提供清单文件的完整路径。
    # --quiet 禁止输出 OK 状态行
    # --warn 报告格式错误的行
    # --strict 严格模式，任何问题都视为错误
    log_debug "执行校验命令: $checksum_tool_cmd --check \"$manifest_file_path\" --quiet"
    # 移除 --warn 和 --strict，只保留 --quiet 以便仅输出错误信息
    verify_output=$("$checksum_tool_cmd" --check "$manifest_file_path" --quiet 2>&1)
    verify_exit_code=$?
    popd > /dev/null || { log_error "无法从目标目录切换回来"; } # 即使失败也要尝试切换回来

    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [ $verify_exit_code -eq 0 ]; then
        log_info "校验和验证成功完成！所有文件完整性校验通过，耗时 ${duration} 秒。"
        if [[ -n "$verify_output" ]]; then
             log_warn "校验和验证过程中出现警告信息:"
             echo "$verify_output" | while IFS= read -r line; do log_warn "  $line"; done
        fi
        return 0
    else
        local failed_count=$(echo "$verify_output" | grep -c ': FAILED')
        log_error "校验和验证失败 (退出码: $verify_exit_code)。发现 $failed_count 个文件校验失败或丢失。"
        log_error "失败详情 (来自 $checksum_tool_cmd):"
        echo "$verify_output" | while IFS= read -r line; do log_error "  $line"; done
        return 1
    fi
}

# --- 直接执行块 (用于测试) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "此脚本主要作为库使用，包含以下函数："
    echo "  generate_source_checksum_manifest <source_path> <manifest_output_path>"
    echo "  verify_checksum_manifest <manifest_file_path> <target_dir_path>"
    echo "请在其他脚本中 source 此文件并调用相应函数。"
    # 可以添加一些简单的测试逻辑
fi
#!/bin/bash

# 依赖: logging.sh (log 函数)

# 检查命令是否存在
# 功能：检查指定的命令是否存在于系统中
# 参数：
#   $1 - 要检查的命令名称
# 返回值：
#   0 - 命令存在
#   1 - 命令不存在
# 错误处理：
#   如果命令不存在，会记录错误
# 使用示例：
#   check_command "rsync" || exit 1
check_command() {
    command -v "$1" >/dev/null 2>&1 || { log "ERROR" "命令 $1 未安装，请先安装该命令"; return 1; }
    return 0
}

# 检查命令版本
# 功能：检查指定命令的版本是否满足最低要求
# 参数：
#   $1 - 要检查的命令名称
#   $2 - 最低版本要求（如 "3.1.0"）
#   $3 - 获取版本的命令行选项（默认为 --version）
#   $4 - 版本号的正则表达式模式（默认为 '[0-9]+(\.[0-9]+)+')
# 返回值：
#   0 - 版本满足要求或无法获取版本信息
#   1 - 版本低于最低要求
# 错误处理：
#   如果无法获取版本信息，会记录警告但不会中断执行
#   如果版本低于要求，会记录警告但不会中断执行
# 使用示例：
#   check_command_version "rsync" "3.1.0"
#   check_command_version "openssl" "1.1.0" "version" "[0-9]+(\.[0-9]+)+[a-z]*"
check_command_version() {
    local cmd=$1
    local min_version=$2
    local version_option=${3:---version}
    local version_regex=${4:-'[0-9]+(\.[0-9]+)+'}

    # 检查命令是否存在
    if ! command -v "$cmd" >/dev/null 2>&1; then
        log "WARN" "命令 $cmd 不存在，无法检查版本"
        return 0 # 或者返回特定错误码？暂定为0，不阻止流程
    fi

    # 获取命令版本
    local version_output
    version_output=$($cmd $version_option 2>&1 | grep -Eo "$version_regex" | head -1)

    if [ -z "$version_output" ]; then
        log "WARN" "无法获取 $cmd 的版本信息"
        return 0
    fi

    # 比较版本 (使用 sort -V 进行版本比较)
    if printf '%s\n' "$min_version" "$version_output" | sort -V -C; then
        # 如果 min_version <= version_output
        log "INFO" "$cmd 版本 $version_output 满足最低要求 $min_version"
        return 0
    else
        # 如果 min_version > version_output
        log "WARN" "$cmd 版本 $version_output 低于推荐的最低版本 $min_version"
        return 1
    fi
}


# 检查文件完整性
# 功能：检查指定文件是否存在且非空，并验证文件权限
# 参数：
#   $1 - 要检查的文件路径
#   $2 - 文件描述（用于日志记录）
#   $3 - 是否检查文件权限（可选，默认为true）
# 返回值：
#   0 - 文件存在且非空 (且权限正确，如果检查)
#   1 - 文件不存在
#   2 - 文件存在但为空
#   3 - 文件存在但权限不正确
# 错误处理：
#   如果文件不存在或为空，会记录错误并返回相应的状态码
#   如果指定检查权限，会验证文件是否可读
# 使用示例：
#   check_file_integrity "/path/to/file" "配置文件"
#   if ! check_file_integrity "/path/to/backup" "备份文件"; then
#     log "ERROR" "备份文件完整性检查失败"
#   fi
check_file_integrity() {
    local file_path=$1
    local desc=$2
    local check_permissions=${3:-true}
    local status=0

    if [ ! -e "$file_path" ]; then
        log "ERROR" "完整性检查失败: $desc 文件/目录不存在: $file_path"
        return 1
    fi

    # 如果是文件，检查是否为空
    if [ -f "$file_path" ] && [ ! -s "$file_path" ]; then
        log "WARN" "完整性检查警告: $desc 文件大小为零: $file_path"
        return 2 # 警告，但不一定是致命错误
    fi

    # 检查文件/目录权限
    if [ "$check_permissions" = true ]; then
       if [ ! -r "$file_path" ]; then
            log "ERROR" "完整性检查失败: $desc 不可读: $file_path"
            return 3
       fi
       # 可选：检查写权限或执行权限
       # if [ ! -w "$file_path" ]; then ... fi
       # if [ ! -x "$file_path" ]; then ... fi
    fi


    log "DEBUG" "完整性检查通过: $desc ($file_path)"
    return 0
}


# 带重试功能的执行命令
# 功能：执行指定的命令，如果失败则自动重试，并提供详细的错误信息和进度显示
# 参数：
#   $1 - 要执行的命令（字符串形式）
#   $2 - 命令描述（用于日志记录）
#   $3 - 最大重试次数（默认为3次）
#   $4 - 重试间隔时间（秒，默认为5秒）
#   $5 - 是否显示进度（可选，默认为false）
#   $6 - 命令超时时间（秒，可选，默认为0表示无超时）
# 返回值：
#   0 - 命令执行成功
#   124 - 命令执行超时
#   其他非0值 - 所有重试后命令仍然失败，返回最后一次执行的退出码
# 错误处理：
#   - 如果命令执行失败，会自动重试直到达到最大重试次数
#   - 每次失败都会记录详细的警告信息、退出码和错误输出
#   - 支持指数退避重试策略，重试间隔会逐渐增加
#   - 支持命令超时处理，避免命令长时间挂起
#   - 自动清理临时文件和进程
# 全局变量依赖:
#   LOG_FILE - 日志文件路径
# 使用示例：
#   exec_with_retry "rsync -a /src/ /dest/" "文件同步" 5 10 true
#   if ! exec_with_retry "tar -cf archive.tar files/" "创建归档"; then
#     log "ERROR" "归档创建失败"
#   fi
exec_with_retry() {
    local cmd=$1
    local desc=$2
    local max_retries=${3:-3}
    local initial_retry_delay=${4:-5}
    local show_progress=${5:-false}
    local timeout=${6:-0}
    local retry_count=0
    local exit_code=0
    local error_output=""
    # 创建临时文件时指定目录，避免权限问题
    local temp_error_file=$(mktemp "${BACKUP_ROOT}/tmp_error_XXXXXX")
    local temp_output_file=$(mktemp "${BACKUP_ROOT}/tmp_output_XXXXXX")
    local start_time=$(date +%s)
    local timeout_cmd=""

    # 确保临时文件在函数退出时被删除
    trap 'rm -f "$temp_error_file" "$temp_output_file"; trap - INT; return $exit_code' EXIT
    # 捕获SIGINT信号，确保清理临时文件并返回特定退出码
    trap 'rm -f "$temp_error_file" "$temp_output_file"; log "WARN" "命令执行被中断: $desc"; trap - INT; return 130' INT

    # 如果设置了超时时间，使用timeout命令
    if [ "$timeout" -gt 0 ] && command -v timeout &>/dev/null; then
        timeout_cmd="timeout $timeout "
        log "DEBUG" "命令将在 $timeout 秒后超时: $cmd"
    fi

    log "DEBUG" "执行命令: $cmd"

    while [ $retry_count -le $max_retries ]; do # 改为 <= 以便执行 max_retries+1 次尝试
        # 计算当前重试的延迟时间（指数退避策略）
        local current_delay=$initial_retry_delay
        if [ $retry_count -gt 0 ]; then
            # 每次重试增加延迟时间，但最多不超过60秒
            current_delay=$(( initial_retry_delay * (2 ** (retry_count - 1)) ))
            [ $current_delay -gt 60 ] && current_delay=60
        fi

        # 显示进度信息
        if [ "$show_progress" = true ]; then
            if [ $retry_count -gt 0 ]; then
                log "INFO" "$desc - 第 $retry_count 次重试 (共 $max_retries 次)..."
            else
                log "INFO" "$desc - 开始执行..."
            fi
        fi

        # 执行命令并同时捕获标准输出和错误输出
        # 使用 bash -c 来执行复杂的命令字符串，确保管道和重定向正确处理
        if [ -n "$timeout_cmd" ]; then
            # 使用timeout命令执行
            bash -c "${timeout_cmd}${cmd}" > "$temp_output_file" 2>"$temp_error_file"
        else
            # 正常执行命令
            bash -c "$cmd" > "$temp_output_file" 2>"$temp_error_file"
        fi

        exit_code=$?
        error_output=$(cat "$temp_error_file")

        # 检查是否超时
        if [ $exit_code -eq 124 ] && [ -n "$timeout_cmd" ]; then
            log "WARN" "$desc 执行超时 (${timeout}秒)"
            # trap EXIT 会处理清理
            return 124
        fi

        if [ $exit_code -eq 0 ]; then
            # 命令执行成功
            local end_time=$(date +%s)
            local duration=$((end_time - start_time))

            # 如果输出很大，只记录部分到日志
            local output_size=$(stat -c%s "$temp_output_file" 2>/dev/null || echo "0")
            if [ "$output_size" -gt 1024 ]; then
                log "DEBUG" "命令输出较大 (${output_size} 字节)，只记录前1024字节到日志"
                head -c 1024 "$temp_output_file" >> "$LOG_FILE"
                echo -e "\n... (输出被截断) ..." >> "$LOG_FILE"
            else
                # 将标准输出附加到日志文件
                cat "$temp_output_file" >> "$LOG_FILE"
            fi

            if [ $retry_count -gt 0 ]; then
                log "INFO" "$desc 在第 $retry_count 次重试后成功，总耗时: ${duration}秒"
            else
                if [ "$show_progress" = true ]; then
                    log "INFO" "$desc 成功完成，耗时: ${duration}秒"
                fi
            fi
            # trap EXIT 会处理清理
            return 0
        else
            # 命令执行失败
            retry_count=$((retry_count + 1))

            # 记录详细的错误信息
            local error_summary=""
            if [ -n "$error_output" ]; then
                # 截取错误输出的前200个字符作为摘要
                error_summary="${error_output:0:200}"
                if [ ${#error_output} -gt 200 ]; then
                    error_summary="${error_summary}...(更多错误信息已记录到日志)"
                fi
                # 将完整错误输出记录到日志文件
                echo "命令错误输出: $error_output" >> "$LOG_FILE"
            else
                error_summary="无错误输出"
            fi

            if [ $retry_count -le $max_retries ]; then
                log "WARN" "$desc 失败 (退出码: $exit_code)，错误: $error_summary"
                log "INFO" "$current_delay 秒后进行第 $retry_count 次重试 (共 $max_retries 次)..."

                # 在重试前等待，并显示倒计时
                if [ "$show_progress" = true ] && [ $current_delay -gt 5 ]; then
                    for ((i=current_delay; i>0; i-=5)); do
                        if [ $i -le 5 ]; then break; fi
                        log "DEBUG" "等待重试中... $i 秒"
                        sleep 5
                    done
                    sleep $(($i > 0 ? $i : 0)) # 确保 sleep 时间非负
                else
                    sleep $current_delay
                fi
            else
                log "ERROR" "$desc 在 $max_retries 次尝试后仍然失败 (退出码: $exit_code)"
                log "ERROR" "最后错误: $error_summary"

                # 记录失败的命令到日志，方便手动重试
                echo "失败的命令: $cmd" >> "$LOG_FILE"
                echo "命令描述: $desc" >> "$LOG_FILE"
                echo "最大重试次数: $max_retries" >> "$LOG_FILE"
                echo "总耗时: $(($(date +%s) - start_time))秒" >> "$LOG_FILE"
                # trap EXIT 会处理清理
                return $exit_code # 返回最后一次的退出码
            fi
        fi
    done
    # trap EXIT 会处理清理
    return $exit_code # 理论上不会执行到这里，但为了保险
}


# 创建恢复点
# 功能：在备份过程中创建检查点，以便在备份中断时能够从该点继续
# 参数：
#   $1 - 备份阶段名称（如 system_config, user_config 等）
#   $2 - 额外的恢复点信息（可选，JSON格式字符串）
# 全局变量依赖:
#   BACKUP_ROOT, TIMESTAMP, BACKUP_DIR, REAL_USER, COMPRESS_BACKUP,
#   COMPRESS_METHOD, DIFF_BACKUP, VERIFY_BACKUP, PARALLEL_BACKUP, LOG_FILE
# 返回值：
#   0 - 恢复点创建成功
#   1 - 恢复点创建失败
# 错误处理：
#   如果恢复点文件创建失败，会记录错误但不会中断脚本执行
# 特性：
#   - 自动清理旧的恢复点文件（保留最近5个）
#   - 记录详细的备份状态和配置信息
#   - 支持额外的自定义恢复点信息
# 使用示例：
#   create_recovery_point "system_config"
#   create_recovery_point "packages" '{"last_package":"firefox"}'
create_recovery_point() {
    local stage=$1
    local extra_info=${2:-"{}"}
    # 使用更明确的文件名格式
    local recovery_file="${BACKUP_ROOT}/recovery_${TIMESTAMP}_${stage}.json"
    local status=0

    log "INFO" "创建恢复点: $stage"

    # 获取系统信息
    local hostname=$(hostname 2>/dev/null || echo "unknown")
    local kernel_version=$(uname -r 2>/dev/null || echo "unknown")
    local available_space=$(df -h "$BACKUP_ROOT" | awk 'NR==2 {print $4}' 2>/dev/null || echo "unknown")

    # 创建恢复点文件内容
    # 注意：JSON 格式要求严格，特别是布尔值和逗号
    local json_content="{"
    json_content+="\"timestamp\": \"$(date +"%Y-%m-%d %H:%M:%S")\","
    json_content+="\"stage\": \"$stage\","
    json_content+="\"backup_dir\": \"$BACKUP_DIR\","
    json_content+="\"user\": \"$REAL_USER\","
    json_content+="\"hostname\": \"$hostname\","
    json_content+="\"kernel\": \"$kernel_version\","
    json_content+="\"available_space\": \"$available_space\","
    json_content+="\"backup_options\": {"
    json_content+="\"compress\": ${COMPRESS_BACKUP:-false}," # 确保是布尔值
    json_content+="\"compress_method\": \"${COMPRESS_METHOD:-gzip}\","
    json_content+="\"diff_backup\": ${DIFF_BACKUP:-false},"
    json_content+="\"verify_backup\": ${VERIFY_BACKUP:-false},"
    json_content+="\"parallel_backup\": ${PARALLEL_BACKUP:-false}"
    json_content+="},"
    json_content+="\"extra_info\": $extra_info" # 假设 extra_info 是有效的 JSON
    # 移除 completed_steps，因为它在原脚本中逻辑混乱且难以维护
    json_content+="}"

    # 写入恢复点文件
    if ! echo "$json_content" > "$recovery_file"; then
        log "ERROR" "创建恢复点文件失败: $recovery_file"
        status=1
    else
        # 验证恢复点文件
        if [ -s "$recovery_file" ]; then
            log "DEBUG" "恢复点文件已创建: $recovery_file ($(stat -c%s "$recovery_file") 字节)"

            # 清理旧的恢复点文件，只保留最近5个
            # 使用 find 和 sort -r 来获取最新的文件
            local old_recovery_files
            old_recovery_files=$(find "$BACKUP_ROOT" -maxdepth 1 -name "recovery_*.json" -type f -printf '%T@ %p\n' | sort -nr | tail -n +6 | cut -d' ' -f2-)

            if [ -n "$old_recovery_files" ]; then
                local count=$(echo "$old_recovery_files" | wc -l)
                log "DEBUG" "清理 $count 个旧恢复点文件"
                echo "$old_recovery_files" | xargs -r rm -f --
            fi
        else
            log "WARN" "恢复点文件创建成功但为空: $recovery_file"
            status=1
        fi
    fi

    return $status
}


# 查找最近的备份目录
# 功能：查找最近的备份目录，用于差异备份
# 参数：无
# 全局变量依赖:
#   BACKUP_ROOT, DIFF_BACKUP
# 输出:
#   设置全局变量 LAST_BACKUP_DIR 为找到的最近备份目录路径
# 返回值：
#   0 - 总是返回成功
# 错误处理：
#   如果没有找到以前的备份，会记录信息并继续执行完整备份
# 特性：
#   - 仅在差异备份模式下有效
#   - 按日期排序查找备份目录
# 使用示例：
#   find_last_backup
find_last_backup() {
    # 清空上次结果
    LAST_BACKUP_DIR=""

    if [ "$DIFF_BACKUP" != "true" ]; then
        log "DEBUG" "差异备份未启用，跳过查找上次备份"
        return 0
    fi

    log "INFO" "查找最近的备份目录以进行差异备份..."

    # 获取所有符合日期格式的备份目录并按名称排序（最新的在最后）
    local latest_backup
    latest_backup=$(find "$BACKUP_ROOT" -maxdepth 1 -type d -name "????-??-??" -printf '%f\n' | sort -r | head -n 1)

    if [ -n "$latest_backup" ]; then
        LAST_BACKUP_DIR="${BACKUP_ROOT}/${latest_backup}"
        # 确保找到的是一个目录
        if [ -d "$LAST_BACKUP_DIR" ]; then
            log "INFO" "找到最近的备份目录: $LAST_BACKUP_DIR"
        else
            log "WARN" "找到的路径 $LAST_BACKUP_DIR 不是目录，将进行完整备份"
            LAST_BACKUP_DIR=""
        fi
    else
        log "INFO" "没有找到以前的备份，将进行完整备份"
    fi
    return 0
}


# 创建备份摘要
# 功能：创建包含备份信息的摘要文件
# 参数：无
# 全局变量依赖:
#   BACKUP_DIR, REAL_USER, BACKUP_SYSTEM_CONFIG, BACKUP_USER_CONFIG,
#   BACKUP_CUSTOM_PATHS, BACKUP_PACKAGES, BACKUP_LOGS, COMPRESS_BACKUP,
#   COMPRESS_METHOD, DIFF_BACKUP, VERIFY_BACKUP, BACKUP_ROOT,
#   BACKUP_RETENTION_COUNT, LOG_RETENTION_DAYS, CUSTOM_PATHS, LOG_FILE
# 返回值：
#   0 - 创建成功
#   1 - 创建失败
# 错误处理：
#   如果摘要文件创建失败，会记录在日志中
# 摘要内容：
#   - 备份时间和主机信息
#   - 备份内容概述
#   - 系统信息（内核版本、Arch版本等）
#   - 备份配置信息
#   - 自定义路径备份状态（如果启用）
# 使用示例：
#   create_backup_summary || log "WARN" "创建备份摘要失败"
create_backup_summary() {
    log "INFO" "创建备份摘要..."

    # 检查备份目录是否存在
    if [ ! -d "$BACKUP_DIR" ]; then
        log "ERROR" "备份目录 $BACKUP_DIR 不存在，无法创建摘要"
        return 1
    fi

    local summary_file="${BACKUP_DIR}/backup-summary.txt"

    # 获取系统信息（增加错误处理）
    local kernel_version=$(uname -r 2>/dev/null || echo "N/A")
    local arch_version=$(pacman -Q core/filesystem 2>/dev/null | cut -d' ' -f2 || echo "N/A")
    local total_packages=$(pacman -Q 2>/dev/null | wc -l || echo "N/A")
    local explicit_packages=$(pacman -Qe 2>/dev/null | wc -l || echo "N/A")
    local foreign_packages=$(pacman -Qm 2>/dev/null | wc -l || echo "N/A")

    # 使用 cat 和 here document 创建文件
    if ! cat > "$summary_file" << EOF
# Arch Linux 备份摘要

备份时间: $(date '+%Y-%m-%d %H:%M:%S')
主机名: $(hostname 2>/dev/null || echo "N/A")
用户: $REAL_USER

## 备份内容

$([ "$BACKUP_SYSTEM_CONFIG" == "true" ] && echo "- 系统配置文件 (/etc)" || echo "- 系统配置文件 (已跳过)")
$([ "$BACKUP_USER_CONFIG" == "true" ] && echo "- 用户配置文件 (~/.*)" || echo "- 用户配置文件 (已跳过)")
$([ "$BACKUP_CUSTOM_PATHS" == "true" ] && echo "- 自定义路径备份" || echo "- 自定义路径备份 (已跳过)")
$([ "$BACKUP_PACKAGES" == "true" ] && echo "- 软件包列表" || echo "- 软件包列表 (已跳过)")
$([ "$BACKUP_LOGS" == "true" ] && echo "- 系统日志" || echo "- 系统日志 (已跳过)")
$([ "$COMPRESS_BACKUP" == "true" ] && echo "- 备份已压缩 (使用 $COMPRESS_METHOD)" || echo "- 备份未压缩")
$([ "$DIFF_BACKUP" == "true" ] && echo "- 差异备份模式 (参考: ${LAST_BACKUP_DIR:-无})" || echo "- 完整备份模式")
$([ "$VERIFY_BACKUP" == "true" ] && echo "- 备份验证已启用" || echo "- 备份验证已禁用")

## 系统信息

- 内核版本: $kernel_version
- Arch 版本: $arch_version
- 已安装软件包数量: $total_packages
- 手动安装软件包数量: $explicit_packages
- 外部软件包数量: $foreign_packages

## 备份配置

- 备份根目录: $BACKUP_ROOT
- 备份保留数量: $BACKUP_RETENTION_COUNT
- 日志保留天数: $LOG_RETENTION_DAYS
EOF
    then
        log "ERROR" "创建备份摘要文件失败: $summary_file"
        return 1
    fi

    # 添加自定义路径备份信息（如果启用且存在）
    if [ "$BACKUP_CUSTOM_PATHS" == "true" ] && [ -n "$CUSTOM_PATHS" ]; then
        echo -e "\n## 已备份的自定义路径\n" >> "$summary_file"

        IFS=' ' read -r -a custom_paths_array <<< "$CUSTOM_PATHS"
        for path in "${custom_paths_array[@]}"; do
            if [ -e "$path" ]; then
                local base_name=$(basename "$path")
                local dest_path="${BACKUP_DIR}/custom/$base_name"

                if [ -e "$dest_path" ]; then
                    echo "- $path (成功)" >> "$summary_file"
                else
                    # 检查是否因为排除而未备份
                    local excluded=false
                    # (这里可以添加更复杂的逻辑来检查排除规则，但为简化，假设不存在就是失败)
                    echo "- $path (失败或被排除)" >> "$summary_file"
                fi
            else
                echo "- $path (源路径不存在)" >> "$summary_file"
            fi
        done
    fi

    log "INFO" "备份摘要已创建: $summary_file"
    return 0
}

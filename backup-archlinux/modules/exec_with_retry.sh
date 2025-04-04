# 带重试功能的执行命令
# 功能：执行指定的命令，如果失败则自动重试，并提供详细的错误信息和进度显示
# 参数：
#   $1 - 要执行的命令（字符串形式）
#   $2 - 命令描述（用于日志记录）
#   $3 - 最大重试次数（默认为3次）
#   $4 - 重试间隔时间（默认为5秒）
#   $5 - 是否显示进度（可选，默认为false）
# 返回值：
#   0 - 命令执行成功
#   非0 - 所有重试后命令仍然失败，返回最后一次执行的退出码
# 错误处理：
#   如果命令执行失败，会自动重试直到达到最大重试次数
#   每次失败都会记录详细的警告信息、退出码和错误输出
#   支持指数退避重试策略，重试间隔会逐渐增加
# 使用示例：
#   exec_with_retry "rsync -a /src/ /dest/" "文件同步" 5 10 true
#   if ! exec_with_retry "tar -cf archive.tar files/" "创建归档"; then
#     log "ERROR" "归档创建失败"
#   fi
# 带重试功能的执行命令
# 功能：执行指定的命令，如果失败则自动重试，并提供详细的错误信息和进度显示
# 参数：
#   $1 - 要执行的命令（字符串形式）
#   $2 - 命令描述（用于日志记录）
#   $3 - 最大重试次数（默认为3次）
#   $4 - 重试间隔时间（默认为5秒）
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
    local temp_error_file=$(mktemp)
    local temp_output_file=$(mktemp)
    local start_time=$(date +%s)
    local timeout_cmd=""
    
    # 如果设置了超时时间，使用timeout命令
    if [ $timeout -gt 0 ] && command -v timeout &>/dev/null; then
        timeout_cmd="timeout $timeout "
        log "DEBUG" "命令将在 $timeout 秒后超时: $cmd"
    fi
    
    log "DEBUG" "执行命令: $cmd"
    
    # 捕获SIGINT信号，确保清理临时文件
    trap 'rm -f "$temp_error_file" "$temp_output_file"; log "WARN" "命令执行被中断: $desc"; return 130' INT
    
    while [ $retry_count -lt $max_retries ]; do
        # 计算当前重试的延迟时间（指数退避策略）
        local current_delay=$initial_retry_delay
        if [ $retry_count -gt 0 ]; then
            # 每次重试增加50%的延迟时间，但最多不超过60秒
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
        if [ -n "$timeout_cmd" ]; then
            # 使用timeout命令执行
            eval $timeout_cmd$cmd > "$temp_output_file" 2>"$temp_error_file"
        else
            # 正常执行命令
            eval $cmd > "$temp_output_file" 2>"$temp_error_file"
        fi
        
        exit_code=$?
        error_output=$(cat "$temp_error_file")
        
        # 检查是否超时
        if [ $exit_code -eq 124 ] && [ -n "$timeout_cmd" ]; then
            log "WARN" "$desc 执行超时 (${timeout}秒)"
            rm -f "$temp_error_file" "$temp_output_file"
            trap - INT
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
                echo "\n... (输出被截断) ..." >> "$LOG_FILE"
            else
                cat "$temp_output_file" >> "$LOG_FILE"
            fi
            
            if [ $retry_count -gt 0 ]; then
                log "INFO" "$desc 在第 $retry_count 次重试后成功，总耗时: ${duration}秒"
            else
                if [ "$show_progress" = true ]; then
                    log "INFO" "$desc 成功完成，耗时: ${duration}秒"
                fi
            fi
            
            rm -f "$temp_error_file" "$temp_output_file"
            trap - INT
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
            
            if [ $retry_count -lt $max_retries ]; then
                log "WARN" "$desc 失败 (退出码: $exit_code)，错误: $error_summary"
                log "INFO" "$current_delay 秒后进行第 $retry_count 次重试 (共 $max_retries 次)..."
                
                # 在重试前等待，并显示倒计时
                if [ "$show_progress" = true ] && [ $current_delay -gt 5 ]; then
                    for ((i=current_delay; i>0; i-=5)); do
                        if [ $i -le 5 ]; then break; fi
                        log "DEBUG" "等待重试中... $i 秒"
                        sleep 5
                    done
                    sleep $(($i))
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
            fi
        fi
    done
    
    rm -f "$temp_error_file" "$temp_output_file"
    trap - INT
    return $exit_code
}
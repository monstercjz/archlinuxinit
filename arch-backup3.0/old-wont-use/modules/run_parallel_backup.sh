# 并行执行备份任务
# 功能：并行执行多个备份任务，提高备份效率
# 参数：
#   $@ - 要执行的任务列表
# 返回值：
#   0 - 所有任务成功完成
#   1 - 至少有一个任务失败
# 错误处理：
#   记录每个任务的执行结果
#   提供详细的任务执行状态和进度信息
# 特性：
#   - 支持任务优先级（系统配置和用户配置优先）
#   - 动态资源管理，避免系统过载
#   - 支持GNU Parallel（如果安装）或使用bash内置的后台进程
#   - 提供详细的执行统计信息
run_parallel_backup() {
    local tasks=($@)
    local results=()  
    local pids=()  # 存储后台进程的PID
    local task_count=${#tasks[@]}
    local completed=0
    local failed=0
    local start_time=$(date +%s)
    
    log "INFO" "开始并行备份，共 $task_count 个任务，最大并行数 $PARALLEL_JOBS"
    
    # 检查系统负载，动态调整并行任务数
    local system_load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "0")
    local cpu_count=$(grep -c processor /proc/cpuinfo 2>/dev/null || echo "$PARALLEL_JOBS")
    local adjusted_jobs=$PARALLEL_JOBS
    
    # 如果系统负载过高，减少并行任务数
    if (( $(echo "$system_load > $cpu_count * 0.7" | bc -l 2>/dev/null || echo "0") )); then
        adjusted_jobs=$(( PARALLEL_JOBS / 2 ))
        adjusted_jobs=$(( adjusted_jobs > 1 ? adjusted_jobs : 1 ))
        log "WARN" "系统负载较高 ($system_load)，调整并行任务数为 $adjusted_jobs"
    fi
    
    # 使用GNU Parallel执行任务
    if [ "$HAS_PARALLEL" == "true" ]; then
        log "INFO" "使用 GNU Parallel 执行并行备份"
        
        # 创建临时任务文件，按优先级排序
        local task_file="${BACKUP_ROOT}/parallel_tasks_${TIMESTAMP}.txt"
        
        # 优先添加系统配置和用户配置备份任务
        for task in "${tasks[@]}"; do
            if [[ "$task" == *"backup_system_config"* ]] || [[ "$task" == *"backup_user_config"* ]]; then
                echo "$task" >> "$task_file"
            fi
        done
        
        # 添加其他任务
        for task in "${tasks[@]}"; do
            if [[ "$task" != *"backup_system_config"* ]] && [[ "$task" != *"backup_user_config"* ]]; then
                echo "$task" >> "$task_file"
            fi
        done
        
        # 使用GNU Parallel执行任务，添加进度显示
        parallel --jobs "$adjusted_jobs" --progress --joblog "${BACKUP_ROOT}/parallel_log_${TIMESTAMP}.txt" < "$task_file"
        
        # 检查结果
        local parallel_exit=$?
        if [ $parallel_exit -eq 0 ]; then
            log "INFO" "并行备份任务全部完成"
        else
            log "WARN" "并行备份任务部分失败，退出码: $parallel_exit"
        fi
        
        # 清理临时文件
        rm -f "$task_file"
        
        return $parallel_exit
    else
        # 使用bash后台进程实现并行
        log "INFO" "使用bash后台进程实现并行备份"
        
        # 创建临时目录存储任务结果
        local temp_dir="${BACKUP_ROOT}/parallel_results_${TIMESTAMP}"
        mkdir -p "$temp_dir"
        
        # 对任务进行优先级排序
        local priority_tasks=()
        local normal_tasks=()
        
        for task in "${tasks[@]}"; do
            if [[ "$task" == *"backup_system_config"* ]] || [[ "$task" == *"backup_user_config"* ]]; then
                priority_tasks+=("$task")
            else
                normal_tasks+=("$task")
            fi
        done
        
        # 合并排序后的任务
        local sorted_tasks=("${priority_tasks[@]}" "${normal_tasks[@]}")
        
        # 启动任务，控制并行数量
        local running=0
        local i=0
        local task_count=${#sorted_tasks[@]}
        
        while [ $i -lt $task_count ]; do
            # 检查系统负载，动态调整并行任务数
            local current_load=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}' || echo "0")
            if (( $(echo "$current_load > $cpu_count * 0.8" | bc -l 2>/dev/null || echo "0") )); then
                log "WARN" "系统负载高 ($current_load)，暂停启动新任务 (5秒)"
                sleep 5
                continue
            fi
            
            # 检查当前运行的任务数量
            if [ $running -lt $adjusted_jobs ]; then
                local task=${sorted_tasks[$i]}
                local result_file="${temp_dir}/result_${i}.txt"
                local time_file="${temp_dir}/time_${i}.txt"
                
                # 记录任务开始时间
                date +%s > "$time_file"
                
                # 在后台执行任务并将结果保存到文件
                eval "$task; echo \$? > '$result_file'" &
                pids+=($!)
                
                log "INFO" "启动任务 #$((i+1))/$task_count: ${task:0:50}... (PID: ${pids[-1]})"
                
                running=$((running + 1))
                i=$((i + 1))
            else
                # 等待任意一个任务完成
                wait -n 2>/dev/null || true
                running=$((running - 1))
            fi
        done
        
        # 等待所有任务完成，显示进度
        log "INFO" "等待所有并行任务完成..."
        local remaining=${#pids[@]}
        while [ $remaining -gt 0 ]; do
            local completed_now=$((task_count - remaining))
            local percent=$((completed_now * 100 / task_count))
            log "INFO" "进度: $percent% ($completed_now/$task_count 任务完成)"
            
            # 等待任意一个任务完成
            wait -n 2>/dev/null || true
            
            # 重新计算剩余任务数
            remaining=0
            for pid in "${pids[@]}"; do
                if kill -0 $pid 2>/dev/null; then
                    remaining=$((remaining + 1))
                fi
            done
            
            # 避免过于频繁的日志输出
            if [ $remaining -gt 0 ]; then
                sleep 2
            fi
        done
        
        # 收集结果
        local total_time=0
        for ((i=0; i<$task_count; i++)); do
            local result_file="${temp_dir}/result_${i}.txt"
            local time_file="${temp_dir}/time_${i}.txt"
            
            if [ -f "$result_file" ]; then
                local exit_code=$(cat "$result_file")
                results+=($exit_code)
                
                # 计算任务执行时间
                if [ -f "$time_file" ]; then
                    local start_time=$(cat "$time_file")
                    local end_time=$(date +%s)
                    local task_time=$((end_time - start_time))
                    total_time=$((total_time + task_time))
                    
                    if [ "$exit_code" -eq 0 ]; then
                        completed=$((completed + 1))
                        log "INFO" "任务 #$((i+1)) 成功完成，耗时: ${task_time}秒"
                    else
                        failed=$((failed + 1))
                        log "WARN" "任务 #$((i+1)) 失败，退出码: $exit_code，耗时: ${task_time}秒"
                    fi
                else
                    if [ "$exit_code" -eq 0 ]; then
                        completed=$((completed + 1))
                    else
                        failed=$((failed + 1))
                        log "WARN" "任务 #$((i+1)) 失败，退出码: $exit_code"
                    fi
                fi
            else
                log "ERROR" "任务 #$((i+1)) 的结果文件不存在"
                failed=$((failed + 1))
            fi
        done
        
        # 清理临时文件
        rm -rf "$temp_dir"
        
        # 计算总执行时间和并行效率
        local end_time=$(date +%s)
        local wall_time=$((end_time - start_time))
        local efficiency=0
        if [ $wall_time -gt 0 ]; then
            efficiency=$(( (total_time * 100) / (wall_time * task_count) ))
        fi
        
        # 报告结果
        log "INFO" "并行备份完成: $completed 成功, $failed 失败, 总耗时: ${wall_time}秒, 并行效率: ${efficiency}%"
        
        if [ $failed -eq 0 ]; then
            return 0
        else
            return 1
        fi
    fi
}
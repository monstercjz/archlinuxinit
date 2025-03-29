#!/bin/bash

# 依赖: logging.sh (log 函数)

# 并行执行备份任务
# 功能：并行执行多个备份任务，提高备份效率
# 参数：
#   $@ - 要执行的任务列表 (函数名字符串)
# 全局变量依赖:
#   PARALLEL_JOBS, HAS_PARALLEL (来自 dependencies.sh), BACKUP_ROOT, TIMESTAMP, LOG_FILE
# 返回值：
#   0 - 所有任务成功完成
#   非0 - 至少有一个任务失败，返回失败任务的数量或最后一个非零退出码
# 错误处理：
#   记录每个任务的执行结果
#   提供详细的任务执行状态和进度信息
# 特性：
#   - 支持任务优先级（系统配置和用户配置优先）
#   - 动态资源管理，避免系统过载 (简单实现)
#   - 支持GNU Parallel（如果安装）或使用bash内置的后台进程
#   - 提供详细的执行统计信息
run_parallel_backup() {
    # 将传入的函数名作为任务
    local tasks=("$@")
    local task_count=${#tasks[@]}
    local completed=0
    local failed=0
    local start_time=$(date +%s)

    if [ $task_count -eq 0 ]; then
        log "INFO" "没有并行任务需要执行"
        return 0
    fi

    log "INFO" "开始并行备份，共 $task_count 个任务，最大并行数 ${PARALLEL_JOBS:-4}"

    # 检查系统负载，动态调整并行任务数 (简单版本)
    local system_load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0")
    local cpu_count=$(grep -c processor /proc/cpuinfo 2>/dev/null || echo "${PARALLEL_JOBS:-4}")
    local adjusted_jobs=${PARALLEL_JOBS:-4}

    # 如果系统负载过高，减少并行任务数 (简单策略)
    if (( $(echo "$system_load > $cpu_count * 0.7" | bc -l 2>/dev/null || echo "0") )); then
        adjusted_jobs=$(( adjusted_jobs / 2 ))
        adjusted_jobs=$(( adjusted_jobs > 1 ? adjusted_jobs : 1 )) # 至少为1
        log "WARN" "系统负载较高 ($system_load)，调整并行任务数为 $adjusted_jobs"
    fi

    # --- 使用GNU Parallel执行任务 ---
    if [ "${HAS_PARALLEL:-false}" == "true" ]; then
        log "INFO" "使用 GNU Parallel 执行并行备份 (调整后 jobs: $adjusted_jobs)"

        # 创建临时任务文件，按优先级排序
        local task_file="${BACKUP_ROOT}/parallel_tasks_${TIMESTAMP}.txt"
        local parallel_log="${BACKUP_ROOT}/parallel_log_${TIMESTAMP}.txt"
        # 清理可能存在的旧文件
        rm -f "$task_file" "$parallel_log"

        # 优先添加系统配置和用户配置备份任务
        for task in "${tasks[@]}"; do
            if [[ "$task" == "backup_system_config" || "$task" == "backup_user_config" ]]; then
                # 将函数调用写入任务文件
                echo "$task" >> "$task_file"
            fi
        done

        # 添加其他任务
        for task in "${tasks[@]}"; do
             if [[ "$task" != "backup_system_config" && "$task" != "backup_user_config" ]]; then
                echo "$task" >> "$task_file"
            fi
        done

        # 使用GNU Parallel执行任务，添加进度显示
        # 需要确保 parallel 可以调用这些函数。通常需要导出函数或使用 bash -c。
        # 为了在库文件中保持独立性，这里假设主脚本已 source 所有库
        # 并且函数已导出 (export -f backup_system_config 等)
        # 或者，更健壮的方式是让 parallel 执行一个调用函数的子脚本。
        # 这里采用简单方式，依赖主脚本导出函数。
        if parallel --jobs "$adjusted_jobs" --progress --joblog "$parallel_log" < "$task_file"; then
             log "INFO" "GNU Parallel 任务全部成功完成"
             failed=0
        else
             # 从 joblog 中统计失败数量 (第七列是退出码)
             failed=$(awk 'NR>1 && $7 != 0 {print $0}' "$parallel_log" 2>/dev/null | wc -l)
             log "WARN" "GNU Parallel 任务部分或全部失败 ($failed 失败)"
        fi

        # 清理临时文件
        rm -f "$task_file"
        # 保留 parallel_log 以供调试

        [ $failed -eq 0 ] && return 0 || return $failed

    # --- 使用bash后台进程实现并行 ---
    else
        log "INFO" "使用bash后台进程实现并行备份 (jobs: $adjusted_jobs)"

        # 创建临时目录存储任务结果
        local temp_dir="${BACKUP_ROOT}/parallel_results_${TIMESTAMP}"
        mkdir -p "$temp_dir"
        # 确保临时目录在脚本退出时被清理
        trap 'rm -rf "$temp_dir"; trap - EXIT' EXIT

        # 对任务进行优先级排序
        local priority_tasks=()
        local normal_tasks=()
        for task in "${tasks[@]}"; do
            if [[ "$task" == "backup_system_config" || "$task" == "backup_user_config" ]]; then
                priority_tasks+=("$task")
            else
                normal_tasks+=("$task")
            fi
        done
        local sorted_tasks=("${priority_tasks[@]}" "${normal_tasks[@]}")

        # 启动任务，控制并行数量
        local pids=()
        local results=() # 存储每个任务的退出码
        local task_times=() # 存储每个任务的耗时
        local running=0
        local i=0

        while [ $i -lt $task_count ]; do
            # 检查系统负载 (简单检查)
            local current_load=$(awk '{print $1}' /proc/loadavg 2>/dev/null || echo "0")
            if (( $(echo "$current_load > $cpu_count * 0.8" | bc -l 2>/dev/null || echo "0") )); then
                log "WARN" "系统负载高 ($current_load)，暂停启动新任务 (5秒)"
                sleep 5
                continue
            fi

            # 检查当前运行的任务数量
            if [ $running -lt $adjusted_jobs ]; then
                local task_func=${sorted_tasks[$i]}
                local result_file="${temp_dir}/result_${i}.txt"
                local time_file="${temp_dir}/time_${i}.txt"

                # 记录任务开始时间
                date +%s > "$time_file"

                # 在后台执行任务并将退出码保存到文件
                # 使用子 shell ( ... ) 确保 trap 等不会相互干扰
                ( "$task_func"; echo $? > "$result_file" ) &
                pids+=($!)

                log "INFO" "启动任务 #$((i+1))/$task_count: $task_func (PID: ${pids[-1]})"

                running=$((running + 1))
                i=$((i + 1))
            else
                # 等待任意一个任务完成
                # 使用 wait -n 可以提高效率，但需要较新版本的 bash
                if command wait -n &>/dev/null; then
                    wait -n || true # 忽略 wait 本身的错误
                else
                    # 兼容旧版 bash，等待所有后台任务，效率较低
                    wait || true
                fi
                # 更新正在运行的任务数 (可能不止一个完成)
                current_running=0
                for pid in "${pids[@]}"; do
                    if kill -0 "$pid" 2>/dev/null; then
                        current_running=$((current_running + 1))
                    fi
                done
                running=$current_running
            fi
        done

        # 等待所有剩余任务完成
        log "INFO" "等待所有并行任务完成..."
        local wait_exit_code=0
        wait || wait_exit_code=$? # 等待所有后台 PID 完成
        if [ $wait_exit_code -ne 0 ] && [ $wait_exit_code -ne 127 ]; then # 忽略 "no child processes" 错误
             log "DEBUG" "Wait 命令退出码: $wait_exit_code"
        fi

        # 收集结果并计算时间
        local total_task_time=0
        for ((idx=0; idx<$task_count; idx++)); do
            local result_file="${temp_dir}/result_${idx}.txt"
            local time_file="${temp_dir}/time_${idx}.txt"
            local task_func=${sorted_tasks[$idx]}

            if [ -f "$result_file" ]; then
                local exit_code=$(cat "$result_file")
                results+=($exit_code)

                # 计算任务执行时间
                if [ -f "$time_file" ]; then
                    local task_start_time=$(cat "$time_file")
                    local task_end_time=$(date +%s) # 近似结束时间
                    local task_time=$((task_end_time - task_start_time))
                    task_times+=($task_time)
                    total_task_time=$((total_task_time + task_time))

                    if [ "$exit_code" -eq 0 ]; then
                        completed=$((completed + 1))
                        log "INFO" "任务 $task_func (#$((idx+1))) 成功完成，耗时: ${task_time}秒"
                    else
                        failed=$((failed + 1))
                        log "WARN" "任务 $task_func (#$((idx+1))) 失败，退出码: $exit_code，耗时: ${task_time}秒"
                    fi
                else
                    # 时间文件不存在，无法计算耗时
                    task_times+=(-1) # 标记无效时间
                    if [ "$exit_code" -eq 0 ]; then
                        completed=$((completed + 1))
                        log "INFO" "任务 $task_func (#$((idx+1))) 成功完成 (无法获取耗时)"
                    else
                        failed=$((failed + 1))
                        log "WARN" "任务 $task_func (#$((idx+1))) 失败，退出码: $exit_code (无法获取耗时)"
                    fi
                fi
            else
                log "ERROR" "任务 $task_func (#$((idx+1))) 的结果文件不存在"
                results+=(-1) # 标记失败
                task_times+=(-1)
                failed=$((failed + 1))
            fi
        done

        # 清理临时文件 (trap 会处理)
        # rm -rf "$temp_dir"

        # 计算总执行时间和并行效率
        local end_time=$(date +%s)
        local wall_time=$((end_time - start_time))
        local efficiency=0
        # 避免除以零
        if [ $wall_time -gt 0 ] && [ $adjusted_jobs -gt 0 ]; then
             # 效率 = (所有任务串行执行的总时间 / (实际墙上时间 * 使用的并行数)) * 100
             # 这里用 total_task_time 作为串行时间的近似值
             efficiency=$(( (total_task_time * 100) / (wall_time * adjusted_jobs) ))
             # 限制效率在 0-100 之间 (理论上可能超过100，如果任务时间计算不准或并行效果极好)
             [ $efficiency -lt 0 ] && efficiency=0
             [ $efficiency -gt 100 ] && efficiency=100 # 实际情况可能超过，但显示100%即可
        fi

        # 报告结果
        log "INFO" "并行备份完成: $completed 成功, $failed 失败, 总耗时: ${wall_time}秒, (近似)并行效率: ${efficiency}%"

        [ $failed -eq 0 ] && return 0 || return $failed
    fi
}

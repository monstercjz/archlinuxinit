# Enhanced Logging and Progress Module for Bash (`logs.sh`)

## 简介

`logs.sh` 是一个功能丰富的 Bash 脚本模块，旨在为其他 Bash 脚本提供强大的日志记录和进度显示功能。它提供了比标准 `echo` 更细粒度的控制，支持多种日志级别、彩色输出、文件日志记录（带轮转）、日志缓冲以及两种类型的进度条（包括 ETA 计算）。

该模块旨在通过 `source` 命令集成到其他脚本中，以增强其可观察性和用户体验。

## 特性

*   **多级日志记录**: 支持从 TRACE 到 FATAL 的 8 个日志级别。
*   **可配置日志级别**: 可以通过环境变量 `LOG_LEVEL` 设置当前脚本需要显示的最低日志级别。
*   **彩色控制台输出**: 根据日志级别使用不同的颜色高亮显示日志条目，可通过 `COLOR_OUTPUT=false` 禁用。
*   **文件日志记录**: 可选地将日志写入指定文件 (`LOG_TO_FILE=true`, `LOG_FILE`)。
*   **日志文件轮转**: 自动管理日志文件大小 (`LOG_FILE_MAX_SIZE`) 和保留数量 (`LOG_FILE_MAX_COUNT`)，防止日志文件无限增长。
*   **日志缓冲**: 将日志条目先写入内存缓冲区，达到一定大小 (`LOG_BUFFER_MAX_SIZE`) 或脚本结束时再写入文件，提高 I/O 性能。
*   **详细调用者信息**: 在 TRACE 和 DEBUG 级别，可选地显示调用日志函数的函数名和行号 (`VERBOSE=true`)。
*   **格式化日志**: 提供类似 `printf` 的日志函数 (`log_info_format`, `log_error_format` 等)。
*   **日志分段**: 使用 `log_section` 函数在日志中创建视觉分隔符，提高可读性。
*   **进度显示**:
    *   提供两种进度显示类型：条形图 (`PROGRESS_TYPE=bar`) 或百分比 (`PROGRESS_TYPE=percent`)。
    *   可通过 `SHOW_PROGRESS=false` 禁用。
    *   支持显示任务描述。
    *   支持计算并显示估计剩余时间 (ETA)，需要 `bc` 命令 (`show_progress_with_eta`)。
*   **环境变量配置**: 大部分行为可以通过环境变量进行配置，无需修改模块本身。
*   **自动清理**: 使用 `trap EXIT` 确保在脚本退出时刷新日志缓冲区并将结束标记写入日志文件。

## 如何使用

1.  **引入模块**: 在你的主脚本中使用 `source` 命令引入 `logs.sh`：
    ```bash
    #!/bin/bash

    # Source the logging module
    source path/to/logs.sh
    ```

2.  **初始化日志系统**: 在脚本开始执行主要逻辑之前，调用 `init_logging` 函数。这将根据环境变量设置日志级别、配置日志文件（如果启用）等。
    ```bash
    # Initialize the logging system
    init_logging
    ```

3.  **调用日志函数**: 使用提供的日志函数记录信息。
    ```bash
    log_trace "详细的跟踪信息..." # 仅当 LOG_LEVEL=TRACE 时显示
    log_debug "调试信息，变量值: $some_var" # 仅当 LOG_LEVEL <= DEBUG 时显示
    log_info "脚本开始执行。"
    log_notice "请注意，这个操作可能需要一些时间。"
    log_warn "配置文件未找到，使用默认设置。"
    log_error "无法连接到数据库。"
    log_critical "磁盘空间严重不足！"
    log_fatal "无法加载必要的库，脚本退出。"

    # 使用格式化日志
    user="Alice"
    count=5
    log_info_format "用户 '%s' 处理了 %d 个文件。" "$user" "$count"

    # 使用日志分段
    log_section "开始数据处理阶段"
    # ... 数据处理代码 ...
    log_section "数据处理完成" $LOG_LEVEL_NOTICE # 指定级别
    ```

4.  **调用进度显示函数**: 在执行长时间任务时，使用 `show_progress` 或 `show_progress_with_eta` 更新进度。

    *   **基本进度条/百分比**:
        ```bash
        total_items=100
        log_info "开始处理 $total_items 个项目..."
        for i in $(seq 1 $total_items); do
            # 模拟工作
            sleep 0.1
            # 更新进度 (当前值, 总值, 描述)
            show_progress "$i" "$total_items" "处理项目"
        done
        log_info "所有项目处理完成。"
        ```

    *   **带 ETA 的进度条/百分比**:
        ```bash
        total_items=50
        start_ts=$(date +%s) # 获取任务开始时间戳
        log_info "开始下载 $total_items 个文件..."
        for i in $(seq 1 $total_items); do
            # 模拟下载
            sleep 0.2
            # 更新进度 (当前值, 总值, 描述, 开始时间戳)
            show_progress_with_eta "$i" "$total_items" "下载文件" "$start_ts"
        done
        log_info "所有文件下载完成。"
        ```

5.  **自动清理**: 无需显式调用清理函数。`logs.sh` 内部使用 `trap finalize_logging EXIT` 来确保在脚本退出时（无论是正常结束还是因错误中断），日志缓冲区会被刷新到文件。

## 配置 (通过环境变量)

可以在运行脚本之前设置以下环境变量来自定义模块的行为：

| 环境变量              | 默认值             | 描述                                                                 |
| :-------------------- | :----------------- | :------------------------------------------------------------------- |
| `LOG_LEVEL`           | `INFO`             | 设置最低显示的日志级别 (TRACE, DEBUG, INFO, NOTICE, WARN, ERROR, CRITICAL, FATAL) |
| `COLOR_OUTPUT`        | `true`             | 是否启用控制台彩色输出 (`true` 或 `false`)                           |
| `LOG_TO_FILE`         | `false`            | 是否将日志写入文件 (`true` 或 `false`)                               |
| `LOG_FILE`            | `/tmp/script.log`  | 日志文件的路径 (当 `LOG_TO_FILE=true` 时生效)                        |
| `LOG_FILE_MAX_SIZE`   | `10485760` (10MB)  | 日志文件的最大大小（字节），超过后会进行轮转                           |
| `LOG_FILE_MAX_COUNT`  | `5`                | 日志文件轮转时保留的最大备份文件数量 (e.g., `.1`, `.2`, ..., `.5`) |
| `VERBOSE`             | `false`            | 是否在 TRACE/DEBUG 日志中显示调用者信息 (函数名:行号) (`true` 或 `false`) |
| `SHOW_PROGRESS`       | `true`             | 是否启用进度显示 (`true` 或 `false`)                                 |
| `PROGRESS_TYPE`       | `bar`              | 进度显示类型 (`bar` 或 `percent`)                                    |
| `LOG_BUFFER_MAX_SIZE` | `1024` (1KB)       | 日志文件缓冲区的最大大小（字节），达到后会刷新到文件                   |

**示例：**

```bash
# 运行脚本，设置日志级别为 DEBUG，并启用文件日志
export LOG_LEVEL=DEBUG
export LOG_TO_FILE=true
export LOG_FILE="/var/log/my_script.log"
./my_main_script.sh
```

## 日志级别

| 级别       | 数值 | 颜色 (默认) | 描述                                       |
| :--------- | :--- | :---------- | :----------------------------------------- |
| TRACE      | 0    | 亮蓝色      | 最详细的跟踪信息，用于深入调试             |
| DEBUG      | 1    | 蓝色        | 调试信息，用于开发和问题排查               |
| INFO       | 2    | 绿色        | 一般信息，报告脚本的正常运行状态           |
| NOTICE     | 3    | 亮青色      | 重要提示信息，需要用户注意但不一定是问题   |
| WARN       | 4    | 黄色        | 警告信息，表示可能存在的问题或潜在风险     |
| ERROR      | 5    | 红色        | 错误信息，表示发生了可恢复的错误           |
| CRITICAL   | 6    | 亮红色      | 严重错误信息，表示可能影响系统稳定性的错误 |
| FATAL      | 7    | 亮紫色      | 致命错误信息，表示脚本无法继续执行的严重错误 |

只有级别数值 **大于或等于** `CURRENT_LOG_LEVEL` (由 `LOG_LEVEL` 环境变量设置) 的日志才会被记录。

## 进度显示

*   **`bar` 类型**: 显示一个类似 `[=====>    ]` 的进度条。
*   **`percent` 类型**: 仅显示百分比，如 `Progress: 75%`。
*   **ETA (Estimated Time Remaining)**: `show_progress_with_eta` 函数会尝试计算并显示任务的估计剩余时间。这需要系统安装 `bc` 命令来进行浮点数运算。如果 `bc` 不可用，ETA 将显示为 "N/A (需要 bc)"。

## 依赖

*   **Bash**: 脚本是为 Bash shell 编写的。
*   **`date`**: 用于获取时间戳。
*   **`stat`**: 用于检查日志文件大小（兼容 Linux 和 macOS/BSD 版本）。
*   **`mkdir`**: 用于创建日志目录。
*   **`dirname`**: 用于获取日志文件的目录部分。
*   **`rm`, `mv`**: 用于日志文件轮转。
*   **`printf`**: 用于格式化输出。
*   **`bc` (可选)**: `show_progress_with_eta` 函数需要 `bc` 来计算 ETA。如果未使用此函数或不需要 ETA，则 `bc` 不是必需的。

## 示例脚本 (`example.sh`)

```bash
#!/bin/bash

# 假设 logs.sh 在同一目录下
source ./logs.sh

# 配置环境变量 (也可以在运行前 export)
export LOG_LEVEL="DEBUG"
export LOG_TO_FILE="true"
export LOG_FILE="./example.log"
export VERBOSE="true"
export PROGRESS_TYPE="bar"

# 初始化
init_logging

# --- 主要逻辑 ---
log_info "脚本开始运行"
log_debug "调试信息：当前用户是 $USER"

# 模拟一个需要一些时间的操作
total_steps=25
start_time=$(date +%s)
log_section "执行主要任务"
for i in $(seq 1 $total_steps); do
    log_trace_format "正在执行步骤 %d/%d" "$i" "$total_steps"
    sleep 0.1 # 模拟工作
    # 更新带 ETA 的进度
    show_progress_with_eta "$i" "$total_steps" "主要任务进度" "$start_time"
done
log_section "主要任务完成" $LOG_LEVEL_NOTICE

# 模拟另一个操作，使用百分比进度
total_files=10
log_info "开始处理文件..."
export PROGRESS_TYPE="percent" # 切换进度类型
for i in $(seq 1 $total_files); do
    sleep 0.2 # 模拟文件处理
    show_progress "$i" "$total_files" "处理文件"
done
log_info "文件处理完毕。"


# 记录一些不同级别的日志
log_warn "发现一个潜在配置问题。"
if [ ! -f "/non/existent/file" ]; then
    log_error "必需文件 /non/existent/file 未找到！"
fi

log_info "脚本执行完毕。"
# finalize_logging 会被 trap 自动调用

exit 0
```

运行示例:

```bash
chmod +x example.sh
./example.sh
```

检查 `example.log` 文件和控制台输出来查看日志和进度。

## todo
bc检查是否安装，如果未安装，如何处理 。

变量的默认值。

init_logging 函数完善。

日志文件写入时的换行符问题。

log_section 函数在日志文件中留下 ANSI 颜色代码的问题。
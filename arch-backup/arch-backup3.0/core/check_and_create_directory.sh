#!/bin/bash

# 定义一个通用函数来检查目录是否存在并可写
check_and_create_directory() {
    local dir_path="$1"
    # shell 约定 成功返回0，失败返回1
    if [ ! -d "$dir_path" ]; then
        log "DEBUG" "目录不存在: $dir_path，尝试创建..."
        if ! mkdir -p "$dir_path" 2>/dev/null; then
            log "FATAL" "无法创建目录: $dir_path，请检查权限"
            return 1
        else
            log "INFO" "成功创建目录: $dir_path"
        fi
    fi
    if [ ! -w "$dir_path" ]; then
        log "FATAL" "目录存在但不可写: $dir_path，请检查权限"
        return 1
    else
        log "INFO" "目录: $dir_path，存在且可写入"
        return 0
    fi
}

# 使用示例
# if check_and_create_directory "$BACKUP_ROOT"; then
#     log "INFO" "目录检查和创建成功，继续执行后续操作..."
#     # 在这里添加后续操作
# else
#     log "ERROR" "目录检查和创建失败，退出程序..."
#     exit 1
# fi
# 定义一个通用函数来检查目录是否存在并可写
# check_and_create_directory() {
#     local dir_path="$1"

#     if [ ! -d "$dir_path" ]; then
#         log "DEBUG" "目录不存在: $dir_path，尝试创建..."
#         if ! mkdir -p "$dir_path" 2>/dev/null; then
#             log "FATAL" "无法创建目录: $dir_path，请检查权限"
#             exit 1
#         else
#             log "INFO" "成功创建目录: $dir_path"
#         fi
#     elif [ ! -w "$dir_path" ]; then
#         log "FATAL" "目录存在但不可写: $dir_path，请检查权限"
#         exit 1
#     else
#         log "INFO" "目录: $dir_path，存在且可写入"
#     fi
# }

# 使用示例
# check_and_create_directory "$BACKUP_ROOT"
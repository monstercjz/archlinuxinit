#!/bin/bash

# 脚本功能：计算指定文件或目录的总大小、文件数量和目录数量
# 支持原始数值输出，方便其他脚本调用

# 启用更严格的错误处理
set -euo pipefail

# --- 默认值 ---
RAW_OUTPUT=false
TARGET_PATH=""

# --- 函数定义 ---

# 显示用法并退出
usage() {
  echo "用法: $0 [-r|--raw] <文件或目录路径>" >&2
  echo "选项:" >&2
  echo "  -r, --raw   输出原始数值 (大小以字节为单位)，每行一个值" >&2
  exit 1
}

# 计算并打印大小
calculate_size() {
  local path="$1"
  local size_bytes
  local size_human

  # 获取字节大小
  size_bytes=$(du -sb "$path" | cut -f1)
  if [ -z "$size_bytes" ]; then
    echo "错误：无法计算路径 '$path' 的大小。" >&2
    return 1
  fi

  if [ "$RAW_OUTPUT" = true ]; then
    echo "$size_bytes"
  else
    # 获取人类可读大小
    size_human=$(du -sh "$path" | cut -f1)
    echo "总大小: $size_human ($size_bytes 字节)"
  fi
}

# 计算并打印文件数量
count_files() {
  local path="$1"
  local count
  count=$(find "$path" -type f | wc -l)
  if [ "$RAW_OUTPUT" = true ]; then
    echo "$count"
  else
    echo "总文件数量: $count"
  fi
}

# 计算并打印目录数量
count_dirs() {
    local path="$1"
    local count
    # 减1是为了排除路径本身
    count=$(find "$path" -type d | wc -l)
    local dir_count=$((count - 1))
    if [ "$RAW_OUTPUT" = true ]; then
        echo "$dir_count"
    else
        echo "总目录数量: $dir_count"
    fi
}

# --- 参数解析 ---

# 检查是否有参数
if [ $# -eq 0 ]; then
  echo "错误：缺少参数。" >&2
  usage
fi

# 解析选项
if [[ "$1" == "-r" || "$1" == "--raw" ]]; then
  RAW_OUTPUT=true
  shift # 移除选项参数
  if [ $# -ne 1 ]; then
    echo "错误：选项 -r/--raw 后需要提供一个文件或目录路径。" >&2
    usage
  fi
  TARGET_PATH="$1"
else
  # 没有选项，第一个参数就是路径
  if [ $# -ne 1 ]; then
     echo "错误：需要提供一个文件或目录路径，或者使用 -r 选项。" >&2
     usage
  fi
  TARGET_PATH="$1"
fi


# --- 主逻辑 ---

# 检查路径是否存在
if [ ! -e "$TARGET_PATH" ]; then
  echo "错误：指定的路径不存在: $TARGET_PATH" >&2
  exit 1
fi

# 如果不是原始输出模式，打印分析路径信息
if [ "$RAW_OUTPUT" = false ]; then
    echo "分析路径: '$TARGET_PATH'"
fi

# 计算大小
calculate_size "$TARGET_PATH" || exit 1 # 如果计算大小失败则退出

# 根据路径类型处理文件和目录计数
if [ -d "$TARGET_PATH" ]; then
  count_files "$TARGET_PATH"
  count_dirs "$TARGET_PATH"
elif [ -f "$TARGET_PATH" ]; then
  if [ "$RAW_OUTPUT" = true ]; then
      echo "1" # 文件数
      echo "0" # 目录数
  else
      echo "总文件数量: 1 (这是一个文件)"
      echo "总目录数量: 0 (这是一个文件)"
  fi
fi

exit 0
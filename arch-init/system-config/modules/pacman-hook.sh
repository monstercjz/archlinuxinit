#!/bin/bash
# file: system-config/pacman-hook.sh

# --- 配置 ---
# 脚本的源目录，相对于此脚本自身的路径。
# SCRIPT_DIR 会被设置为 /path/to/your/repo/system-config/
# 所以源文件路径是 "${SCRIPT_DIR}/modules/pacman-hook-scripts"
SOURCE_BASE_DIR="pacman-hook-scripts"

DEST_BIN_DIR="/usr/local/bin"
DEST_HOOK_DIR="/etc/pacman.d/hooks"
# --- End 配置 ---

# 启用严格模式：
# -e: 任何命令失败时立即退出
# -u: 引用未设置的变量时报错
# -o pipefail: 管道中任何命令失败时，整个管道失败
set -euo pipefail

# 获取当前脚本的绝对路径的目录
# 无论从哪里调用此脚本，SCRIPT_DIR 都会正确指向 system-config/ 目录
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

# 组合出完整的源目录路径
FULL_SOURCE_DIR="${SCRIPT_DIR}/${SOURCE_BASE_DIR}"

# --- 函数定义 ---

# 检查是否以root用户运行
check_root() {
    if [[ "$EUID" -ne 0 ]]; then
        echo "错误: 此脚本必须以root用户运行。" >&2
        # 如果是被 system-config.sh 调用的，这里的 exit 会退出整个 system-config.sh 脚本
        exit 1
    fi
}

# 部署脚本文件 (需要可执行权限)
# 参数1: 源文件路径 (完整的绝对路径)
# 参数2: 目标目录
deploy_script() {
    local src_file="$1"
    local dest_dir="$2"
    local dest_name="$(basename "$src_file")" # 提取文件名
    local dest_path="${dest_dir}/${dest_name}"

    echo "正在部署脚本: ${src_file} 到 ${dest_path}"

    if [[ ! -f "$src_file" ]]; then
        echo "错误: 源脚本文件不存在: ${src_file}" >&2
        return 1 # 返回非零状态码，触发 set -e 退出
    fi

    cp -v "$src_file" "$dest_path" || { echo "错误: 复制脚本 ${src_file} 失败。" >&2; return 1; }
    chmod 755 "$dest_path" || { echo "错误: 设置脚本 ${dest_path} 执行权限失败。" >&2; return 1; }
    echo "成功部署脚本: ${dest_name}"
    return 0
}

# 部署pacman hook文件 (通常只需要可读权限)
# 参数1: 源文件路径 (完整的绝对路径)
# 参数2: 目标目录
deploy_hook() {
    local src_file="$1"
    local dest_dir="$2"
    local dest_name="$(basename "$src_file")" # 提取文件名
    local dest_path="${dest_dir}/${dest_name}"

    echo "正在部署Pacman Hook: ${src_file} 到 ${dest_path}"

    if [[ ! -f "$src_file" ]]; then
        echo "错误: 源Hook文件不存在: ${src_file}" >&2
        return 1 # 返回非零状态码
    fi

    cp -v "$src_file" "$dest_path" || { echo "错误: 复制Hook文件 ${src_file} 失败。" >&2; return 1; }
    # Pacman hooks通常不需要可执行权限，只需要可读权限 (644)
    chmod 644 "$dest_path" || { echo "错误: 设置Hook文件 ${dest_path} 权限失败。" >&2; return 1; }
    echo "成功部署Pacman Hook: ${dest_name}"
    return 0
}

# --- 主执行流程 ---

echo "--- 开始部署Pacman相关脚本和Hook ---"

check_root

# 确保源目录存在
if [[ ! -d "$FULL_SOURCE_DIR" ]]; then
    echo "错误: 源目录不存在或路径错误: ${FULL_SOURCE_DIR}" >&2
    echo "请确保脚本结构正确，或者更新脚本中的 SOURCE_BASE_DIR 变量。" >&2
    exit 1
fi

# 确保目标目录存在
echo "正在创建或验证目标目录..."
mkdir -p "$DEST_BIN_DIR" || { echo "错误: 无法创建目录 ${DEST_BIN_DIR}" >&2; exit 1; }
mkdir -p "$DEST_HOOK_DIR" || { echo "错误: 无法创建目录 ${DEST_HOOK_DIR}" >&2; exit 1; }
echo "目标目录已准备就绪。"

# 部署脚本到 /usr/local/bin
echo ""
echo "--- 部署可执行脚本 ---"
deploy_script "${FULL_SOURCE_DIR}/backup-manual_install_package-info.sh" "$DEST_BIN_DIR"
deploy_script "${FULL_SOURCE_DIR}/backup-pacman-info.sh" "$DEST_BIN_DIR"

# 部署Hook到 /etc/pacman.d/hooks
echo ""
echo "--- 部署Pacman Hook ---"
deploy_hook "${FULL_SOURCE_DIR}/backup-manual_install_package.hook" "$DEST_HOOK_DIR"
deploy_hook "${FULL_SOURCE_DIR}/backup-pkglist-log.hook" "$DEST_HOOK_DIR"

echo ""
echo "--- 所有Pacman相关脚本和Hook部署完成！ ---"
exit 0
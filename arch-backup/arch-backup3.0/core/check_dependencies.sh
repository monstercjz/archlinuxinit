#!/bin/bash

############################################################
# 检查外部命令依赖脚本
# 功能：检查项目运行所需的所有外部命令是否都存在于系统中。
############################################################

# --- 主检查函数 ---
# 返回值:
#   0 - 所有依赖都存在
#   1 - 缺少一个或多个依赖
check_dependencies() {
    # 核心依赖列表 (最可能需要用户安装的)
    local core_dependencies=(
        rsync
        bc
        awk
        numfmt
        du
        find
        wc
        stat
        df
    )
    # 扩展依赖列表 (通常系统自带，但为了完整性检查)
    local extended_dependencies=(
        mkdir
        basename
        dirname
        date
        readlink
        whoami
        cat
        tail
        xargs
        sleep
        pwd
        uname
        rm
        mv
        printf
        echo
        tee
    )

    local all_dependencies=("${core_dependencies[@]}" "${extended_dependencies[@]}")
    local missing_dependencies=()
    local dependency_found=true

    log_section "开始检查外部命令依赖" $LOG_LEVEL_INFO

    for cmd in "${all_dependencies[@]}"; do
        if ! command -v "$cmd" > /dev/null 2>&1; then
            log_error "依赖检查失败：命令 '$cmd' 未找到。"
            missing_dependencies+=("$cmd")
            dependency_found=false
        else
             log_debug "依赖检查通过：命令 '$cmd' 已找到。"
        fi
    done

    if ! $dependency_found; then
        log_fatal "缺少必要的外部命令: ${missing_dependencies[*]}. 请安装它们后重试。"
        # 提供一些常见的安装提示 (根据发行版可能不同)
        log_notice "常见安装命令提示:"
        log_notice "  - Arch/Manjaro: sudo pacman -S rsync bc awk coreutils findutils procps-ng"
        log_notice "  - Debian/Ubuntu: sudo apt install -y rsync bc gawk coreutils findutils procps"
        log_notice "  - Fedora: sudo dnf install -y rsync bc gawk coreutils findutils procps-ng"
        return 1
    else
        log_info "所有外部命令依赖检查通过。"
        return 0
    fi
}

# --- 直接执行块 (可选，主要用于测试) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 为了能独立测试，需要加载日志库
    _check_dep_script_dir=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
    _check_dep_core_dir="$_check_dep_script_dir" # 假设在 core 目录下
    _check_dep_logging_lib="$_check_dep_core_dir/loggings.sh"
    _check_dep_config_lib="$_check_dep_core_dir/config.sh" # loggings 可能需要 config

    if [ -f "$_check_dep_config_lib" ]; then
        . "$_check_dep_config_lib"
    else
        echo "错误：无法加载配置库 $_check_dep_config_lib" >&2
        # 即使没有配置，也尝试加载日志库
    fi

    if [ -f "$_check_dep_logging_lib" ]; then
        . "$_check_dep_logging_lib"
        # 尝试初始化日志，即使没有完整配置
        # 设置一些默认值以防万一
        : "${LOG_LEVEL:=INFO}"
        : "${COLOR_OUTPUT:=true}"
        : "${LOG_TO_FILE:=false}"
        init_logging # 初始化日志
    else
        echo "错误：无法加载日志库 $_check_dep_logging_lib，将使用 echo 输出。" >&2
        # 定义一个简单的 log 函数作为后备
        log_section() { echo "--- $1 ---"; }
        log_info() { echo "[INFO] $1"; }
        log_error() { echo "[ERROR] $1" >&2; }
        log_fatal() { echo "[FATAL] $1" >&2; }
        log_notice() { echo "[NOTICE] $1"; }
        log_debug() { echo "[DEBUG] $1"; }
    fi

    check_dependencies
    exit $?
fi
#!/bin/bash

# 日志记录函数
# 参数: $1: 日志级别 (INFO, WARN, ERROR, STEP)
# 参数: $2: 日志消息
log() {
    local level="$1"
    local message="$2"
    local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
    local color_reset="\e[0m"
    local color_info="\e[34m" # Blue
    local color_warn="\e[33m" # Yellow
    local color_error="\e[31m" # Red
    local color_step="\e[32m" # Green

    case "$level" in
        INFO)
            echo -e "${color_info}[${timestamp}] [INFO] ${message}${color_reset}"
            ;;
        WARN)
            echo -e "${color_warn}[${timestamp}] [WARN] ${message}${color_reset}"
            ;;
        ERROR)
            echo -e "${color_error}[${timestamp}] [ERROR] ${message}${color_reset}"
            ;;
        STEP)
            echo -e "\n${color_step}>>> [STEP] ${message}${color_reset}\n"
            ;;
        *)
            echo "[${timestamp}] ${message}"
            ;;
    esac
}

# 检查命令是否存在
# 参数: $1: 命令名称
# 返回: 0 如果存在, 1 如果不存在
command_exists() {
    command -v "$1" &> /dev/null
}

# 检测包管理器
# 返回: 包管理器命令 (pacman, apt, dnf, brew, yum) 或 "unknown"
detect_package_manager() {
    if command_exists pacman; then
        echo "pacman"
    elif command_exists apt-get; then
        echo "apt"
    elif command_exists dnf; then
        echo "dnf"
    elif command_exists brew; then
        echo "brew"
    elif command_exists yum; then
        echo "yum" # CentOS 旧版本
    else
        echo "unknown"
    fi
}

# 获取包管理器更新命令
# 参数: $1: 包管理器名称
get_update_command() {
    case "$1" in
        pacman) echo "sudo pacman -Syu --noconfirm" ;;
        apt) echo "sudo apt-get update" ;;
        dnf) echo "sudo dnf check-update" ;;
        brew) echo "brew update" ;;
        yum) echo "sudo yum check-update" ;;
        *) echo "" ;;
    esac
}

# 获取包管理器安装命令
# 参数: $1: 包管理器名称
# 参数: $@: 要安装的包列表 (从 $2 开始)
get_install_command() {
    local pm="$1"
    shift
    local packages="$@"
    case "$pm" in
        pacman) echo "sudo pacman -S --noconfirm --needed $packages" ;;
        apt) echo "sudo apt-get install -y $packages" ;;
        dnf) echo "sudo dnf install -y $packages" ;;
        brew) echo "brew install $packages" ;;
        yum) echo "sudo yum install -y $packages" ;;
        *) echo "" ;;
    esac
}

# 用户确认提示
# 参数: $1: 提示信息
# 返回: 0 如果用户确认 (y/Y), 1 如果用户取消 (n/N)
prompt_confirm() {
    local message="$1"
    local response
    while true; do
        read -p "$message [y/N]: " response
        case "$response" in
            [yY][eE][sS]|[yY])
                return 0
                ;;
            [nN][oO]|[nN]|"") # 默认为 No
                return 1
                ;;
            *)
                log WARN "请输入 'y' 或 'n'."
                ;;
        esac
    done
}

# 用户选择提示
# 参数: $1: 提示信息
# 参数: $@: 选项列表 (从 $2 开始)
# 返回: 用户选择的选项索引 (从 1 开始)
prompt_choice() {
    local message="$1"
    shift
    local options=("$@")
    local num_options=${#options[@]}
    local choice

    echo "$message"
    for i in "${!options[@]}"; do
        echo "  $(($i + 1)). ${options[$i]}"
    done

    while true; do
        read -p "请输入选项编号 (1-$num_options): " choice
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "$num_options" ]; then
            return "$choice"
        else
            log WARN "无效的输入，请输入 1 到 $num_options 之间的数字。"
        fi
    done
}

# 检查目录是否存在且为 Oh My Zsh 插件目录
# 参数: $1: 插件名称 (例如 zsh-syntax-highlighting)
is_omz_plugin_installed() {
    local plugin_name="$1"
    local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/${plugin_name}"
    [ -d "$plugin_dir" ] && [ -n "$(ls -A "$plugin_dir")" ]
}

# 检查 Powerlevel10k 主题是否存在
is_p10k_theme_installed() {
    local theme_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    [ -d "$theme_dir" ] && [ -f "${theme_dir}/powerlevel10k.zsh-theme" ]
}

# 检查字体是否可能已安装 (基于常见名称模式)
# 注意: 这只是一个启发式检查，不保证完全准确
# 参数: $1: 字体名称模式 (例如 MesloLGS)
is_font_installed_heuristic() {
    local font_pattern="$1"
    # 检查 Linux/macOS 的常见字体目录
    local font_dirs=(
        "$HOME/.local/share/fonts"
        "$HOME/.fonts"
        "/usr/local/share/fonts"
        "/usr/share/fonts"
        "/Library/Fonts" # macOS 系统字体
        "$HOME/Library/Fonts" # macOS 用户字体
    )
    for dir in "${font_dirs[@]}"; do
        if [ -d "$dir" ]; then
            # 使用 find 查找包含模式的文件名，忽略大小写
            if find "$dir" -iname "*${font_pattern}*" -print -quit | grep -q .; then
                return 0 # 找到匹配的字体文件
            fi
        fi
    done
    return 1 # 未找到
}

# 运行命令并记录日志
# 参数: $@: 要执行的命令及其参数
run_command() {
    log INFO "执行命令: $@"
    if "$@"; then
        log INFO "命令成功执行: $@"
        return 0
    else
        log ERROR "命令执行失败: $@"
        return 1
    fi
}

# 运行需要 sudo 的命令并记录日志
# 参数: $@: 要执行的命令及其参数
run_sudo_command() {
    log INFO "执行需要 sudo 的命令: $@"
    if sudo "$@"; then
        log INFO "命令成功执行: sudo $@"
        return 0
    else
        log ERROR "命令执行失败: sudo $@"
        return 1
    fi
}

# 备份文件
# 参数: $1: 要备份的文件路径
backup_file() {
    local filepath="$1"
    if [ -f "$filepath" ]; then
        local backup_path="${filepath}.backup_$(date +%Y%m%d_%H%M%S)"
        log INFO "备份文件 '$filepath' 到 '$backup_path'"
        if cp "$filepath" "$backup_path"; then
            log INFO "备份成功。"
            return 0
        else
            log ERROR "备份文件 '$filepath' 失败！"
            return 1
        fi
    elif [ -e "$filepath" ]; then
        log WARN "路径 '$filepath' 存在但不是一个普通文件，无法备份。"
        return 1
    else
        # log INFO "文件 '$filepath' 不存在，无需备份。"
        return 0 # 文件不存在，视为成功（无需操作）
    fi
}

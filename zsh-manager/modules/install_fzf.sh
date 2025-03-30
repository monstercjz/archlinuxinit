#!/usr/bin/env bash

# ███████╗███████╗███████╗    ████████╗ █████╗ ██████╗
# ╚══███╔╝╚══███╔╝╚══███╔╝    ╚══██╔══╝██╔══██╗██╔══██╗
#   ███╔╝   ███╔╝   ███╔╝        ██║   ███████║██████╔╝
#  ███╔╝   ███╔╝   ███╔╝         ██║   ██╔══██║██╔══██╗
# ███████╗███████╗███████╗       ██║   ██║  ██║██████╔╝
# ╚══════╝╚══════╝╚══════╝       ╚═╝   ╚═╝  ╚═╝╚═════╝
# fzf-tab自动化配置脚本 v2.1

set -euo pipefail
trap 'echo "脚本被中断，退出状态 $?" >&2; exit 1' INT TERM

# 颜色定义
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
RESET='\033[0m'

# 系统检测
OS_ID=$(grep -oP '^ID=\K\w+' /etc/os-release 2>/dev/null || echo "unknown")
ZSH_CUSTOM="${ZSH_CUSTOM:-${HOME}/.oh-my-zsh/custom}"

# 进度计数器
TOTAL_STEPS=5
CURRENT_STEP=1

# 美化输出函数
status_icon() {
    if [ $1 -eq 0 ]; then
        echo -e "${GREEN}✓${RESET}"
    else
        echo -e "${RED}✗${RESET}"
    fi
}

step_start() {
    echo -e "${BLUE}▶ 步骤 ${CURRENT_STEP}/${TOTAL_STEPS}: $1...${RESET}"
    ((CURRENT_STEP++))
}

step_detail() {
    echo -e "  ${YELLOW}▷${RESET} $1"
}

# 依赖安装函数（带详细输出）
install_dependencies() {
    step_start "系统依赖检查与安装"
    #OS_ID=$(grep -oP '^ID=\K\w+' /etc/os-release 2>/dev/null || echo "unknown")
    local install_cmd=()
    case $OS_ID in
        arch|manjaro)
            install_cmd=(sudo pacman -Sy --needed --noconfirm)
            packages=(zsh fzf bat eza)
            ;;
        debian|ubuntu|raspbian)
            step_detail "更新软件源"
            sudo apt-get update -q
            install_cmd=(sudo apt-get install -y -qq)
            packages=(zsh fzf bat eza)
            ;;
        fedora|centos|rhel)
            install_cmd=(sudo dnf install -y -q)
            packages=(zsh fzf bat eza)
            ;;
        *)
            echo -e "${RED}❌ 不支持的发行版: ${OS_ID}${RESET}"
            return 1
            ;;
    esac

    step_detail "正在安装: ${packages[*]}"
    if "${install_cmd[@]}" "${packages[@]}" > /dev/null; then
        echo -e "  ${GREEN}✔ 依赖安装成功${RESET}"
    else
        echo -e "  ${RED}✖ 依赖安装失败，退出码: $?${RESET}"
        return 1
    fi
}

# 检查前置条件（增强版）
check_prerequisites() {
    step_start "环境预检"

    step_detail "检查终端类型"
    if [[ $TERM != "xterm-256color" ]]; then
        echo -e "  ${YELLOW}⚠ 建议使用256色终端以获得最佳体验${RESET}"
    fi

    step_detail "检查必要命令"
    local missing=()
    for cmd in zsh git; do
        if ! command -v $cmd &>/dev/null; then
            missing+=("$cmd")
        fi
    done

    if (( ${#missing[@]} > 0 )); then
        echo -e "  ${RED}✖ 缺失关键依赖: ${missing[*]}${RESET}"
        return 1
    else
        echo -e "  ${GREEN}✔ 基础依赖就绪${RESET}"
    fi

    step_detail "验证Oh My Zsh安装"
    if [[ ! -d "${HOME}/.oh-my-zsh" ]]; then
        echo -e "  ${RED}✖ 未找到Oh My Zsh${RESET}"
        echo -e "${YELLOW}建议执行官方安装命令："
        echo 'sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"'
        echo -e "${RESET}"
        return 1
    fi
}

# 安装fzf-tab插件（带进度反馈）
install_fzf_tab() {
    step_start "插件部署"
    local plugin_dir="${ZSH_CUSTOM}/plugins/fzf-tab"

    if [[ -d "$plugin_dir" ]]; then
        step_detail "检测到现存安装，尝试更新..."
        if git -C "$plugin_dir" pull --rebase 2>&1 | while read line; do
            echo -e "  ${BLUE}▌${RESET} ${line}";
        done; then
            echo -e "  ${GREEN}✔ 更新成功 (当前提交: $(git -C "$plugin_dir" log -1 --pretty=format:'%h'))${RESET}"
        else
            echo -e "  ${RED}✖ 更新失败，错误码: $?${RESET}"
            return 1
        fi
    else
        step_detail "克隆仓库到: ${plugin_dir}"
        if git clone --progress https://github.com/Aloxaf/fzf-tab.git "$plugin_dir" 2>&1 | while read line; do
            echo -e "  ${BLUE}▌${RESET} ${line}";
        done; then
            echo -e "  ${GREEN}✔ 克隆完成 (版本: $(git -C "$plugin_dir" describe --tags))${RESET}"
        else
            echo -e "  ${RED}✖ 克隆失败，请检查网络或权限${RESET}"
            return 1
        fi
    fi
}

# 配置Zshrc（带差异对比）
configure_zshrc() {
    step_start "个性化配置"
    local zshrc="${HOME}/.zshrc"
    local backup="${zshrc}.bak-$(date +%s)"

    step_detail "备份原配置 → ${backup}"
    cp "$zshrc" "$backup" || {
        echo -e "  ${RED}✖ 备份失败，请检查权限${RESET}"
        return 1
    }

    step_detail "注入插件配置"
    if ! grep -q "plugins=.*fzf-tab" "$zshrc"; then
        sed -i "s/^plugins=(\(.*\))/plugins=(\1 fzf-tab)/" "$zshrc"
        echo -e "  ${GREEN}✔ 插件列表更新${RESET}"
        echo -e "${YELLOW}修改差异:"
        diff --color=always -u "$backup" "$zshrc" | grep -E '^\+' | tail -n +3
        echo -e "${RESET}"
    else
        echo -e "  ${BLUE}ℹ 插件已存在配置中${RESET}"
    fi

    step_detail "应用性能优化"
    if ! grep -q "# fzf-tab configuration" "$zshrc"; then
        cat <<-EOF >> "$zshrc"

		# fzf-tab configuration
		zstyle ':fzf-tab:*' fzf-flags --height=60% --border
		zstyle ':fzf-tab:complete:*:*' fzf-preview '\
		  (bat --color=always --line-range :500 \$realpath 2>/dev/null || \
		   exa -al --git --icons \$realpath || \
		   ls -lAh --color=always \$realpath) 2>/dev/null'
		zstyle ':completion:*' max-matches 5000
		zstyle ':completion:*' use-cache on
		zstyle ':completion:*' cache-path ~/.cache/zsh/.zcompcache
		EOF
        echo -e "  ${GREEN}✔ 配置注入完成${RESET}"
    else
        echo -e "  ${BLUE}ℹ 检测到现有配置，保留原设置${RESET}"
    fi
}

# 安装后验证
post_validation() {
    step_start "最终验证"

    step_detail "检查插件加载"
    if zsh -i -c 'echo ${plugins[(I)fzf-tab]}' | grep -q fzf-tab; then
        echo -e "  ${GREEN}✔ 插件已正确加载${RESET}"
    else
        echo -e "  ${RED}✖ 插件加载失败${RESET}"
        return 1
    fi

    step_detail "测试补全功能"
    if zsh -i -c 'type _fzf_tab_main' &>/dev/null; then
        echo -e "  ${GREEN}✔ 补全系统正常${RESET}"
    else
        echo -e "  ${RED}✖ 补全功能异常${RESET}"
        return 1
    fi
}

main() {
    check_prerequisites || exit 1
    install_dependencies || exit 2
    install_fzf_tab || exit 3
    configure_zshrc || exit 4
    post_validation || exit 5

    echo -e "\n${GREEN}✅ 所有步骤已完成！耗时: ${SECONDS}秒${RESET}"
    echo -e "请执行以下命令立即生效:"
    echo -e "  ${BLUE}source ~/.zshrc${RESET}\n"
}

main "$@"

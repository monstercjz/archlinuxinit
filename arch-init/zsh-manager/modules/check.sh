#!/bin/bash
source "$(dirname "$0")/core/config.sh"
source "$(dirname "$0")/core/utils.sh"

check_environment() {
    clear
    echo -e "${CYAN}============= 系统环境检查 =============${NC}"
    
    # 1. 检查Zsh本体
    local zsh_path=$(command -v zsh)
    if [[ -n "$zsh_path" ]]; then
        local zsh_version=$(zsh --version 2>&1 | awk '{print $2}')
        show_status "info" "Zsh 已安装 (版本: ${GREEN}${zsh_version}${NC})"
    else
        show_status "error" "Zsh 未安装"
    fi

    # 2. 检查默认Shell
    echo -ne "当前默认 Shell: "
    if [[ $(basename "$SHELL") == "zsh" ]]; then
        echo -e "${GREEN}$SHELL${NC}"
    else
        echo -e "${YELLOW}$SHELL (建议使用Zsh)${NC}"
    fi

    # 3. 检查Oh My Zsh
    echo -ne "Oh My Zsh 状态: "
    if [[ -d "$HOME/.oh-my-zsh" ]]; then
        local omz_version=$(cd ~/.oh-my-zsh && git describe --tags 2>/dev/null)
        show_status "info" "已安装 (版本: ${GREEN}${omz_version}${NC})"
    else
        show_status "error" "未安装"
    fi

    # 4. 检查Powerlevel10k
    echo -ne "Powerlevel10k 状态: "
    p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ -d "$p10k_dir" ]]; then
        show_status "info" "已安装"
    else
        show_status "error" "未安装"
    fi

    # 5. 检查插件
    declare -A plugins=(
        ["语法高亮"]="zsh-syntax-highlighting"
        ["自动建议"]="zsh-autosuggestions"
    )
    echo "插件状态:"
    for name in "${!plugins[@]}"; do
        plugin=${plugins[$name]}
        path="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
        echo -ne "  ${CYAN}$name: ${NC}"
        [[ -d "$path" ]] && echo -e "${GREEN}已安装${NC}" || echo -e "${RED}未安装${NC}"
    done

    # 6. 检查字体
    echo -ne "Meslo 字体状态: "
    if fc-list | grep -qi "MesloLGS NF"; then
        show_status "info" "已安装"
    else
        show_status "error" "未安装"
    fi

    # 7. 终端配置提醒
    echo -e "${YELLOW}\n请手动检查终端字体设置:"
    echo -e "  1. 打开终端设置 → 外观"
    echo -e "  2. 选择 'MesloLGS NF' 字体"
    echo -e "  3. 重启终端应用${NC}"

    echo -e "${CYAN}========================================${NC}"
}
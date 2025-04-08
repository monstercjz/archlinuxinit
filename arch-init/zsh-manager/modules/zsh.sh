#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$SOURCE_DIR/core/utils.sh"


manage_zsh() {

    local operation=$1

    

    case $operation in

        "install")
            # 检查是否已安装
            if command -v zsh &> /dev/null; then
                local zsh_version=$(zsh --version 2>&1 | awk '{print $2}')
                show_status "info" "Zsh 已安装 (版本: ${GREEN}${zsh_version}${NC})"
                
                echo -ne "${YELLOW}是否强制重新安装？[y/N] ${NC}"
                read -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    show_status "info" "跳过安装"
                    return 0
                fi
            fi

            show_status "info" "开始安装 Zsh"

            sudo pacman -S --needed zsh || return 1

            

            if [[ $SHELL != */zsh ]]; then

                chsh -s /bin/zsh && \

                show_status "success" "默认 Shell 已设置为 Zsh" || \

                show_status "error" "修改默认 Shell 失败"

            fi

            ;;

            

        "uninstall")

            confirm_action "uninstall" "Zsh" || return 0

            

            show_status "info" "开始卸载 Zsh"

            
            # 恢复默认的 zsh 配置（如果 zsh 之前是默认 shell）
            if [[ $SHELL == */zsh ]]; then
                chsh -s /bin/bash && \
                show_status "success" "默认 Shell 已恢复为 Bash" || \
                show_status "error" "恢复 Shell 失败"
            else
                show_status "info" "默认 Shell 已经是 Bash"
            fi
            sudo pacman -Rns zsh

            ;;

    esac

}

# 执行示例：manage_zsh "install"

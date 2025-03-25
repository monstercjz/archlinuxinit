#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$SOURCE_DIR/core/utils.sh"


OMZ_DIR="$HOME/.oh-my-zsh"


manage_omz() {

    local operation=$1

    case $operation in

        "install")

            show_status "info" "开始安装 Oh My Zsh"

            [ -d "$OMZ_DIR" ] && {
                show_status "info" "Oh My Zsh 已存在"
                
                echo -ne "${YELLOW}是否强制重新安装？[y/N] ${NC}"
                read -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    show_status "info" "跳过安装"
                    return 0
                else
                    # 如果用户选择重新安装，先删除现有安装
                    rm -rf "$OMZ_DIR"
                    show_status "info" "已删除现有安装，准备重新安装"
                fi
            }

            sh -c "$(curl -fsSL https://raw.github.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended && \
            show_status "success" "安装完成" || \
            show_status "error" "安装失败"

            ;;

        "uninstall")

            confirm_action "uninstall" "Oh My Zsh" || return 0

            show_status "info" "开始卸载 Oh My Zsh"

            # 删除 Oh My Zsh 安装目录
            if [ -d "$OMZ_DIR" ]; then
                rm -rf "$OMZ_DIR"
                show_status "info" "已删除 Oh My Zsh 安装目录"
            else
                show_status "info" "未找到 Oh My Zsh 安装目录"
            fi

            # 删除 ~/.zshrc 文件中与 Oh My Zsh 相关的配置
            # if [ -f "$ZSHRC" ]; then
            #     sed -i '/^plugins=/d' "$ZSHRC"
            #     sed -i '/^source ~\/.oh-my-zsh\/zshrc/d' "$ZSHRC"
            #     sed -i '/# oh-my-zsh/d' "$ZSHRC"
            #     show_status "info" "已清理 ~/.zshrc 文件中的 Oh My Zsh 配置"
            # else
            #     show_status "info" "未找到 ~/.zshrc 文件"
            # fi

            # 恢复默认的 ~/.zshrc 文件（如果存在备份）
            if [ -f "$ZSHRC.pre-oh-my-zsh" ]; then
                echo "正在备份 ~/.zshrc 文件...到 /home/cjz/.zshrc.bak"
                cp "$ZSHRC" "$ZSHRC.bak"
                echo "正在恢复默认的 ~/.zshrc 文件...从 /home/cjz/.zshrc.pre-oh-my-zsh"
                mv "$ZSHRC.pre-oh-my-zsh" "$ZSHRC"
                show_status "info" "已恢复默认的 ~/.zshrc 文件"
            fi

            # 恢复默认的 zsh 配置（如果 zsh 之前是默认 shell）
            # if [[ $SHELL == */zsh ]]; then
            #     chsh -s /bin/bash && \
            #     show_status "success" "默认 Shell 已恢复为 Bash" || \
            #     show_status "error" "恢复 Shell 失败"
            # else
            #     show_status "info" "默认 Shell 已经是 Bash"
            # fi

            # show_status "success" "卸载完成"

            ;;

    esac

}

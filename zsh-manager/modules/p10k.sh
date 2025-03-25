#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$SOURCE_DIR/core/utils.sh"


P10K_DIR="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"


manage_p10k() {

    local operation=$1

    

    case $operation in

        "install")

            show_status "info" "开始安装 Powerlevel10k"

            [ -d "$P10K_DIR" ] && {
                show_status "info" "Powerlevel10k 已存在"
                
                echo -ne "${YELLOW}是否强制重新安装？[y/N] ${NC}"
                read -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    show_status "info" "跳过安装"
                    return 0
                else
                    # 如果用户选择重新安装，先删除现有安装
                    rm -rf "$P10K_DIR"
                    show_status "info" "已删除现有安装，准备重新安装"
                fi
            }

            

            git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$P10K_DIR" && \

            sed -i 's/^ZSH_THEME=.*/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "$ZSHRC" && \

            show_status "success" "安装完成！运行 p10k configure 初始化配置" || \

            show_status "error" "安装失败"

            ;;

            

        "uninstall")

            confirm_action "uninstall" "Powerlevel10k" || return 0

            show_status "info" "开始卸载 Powerlevel10k"

            # 删除 Powerlevel10k 安装目录
            if [ -d "$P10K_DIR" ]; then
                rm -rf "$P10K_DIR"
                show_status "info" "已删除 Powerlevel10k 安装目录"
            else
                show_status "info" "未找到 Powerlevel10k 安装目录"
            fi

            # 删除 ~/.zshrc 文件中与 Powerlevel10k 相关的配置
            # if [ -f "$ZSHRC" ]; then
            #      删除 ZSH_THEME 配置行
            #     sed -i '/^ZSH_THEME="powerlevel10k/d' "$ZSHRC"
            #      删除 Powerlevel10k 即时提示初始化代码块
            #     sed -i '/^\[\[ ! -f ~/.p10k.zsh \]\] || source ~/.p10k.zsh/d' "$ZSHRC" # 这句代码有错
            #     sed -i '/^if \[\[ -r "${XDG_CACHE_HOME:-\$HOME\/.cache}\/p10k-instant-prompt-\${(%):-%n}.zsh" \]\]; then/d' "$ZSHRC"
            #     sed -i '/^  source "${XDG_CACHE_HOME:-\$HOME\/.cache}\/p10k-instant-prompt-\${(%):-%n}.zsh"/d' "$ZSHRC"
            #     sed -i '/^fi/d' "$ZSHRC"
            #     show_status "info" "已清理 ~/.zshrc 文件中的 Powerlevel10k 配置"
            # else
            #     show_status "info" "未找到 ~/.zshrc 文件"
            # fi
             # 删除 ~/.zshrc 文件中与 Powerlevel10k 相关的配置
            if [ -f "$ZSHRC" ]; then
                # 删除 ZSH_THEME 配置行
                sed -i '/^ZSH_THEME="powerlevel10k/d' "$ZSHRC"
                # 删除 Powerlevel10k 即时提示初始化代码块
                sed -i '/^\[\[ ! -f ~\/.p10k\.zsh \]\] || source ~\/.p10k\.zsh/d' "$ZSHRC"
                sed -i '/^if \[\[ -r "${XDG_CACHE_HOME:-\$HOME\/.cache}\/p10k-instant-prompt-\${(%):-%n}\.zsh" \]\]; then/d' "$ZSHRC"
                sed -i '/^  source "${XDG_CACHE_HOME:-\$HOME\/.cache}\/p10k-instant-prompt-\${(%):-%n}\.zsh"/d' "$ZSHRC"
                sed -i '/^fi/d' "$ZSHRC"
                show_status "info" "已清理 ~/.zshrc 文件中的 Powerlevel10k 配置"
            else
                show_status "info" "未找到 ~/.zshrc 文件"
            fi
            # 删除 Powerlevel10k 配置文件
            P10K_CONFIG="$HOME/.p10k.zsh"
            if [ -f "$P10K_CONFIG" ]; then
                cp "$P10K_CONFIG" "$P10K_CONFIG.bak"
                rm -v "$P10K_CONFIG"
                show_status "info" "已删除 Powerlevel10k 配置文件"
            else
                show_status "info" "未找到 Powerlevel10k 配置文件"
            fi

            show_status "success" "卸载完成"

            ;;

    esac

}

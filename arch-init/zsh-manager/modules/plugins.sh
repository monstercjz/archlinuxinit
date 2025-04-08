#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$SOURCE_DIR/core/utils.sh"

declare -A PLUGINS=(
    ["zsh-syntax-highlighting"]="https://github.com/zsh-users/zsh-syntax-highlighting.git"
    ["zsh-autosuggestions"]="https://github.com/zsh-users/zsh-autosuggestions"
)

manage_plugins() {
    local operation=$1

    case $operation in

        "install")

            show_status "info" "开始安装插件"

            # 检查是否已安装任何插件
            local any_plugin_installed=false
            for plugin in "${!PLUGINS[@]}"; do
                local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
                if [ -d "$plugin_dir" ]; then
                    any_plugin_installed=true
                    break
                fi
            done

            # 如果已安装任何插件，询问是否重新安装
            if $any_plugin_installed; then
                show_status "info" "部分或全部插件已存在"

                echo -ne "${YELLOW}是否强制重新安装所有插件？[y/N] ${NC}"
                read -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    show_status "info" "跳过安装"
                    return 0
                else
                    # 如果用户选择重新安装，先删除现有安装
                    for plugin in "${!PLUGINS[@]}"; do
                        local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
                        [ -d "$plugin_dir" ] && rm -rf "$plugin_dir"
                    done
                    show_status "info" "已删除现有安装，准备重新安装"
                fi
            fi

            for plugin in "${!PLUGINS[@]}"; do
                local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
                [ -d "$plugin_dir" ] && continue

                show_status "info" "正在安装 $plugin"

                git clone "${PLUGINS[$plugin]}" "$plugin_dir" || {
                    show_status "error" "$plugin 安装失败"
                    continue
                }

            done

            # 读取当前的 plugins 配置
            local plugins_line=$(grep '^plugins=(' "$ZSHRC")
            if [[ -n "$plugins_line" ]]; then
                # 去掉 plugins=( 和 )，并将插件名称提取到数组中
                local plugins_content=$(echo "$plugins_line" | sed -E 's/^plugins=\((.*)\)/\1/')
                IFS=' ' read -r -a current_plugins <<< "$plugins_content"
            else
                # 如果没有找到 plugins=，则初始化为空数组
                current_plugins=()
            fi

            # 添加新的插件到数组中
            for plugin in "${!PLUGINS[@]}"; do
                if [[ ! " ${current_plugins[@]} " =~ " ${plugin} " ]]; then
                    current_plugins+=("$plugin")
                fi
            done

            # 更新 plugins 配置
            local updated_plugins_line="plugins=(${current_plugins[*]})"
            # 替换旧的 plugins 配置行
            if [[ -n "$plugins_line" ]]; then
                sed -i "s/^plugins=(.*)/$updated_plugins_line/" "$ZSHRC"
            else
                echo "$updated_plugins_line" >> "$ZSHRC"
            fi

            show_status "success" "插件配置已更新"

            ;;

        "uninstall")

            confirm_action "uninstall" "所有插件" || return 0

            show_status "info" "开始卸载插件"

            for plugin in "${!PLUGINS[@]}"; do
                local plugin_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/$plugin"
                if [ -d "$plugin_dir" ]; then
                    rm -rf "$plugin_dir"
                    show_status "info" "已移除 $plugin"
                fi
            done

            # 读取当前的 plugins 配置
            local plugins_line=$(grep '^plugins=(' "$ZSHRC")
            if [[ -n "$plugins_line" ]]; then
                # 去掉 plugins=( 和 )，并将插件名称提取到数组中
                # 替换原有字符串处理逻辑
                local plugins_content=$(echo "$plugins_line" | sed -E 's/^plugins=\((.*)\)/\1/')
                IFS=' ' read -r -a current_plugins <<< "$plugins_content"
                # 移除已卸载的插件
                for plugin in "${!PLUGINS[@]}"; do
                    current_plugins=("${current_plugins[@]/$plugin}")
                done
                # 更新 plugins 配置
                local updated_plugins_line="plugins=(${current_plugins[*]})"
                # 替换旧的 plugins 配置行
                sed -i "s/^plugins=(.*)/$updated_plugins_line/" "$ZSHRC"
            fi

            show_status "success" "插件配置已清理"

            ;;

    esac
}

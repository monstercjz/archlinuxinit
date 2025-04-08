#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$SOURCE_DIR/core/utils.sh"


FONT_NAME="MesloLGS NF"

FONT_URL="https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf"

FONT_DIR="/usr/share/fonts"


manage_fonts() {

    local operation=$1

    

    case $operation in

        "install")

            show_status "info" "开始安装字体"

            [ -f "$FONT_DIR/MesloLGS NF Regular.ttf" ] && {
                show_status "info" "字体已存在"
                
                echo -ne "${YELLOW}是否强制重新安装？[y/N] ${NC}"
                read -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    show_status "info" "跳过安装"
                    return 0
                else
                    # 如果用户选择重新安装，先删除现有安装
                    sudo rm -f "$FONT_DIR"/MesloLGS*
                    show_status "info" "已删除现有安装，准备重新安装"
                fi
            }

            

            # mkdir -p "$FONT_DIR"

            # wget -qO "$FONT_DIR/MesloLGS NF Regular.ttf" "$FONT_URL" && \
            wget https://github.com/romkatv/powerlevel10k-media/raw/master/MesloLGS%20NF%20Regular.ttf
            sudo mv MesloLGS*.ttf /usr/share/fonts/

            fc-cache -f -v && \

            show_status "success" "安装完成！请手动设置终端字体" || \

            show_status "error" "字体安装失败"

            ;;

            

        "uninstall")

            confirm_action "uninstall" "Meslo 字体" || return 0

            

            show_status "info" "开始卸载字体"

            rm -f "$FONT_DIR"/MesloLGS* && \

            fc-cache -f -v && \

            show_status "success" "字体已移除，请手动重置终端字体" || \

            show_status "error" "字体移除失败"

            ;;

    esac

}

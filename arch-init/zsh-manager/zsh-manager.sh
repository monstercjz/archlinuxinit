#!/bin/bash

SCRIPT_DIRS=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

echo "调试信息 - 当前脚本目录: $SCRIPT_DIRS"
ORIGINAL_SCRIPT_DIRS="$SCRIPT_DIRS"
if [ -f "$SCRIPT_DIRS/core/config.sh" ]; then
    source "$SCRIPT_DIRS/core/config.sh"
    echo "已加载配置文件路径: $SCRIPT_DIRS/core/config.sh"
else
    echo "错误：配置文件不存在于 $SCRIPT_DIRS/core/config.sh"
fi
SCRIPT_DIRS="$ORIGINAL_SCRIPT_DIRS"

ORIGINAL_SCRIPT_DIRS="$SCRIPT_DIRS"
if [ -f "$SCRIPT_DIRS/core/utils.sh" ]; then
    source "$SCRIPT_DIRS/core/utils.sh"
    echo "已加载工具函数库: $SCRIPT_DIRS/core/utils.sh"
else
    echo "错误：工具函数库不存在于 $SCRIPT_DIRS/core/utils.sh"
fi
SCRIPT_DIRS="$ORIGINAL_SCRIPT_DIRS"


show_menu() {

    clear

    echo -e "${CYAN}Zsh 环境管理终端 v5.0${NC}"

    echo -e "${GREEN}1. 安装组件  2. 卸载组件  3. 系统检查  4. 备份管理  0. 退出${NC}"

}


manage_component() {

    local component=$1

    local operation=$2

    

    case $component in

        "zsh") source "$SCRIPT_DIRS/modules/zsh.sh"; manage_zsh $operation ;;

        "omz") source "$SCRIPT_DIRS/modules/omz.sh"; manage_omz $operation ;;

        "p10k") source "$SCRIPT_DIRS/modules/p10k.sh"; manage_p10k $operation ;;

        "plugins") source "$SCRIPT_DIRS/modules/plugins.sh"; manage_plugins $operation ;;

        "fonts") source "$SCRIPT_DIRS/modules/fonts.sh"; manage_fonts $operation ;;

        *) show_status "error" "未知组件: $component" ;;

    esac

}


while true; do

    show_menu

    read -p "请输入操作编号: " choice

    

    case $choice in

        1) 

            read -p "选择要安装的组件 (zsh/omz/p10k/plugins/fonts/all): " comp

            [ "$comp" = "all" ] && comp="zsh omz p10k plugins fonts"

            for c in $comp; do

                manage_component "$c" "install"

            done

            ;;

        2)

            read -p "选择要卸载的组件 (zsh/omz/p10k/plugins/fonts/all): " comp 

            [ "$comp" = "all" ] && comp="zsh omz p10k plugins fonts"

            for c in $comp; do

                manage_component "$c" "uninstall"

            done

            ;;

        3) 
            source "$SCRIPT_DIRS/modules/check.sh"
            check_environment
            ;;
            
        4)
            
            # 定义SOURCE_DIR变量，确保正确引用backup.sh
            SOURCE_DIR=$SCRIPT_DIRS
            # 确保使用正确的相对路径引用backup.sh
            source "$SOURCE_DIR/modules/backup.sh"
            echo -e "${GREEN}1. 创建备份  2. 恢复备份  3. 列出备份  4. 删除备份  0. 返回${NC}"
            read -p "请选择操作: " backup_op
            
            case $backup_op in
                1) manage_backup "backup" ;;
                2) manage_backup "restore" ;;
                3) manage_backup "list" ;;
                4) manage_backup "delete" ;;
                0) continue ;;
                *) show_status "error" "无效选项" ;;
            esac
            ;;
            
        0) exit 0 ;;

        *) show_status "error" "无效选项" ;;

    esac

    

    read -n 1 -s -r -p "按任意键继续..."

done

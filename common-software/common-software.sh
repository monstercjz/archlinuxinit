#!/bin/bash

# common-software/common-software.sh

common_software_menu() {
  echo "常用软件菜单"
  echo "1. 必备软件"
  echo "2. 其他软件"
  echo "b. 返回主菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) essential_software_menu ;;
    2) other_software_menu ;;
    b) main_menu ;;
    *) echo "无效选择" ;;
  esac
}

essential_software_menu() {
  echo "必备软件菜单"
  echo "1. 安装 VSCode"
  echo "2. 安装 RustDesk"
  echo "3. 安装 Edge 浏览器"
  echo "b. 返回常用软件菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) bash common-software/modules/essential.sh vscode ;; # 假设 essential.sh 接受参数 vscode
    2) bash common-software/modules/essential.sh rustdesk ;; # 假设 essential.sh 接受参数 rustdesk
    3) bash common-software/modules/essential.sh edge ;; # 假设 essential.sh 接受参数 edge
    b) common_software_menu ;;
    *) echo "无效选择" ;;
  esac
}

other_software_menu() {
  echo "其他软件菜单"
  echo "敬请期待..."
  common_software_menu
}

common_software_menu
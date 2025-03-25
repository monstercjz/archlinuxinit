#!/bin/bash

# common-software/modules/essential.sh

ESSENTIAL_SOFTWARE_MENU() {
  echo "必备软件菜单"
  echo "1. 安装 VSCode"
  echo "2. 安装 RustDesk"
  echo "3. 安装 Edge 浏览器"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_vscode ;;
    2) install_rustdesk ;;
    3) install_edge ;;
    b) exit 0 ;; # 返回 common_software_menu，由 common-software.sh 处理
    *) echo "无效选择" ;;
  esac
}

install_vscode() {
  echo "正在安装 VSCode..."
  # 使用 pacman 安装 vscode
  sudo pacman -S code --noconfirm
  echo "VSCode 安装完成"
  ESSENTIAL_SOFTWARE_MENU
}

install_rustdesk() {
  echo "正在安装 RustDesk..."
  # 使用 yay 安装 rustdesk
  yay -S rustdesk --noconfirm
  echo "RustDesk 安装完成"
  ESSENTIAL_SOFTWARE_MENU
}

install_edge() {
  echo "正在安装 Edge 浏览器..."
  # 使用 yay 安装 microsoft-edge-stable
  yay -S microsoft-edge-stable --noconfirm
  echo "Edge 浏览器安装完成"
  ESSENTIAL_SOFTWARE_MENU
}

ESSENTIAL_SOFTWARE_MENU
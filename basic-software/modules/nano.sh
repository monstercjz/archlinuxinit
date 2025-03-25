#!/bin/bash

# basic-software/modules/nano.sh

NANO_INSTALL() {
  echo "安装 nano 菜单"
  echo "1. 安装 nano"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_nano_editor ;;
    b) exit 0 ;; # 返回 basic_software_menu，由 basic-software.sh 处理
    *) echo "无效选择" ;;
  esac
}

install_nano_editor() {
  echo "正在安装 nano..."
  if pacman -Q nano &>/dev/null; then
    echo "nano 已经安装"
  else
    # 使用 pacman 安装 nano
    sudo pacman -S nano --noconfirm
    echo "nano 安装完成"
  fi
  NANO_INSTALL
}

NANO_INSTALL
#!/bin/bash

# basic-software/modules/aur-helper.sh

AUR_HELPER_MENU() {
  echo "安装 AUR 助手菜单"
  echo "1. 安装 yay"
  echo "2. 安装 paru"
  echo "3. 安装 octopi"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_yay ;;
    2) install_paru ;;
    3) install_octopi ;;
    b) exit 0 ;; # 返回 basic_software_menu，由 basic-software.sh 处理
    *) echo "无效选择" ;;
  esac
}

install_yay() {
  echo "正在安装 yay..."
  if command -v yay &>/dev/null; then
    echo "yay 已经安装"
  else
    # 克隆 yay git 仓库
    git clone https://aur.archlinux.org/yay.git
    cd yay
    # 编译安装 yay
    makepkg -si
    cd ..
    echo "yay 安装完成"
  fi
  AUR_HELPER_MENU
}

install_paru() {
  echo "正在安装 paru..."
  if command -v paru &>/dev/null; then
    echo "paru 已经安装"
  else
    # 克隆 paru git 仓库
    git clone https://aur.archlinux.org/paru.git
    cd paru
    # 编译安装 paru
    makepkg -si
    cd ..
    echo "paru 安装完成"
  fi
  AUR_HELPER_MENU
}

install_octopi() {
  echo "正在安装 octopi..."
  if pacman -Q octopi &>/dev/null; then
    echo "octopi 已经安装"
  else
    # 使用 pacman 安装 octopi
    sudo pacman -S octopi --noconfirm
    echo "octopi 安装完成"
  fi
  AUR_HELPER_MENU
}

AUR_HELPER_MENU
#!/bin/bash

# system-config/modules/mirrors.sh

MIRRORS_MENU() {
  echo "换源菜单"
  echo "1. 换官方源"
  echo "2. 添加 archlinuxcn 源"
  echo "3. 添加 flathub 源"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) change_to_official_mirrors ;;
    2) add_archlinuxcn_mirrors ;;
    3) add_flathub_repo ;;
    b) exit 0 ;; # 返回 system_config_menu，由 system-config.sh 处理
    *) echo "无效选择" ;;
  esac
}

change_to_official_mirrors() {
  echo "正在更换为官方源..."
  # 备份当前 mirrorlist
  sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup.current
  # 替换 mirrorlist 为官方源列表
  sudo cp /etc/pacman.d/mirrorlist.backup /etc/pacman.d/mirrorlist
  echo "官方源更换完成"
  MIRRORS_MENU
}

add_archlinuxcn_mirrors() {
  echo "正在添加 archlinuxcn 源..."
  # 添加 archlinuxcn 源配置到 pacman.conf
  sudo echo -e "\n[archlinuxcn]\nServer = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch" >> /etc/pacman.conf
  # 导入 archlinuxcn GPG key
  sudo pacman-key -r DA624D892D06DAA7
  sudo pacman-key --lsign-key DA624D892D06DAA7
  echo "archlinuxcn 源添加完成"
  MIRRORS_MENU
}

add_flathub_repo() {
  echo "正在添加 flathub 仓库..."
  # 添加 flathub 仓库
  sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
  echo "flathub 仓库添加完成"
  MIRRORS_MENU
}

MIRRORS_MENU
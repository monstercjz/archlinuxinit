#!/bin/bash

# system-config/system-config.sh

system_config_menu() {
  clear
  echo "系统配置菜单"
  echo "1. 换源"
  echo "2. 设置窗口权限"
  echo "3. sudo 权限强化"
  echo "4. 网络地址设定"
  echo "b. 返回主菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) mirrors_menu ;;
    2) permissions_config ;;
    3) sudo_config ;;
    4) network_config ;;
    b) main_menu ;;
    *) echo "无效选择" ;;
  esac
}

mirrors_menu() {
  echo "换源菜单"
  echo "1. 换官方源"
  echo "2. 添加 archlinuxcn 源"
  echo "3. 添加 flathub 源"
  echo "b. 返回系统配置菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) bash system-config/modules/mirrors.sh official ;; # 假设 mirrors.sh 接受参数 official
    2) bash system-config/modules/mirrors.sh archlinuxcn ;; # 假设 mirrors.sh 接受参数 archlinuxcn
    3) bash system-config/modules/mirrors.sh flathub ;; # 假设 mirrors.sh 接受参数 flathub
    b) system_config_menu ;;
    *) echo "无效选择" ;;
  esac
}

permissions_config() {
  echo "设置窗口权限"
  bash system-config/modules/permissions.sh
  system_config_menu
}

sudo_config() {
  echo "sudo 权限强化"
  bash system-config/modules/sudo.sh
  system_config_menu
}

network_config() {
  echo "网络地址设定"
  bash system-config/modules/network.sh
  system_config_menu
}

system_config_menu

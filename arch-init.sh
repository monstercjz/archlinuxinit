#!/bin/bash

# arch-init.sh

main_menu() {
  echo "主菜单"
  echo "1. 系统配置"
  echo "2. 基础软件"
  echo "3. 常用软件"
  echo "4. ZSH 管理"
  echo "q. 退出"
  read -p "请选择菜单: " choice
  case $choice in
    1) system_config_menu ;;
    2) basic_software_menu ;;
    3) common_software_menu ;;
    4) zsh_manager_menu ;;
    q) exit 0 ;;
    *) echo "无效选择" ;;
  esac
}

system_config_menu() {
  echo "系统配置菜单"
  bash system-config/system-config.sh
  main_menu
}

basic_software_menu() {
  echo "基础软件菜单"
  bash basic-software/basic-software.sh
  main_menu
}

common_software_menu() {
  echo "常用软件菜单"
  bash common-software/common-software.sh
  main_menu
}

zsh_manager_menu() {
  echo "ZSH 管理菜单"
  bash zsh-manager/zsh-manager.sh
  main_menu
}

main_menu
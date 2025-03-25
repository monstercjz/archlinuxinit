#!/bin/bash

# system-config/modules/sudo.sh

SUDO_CONFIG() {
  echo "sudo 权限强化菜单"
  echo "1. 强化 sudo 权限 (免密)"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) enable_sudo_nopasswd ;;
    b) exit 0 ;; # 返回 system_config_menu，由 system-config.sh 处理
    *) echo "无效选择" ;;
  esac
}

enable_sudo_nopasswd() {
  echo "正在强化 sudo 权限..."
  # 获取当前用户名
  current_user=$(whoami)
  # 添加免密 sudo 配置
  sudo echo "%$current_user ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/nopasswd_user
  echo "sudo 权限强化完成"
  SUDO_CONFIG
}

SUDO_CONFIG
#!/bin/bash

# system-config/modules/permissions.sh

PERMISSIONS_CONFIG() {
  echo "设置窗口权限菜单"
  echo "1. 允许普通用户访问窗口"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) allow_user_access_xserver ;;
    b) exit 0 ;; # 返回 system_config_menu，由 system-config.sh 处理
    *) echo "无效选择" ;;
  esac
}

allow_user_access_xserver() {
  echo "正在设置窗口权限..."
  # 允许所有本地用户访问 X server
  xhost +local:
  echo "窗口权限设置完成"
  PERMISSIONS_CONFIG
}

PERMISSIONS_CONFIG
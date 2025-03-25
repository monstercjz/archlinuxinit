#!/bin/bash

# system-config/modules/network.sh

NETWORK_CONFIG() {
  echo "网络地址设定菜单"
  echo "1. 自定义设置网络 IP 等信息 (TODO)"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) custom_network_config ;;
    b) exit 0 ;; # 返回 system_config_menu，由 system-config.sh 处理
    *) echo "无效选择" ;;
  esac
}

custom_network_config() {
  echo "自定义设置网络 IP 等信息 (TODO)"
  echo "此功能尚未实现，敬请期待..."
  NETWORK_CONFIG
  NETWORK_CONFIG
}

NETWORK_CONFIG
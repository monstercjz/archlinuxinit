#!/bin/bash

# basic-software/modules/firewall.sh

FIREWALL_CONFIG() {
  echo "防火墙配置菜单"
  echo "1. 防火墙配置 (TODO)"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) config_firewall ;;
    b) exit 0 ;; # 返回 basic_software_menu，由 basic-software.sh 处理
    *) echo "无效选择" ;;
  esac
}

config_firewall() {
  echo "防火墙配置 (TODO)..."
  echo "此功能尚未实现，敬请期待..."
  FIREWALL_CONFIG
  FIREWALL_CONFIG
}

FIREWALL_CONFIG
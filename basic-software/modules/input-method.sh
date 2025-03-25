#!/bin/bash

# basic-software/modules/input-method.sh

INPUT_METHOD_INSTALL() {
  echo "安装输入法菜单"
  echo "1. 安装输入法 (TODO)"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_input_method_package ;;
    b) exit 0 ;; # 返回 basic_software_menu，由 basic-software.sh 处理
    *) echo "无效选择" ;;
  esac
}

install_input_method_package() {
  echo "正在安装输入法 (TODO)..."
  echo "此功能尚未实现，敬请期待..."
  INPUT_METHOD_INSTALL
  INPUT_METHOD_INSTALL
}

INPUT_METHOD_INSTALL

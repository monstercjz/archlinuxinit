#!/bin/bash

# basic-software/basic-software.sh

basic_software_menu() {
  echo "基础软件菜单"
  echo "1. 安装 AUR 助手"
  echo "2. 安装 SSH"
  echo "3. 安装 nano"
  echo "4. 安装输入法"
  echo "5. 防火墙配置"
  echo "b. 返回主菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) aur_helper_menu ;;
    2) ssh_install ;;
    3) nano_install ;;
    4) input_method_install ;;
    5) firewall_config ;;
    b) main_menu ;;
    *) echo "无效选择" ;;
  esac
}

aur_helper_menu() {
  echo "安装 AUR 助手菜单"
  echo "1. 安装 yay"
  echo "2. 安装 paru"
  echo "3. 安装 octopi"
  echo "b. 返回基础软件菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) bash basic-software/modules/aur-helper.sh yay ;; # 假设 aur-helper.sh 接受参数 yay
    2) bash basic-software/modules/aur-helper.sh paru ;; # 假设 aur-helper.sh 接受参数 paru
    3) bash basic-software/modules/aur-helper.sh octopi ;; # 假设 aur-helper.sh 接受参数 octopi
    b) basic_software_menu ;;
    *) echo "无效选择" ;;
  esac
}

ssh_install() {
  echo "安装 SSH"
  bash basic-software/modules/ssh.sh
  basic_software_menu
}

nano_install() {
  echo "安装 nano"
  bash basic-software/modules/nano.sh
  basic_software_menu
}

input_method_install() {
  echo "安装输入法"
  bash basic-software/modules/input-method.sh
  basic_software_menu
}

firewall_config() {
  echo "防火墙配置"
  bash basic-software/modules/firewall.sh
  basic_software_menu
}

basic_software_menu
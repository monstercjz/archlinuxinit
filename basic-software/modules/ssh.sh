#!/bin/bash

# basic-software/modules/ssh.sh

SSH_INSTALL() {
  echo "安装 SSH 菜单"
  echo "1. 安装 SSH"
  echo "b. 返回上一级菜单"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_ssh_server ;;
    b) exit 0 ;; # 返回 basic_software_menu，由 basic-software.sh 处理
    *) echo "无效选择" ;;
  esac
}

install_ssh_server() {
  echo "正在安装 SSH..."
  # 使用 pacman 安装 openssh
  sudo pacman -S openssh --noconfirm
  # 启动 sshd 服务
  sudo systemctl start sshd
  # 设置 sshd 服务开机自启
  sudo systemctl enable sshd
  echo "SSH 安装完成"
  SSH_INSTALL
}

SSH_INSTALL
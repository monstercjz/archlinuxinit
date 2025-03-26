#!/bin/bash

# basic-software/modules/ssh.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/ssh_setup.log"

# 确保日志目录存在
ensure_log_dir() {
  if [ ! -d "$LOG_DIR" ]; then
    echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
    echo -e "${COLOR_BLUE}步骤 0: 创建日志目录${COLOR_RESET}"
    echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
    echo "开始创建日志目录 $LOG_DIR"
    if sudo mkdir -p "$LOG_DIR"; then
      echo "日志目录创建完成: $LOG_DIR"
      log "INFO" "日志目录创建完成: $LOG_DIR"
    else
      echo "日志目录创建失败"
      log "ERROR" "日志目录创建失败"
      exit 1
    fi
  fi
}

# 确保日志文件存在并有写权限
ensure_log_file() {
  if [ ! -f "$LOG_FILE" ]; then
    echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
    echo -e "${COLOR_BLUE}步骤 1: 创建日志文件${COLOR_RESET}"
    echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
    echo "开始创建日志文件 $LOG_FILE"
    if sudo touch "$LOG_FILE"; then
      echo "日志文件创建完成: $LOG_FILE"
      log "INFO" "日志文件创建完成: $LOG_FILE"
      sudo chmod 640 "$LOG_FILE"
      log "INFO" "设置日志文件权限为 640"
    else
      echo "日志文件创建失败"
      log "ERROR" "日志文件创建失败"
      exit 1
    fi
  fi
}

log() {
  local level="$1"
  local message="$2"
  local color

  case "$level" in
    INFO)
      color=$(tput setaf 2)  # Green
      ;;
    WARNING)
      color=$(tput setaf 3)  # Yellow
      ;;
    ERROR)
      color=$(tput setaf 1)  # Red
      ;;
    *)
      color=$(tput setaf 4)  # Blue
      ;;
  esac

  # 终端输出带颜色的日志
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message" | sed "s/^/$color/" | sed "s/$/$(tput sgr0)/"

  # 文件中写入纯文本日志
  echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message" | sudo tee -a $LOG_FILE > /dev/null
}

run_with_sudo() {
  if sudo "$@"; then
    log "INFO" "Command '$*' executed successfully"
  else
    log "ERROR" "Command '$*' failed"
    return 1
  fi
}

confirm_action() {
  read -p "$(echo -e "${COLOR_GREEN}确认执行此操作? (y/n): ${COLOR_RESET}")" confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${COLOR_RED}操作已取消${COLOR_RESET}"
    log "INFO" "操作已取消"
    return 1
  fi
}
restart_ssh_service() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 2: 重启 SSH 服务${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  if confirm_action; then
    log "INFO" "开始重启 SSH 服务"
    if run_with_sudo systemctl restart sshd; then
      echo "SSH 服务重启完成"
      log "INFO" "SSH 服务重启完成"
    fi
  fi
}
SSH_INSTALL() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}SSH 安装菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 安装 SSH 服务器${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 启用 SSH 服务${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 禁用 SSH 服务${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}4. 配置 SSH 服务${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}5. 生成 SSH 密钥${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}b. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_ssh_server ;;
    2) enable_ssh_service ;;
    3) disable_ssh_service ;;
    4) configure_ssh ;;
    5) generate_ssh_key ;;
    b) exit 0 ;; # 返回 basic_software_menu，由 basic-software.sh 处理
    *) echo "无效选择" ;;
  esac
}

install_ssh_server() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 安装 SSH 服务器${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始安装 SSH 服务器"
  if pacman -Q openssh &>/dev/null; then
    echo "SSH 已经安装"
    log "INFO" "SSH 已经安装"
  else
    if confirm_action; then
      if run_with_sudo pacman -S openssh --noconfirm; then
        echo "SSH 安装完成"
        log "INFO" "SSH 安装完成"
        enable_ssh_service
      fi
    fi
  fi
  SSH_INSTALL
}

enable_ssh_service() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 启用 SSH 服务${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始启用 SSH 服务"
  if confirm_action; then
    if run_with_sudo systemctl start sshd; then
      echo "SSH 服务启动完成"
      log "INFO" "SSH 服务启动完成"
      if run_with_sudo systemctl enable sshd; then
        echo "SSH 服务开机自启设置完成"
        log "INFO" "SSH 服务开机自启设置完成"
      fi
    fi
  fi
  SSH_INSTALL
}

disable_ssh_service() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 禁用 SSH 服务${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始禁用 SSH 服务"
  if confirm_action; then
    if run_with_sudo systemctl stop sshd; then
      echo "SSH 服务停止完成"
      log "INFO" "SSH 服务停止完成"
      if run_with_sudo systemctl disable sshd; then
        echo "SSH 服务开机自启禁用完成"
        log "INFO" "SSH 服务开机自启禁用完成"
      fi
    fi
  fi
  SSH_INSTALL
}

configure_ssh() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}SSH 配置菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 修改 SSH 端口${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 启用/禁用 root 登录${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 启用/禁用仅运行密钥认证${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}4. 手动编辑配置文件${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}b. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) change_ssh_port ;;
    2) toggle_root_login ;;
    3) toggle_key_authentication ;;
    4) edit_ssh_config ;;
    b) SSH_INSTALL ;;
    *) echo "无效选择" ;;
  esac
}

change_ssh_port() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 修改 SSH 端口${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始修改 SSH 端口"
  read -p "请输入新的 SSH 端口: " new_port
  if confirm_action; then
    if run_with_sudo sed -i "s/^#*Port .*/Port $new_port/" /etc/ssh/sshd_config; then
      echo "SSH 端口修改完成"
      log "INFO" "SSH 端口修改完成"
      restart_ssh_service
    fi
  fi
  configure_ssh
}

toggle_root_login() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 启用/禁用 root 登录${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始启用/禁用 root 登录"
  read -p "启用 root 登录? (y/n): " choice
  if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    if confirm_action; then
      if run_with_sudo sed -i "s/^#*PermitRootLogin .*/PermitRootLogin yes/" /etc/ssh/sshd_config; then
        echo "root 登录已启用"
        log "INFO" "root 登录已启用"
        restart_ssh_service
      fi
    fi
  else
    if confirm_action; then
      if run_with_sudo sed -i "s/^#*PermitRootLogin .*/PermitRootLogin no/" /etc/ssh/sshd_config; then
        echo "root 登录已禁用"
        log "INFO" "root 登录已禁用"
        restart_ssh_service
      fi
    fi
  fi
  configure_ssh
}

toggle_key_authentication() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 启用/禁用仅运行密钥认证${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始启用/禁用仅运行密钥认证"
  read -p "启用仅运行密钥认证? (y/n): " choice
  if [[ "$choice" == "y" || "$choice" == "Y" ]]; then
    if confirm_action; then
      if run_with_sudo sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication no/" /etc/ssh/sshd_config; then
        echo "仅运行密钥认证已启用"
        log "INFO" "仅运行密钥认证已启用"
        restart_ssh_service
      fi
    fi
  else
    if confirm_action; then
      if run_with_sudo sed -i "s/^#*PasswordAuthentication .*/PasswordAuthentication yes/" /etc/ssh/sshd_config; then
        echo "仅运行密钥认证已禁用"
        log "INFO" "仅运行密钥认证已禁用"
        restart_ssh_service
      fi
    fi
  fi
  configure_ssh
}

edit_ssh_config() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 手动编辑配置文件${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始手动编辑配置文件"
  if confirm_action; then
    if run_with_sudo nano /etc/ssh/sshd_config; then
      echo "配置文件编辑完成"
      log "INFO" "配置文件编辑完成"
      restart_ssh_service
    fi
  fi
  configure_ssh
}

generate_ssh_key() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 生成 SSH 密钥${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始生成 SSH 密钥"
  read -p "请输入密钥保存路径 (默认: ~/.ssh/id_rsa): " key_path
  key_path=${key_path:-~/.ssh/id_rsa}
  if confirm_action; then
    if run_with_sudo ssh-keygen -t rsa -b 4096 -f "$key_path"; then
      echo "SSH 密钥生成完成"
      log "INFO" "SSH 密钥生成完成"
    fi
  fi
  SSH_INSTALL
}



# 清理函数
cleanup() {
  log "INFO" "脚本退出"
}

# 设置 trap 以捕获退出信号
trap cleanup EXIT

# 确保日志目录和文件存在
ensure_log_dir
ensure_log_file

# 启动菜单
SSH_INSTALL
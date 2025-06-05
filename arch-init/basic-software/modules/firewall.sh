#!/bin/bash

# basic-software/modules/firewall.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/firewall_setup.log"

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
      sudo chmod 644 "$LOG_FILE"
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

FIREWALL_CONFIG() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}防火墙配置菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 安装防火墙${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 启用防火墙${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 禁用防火墙${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}4. 开放端口${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}5. 关闭端口${COLOR_RESET}"
  #echo -e "${COLOR_YELLOW}6. 查看防火墙状态${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}6. 查看防火墙规则${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}7. 重置防火墙规则${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}8. 开启自启动防火墙${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}9. 禁用自启动防火墙${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_firewall ;;
    2) enable_firewall ;;
    3) disable_firewall ;;
    4) open_port ;;
    5) close_port ;;
    # 6) check_firewall_status ;;
    6) view_firewall_rules ;;
    7) reset_firewall_rules ;;
    8) enable_boot_firewall ;;
    9) disable_boot_firewall ;;
    0) exit 0 ;; # 返回 basic_software_menu，由 basic-software.sh 处理
    *) wait_right_choice ;;
  esac
}
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  FIREWALL_CONFIG
}

install_firewall() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 检查 ufw 是否已安装${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始检查 ufw 是否已安装"
  
  if pacman -Q ufw &> /dev/null; then
    echo -e "${COLOR_YELLOW}ufw 已经安装。${COLOR_RESET}"
    log "INFO" "ufw 已经安装"
    read -p "$(echo -e "${COLOR_GREEN}是否要强制重新安装 ufw? (y/n): ${COLOR_RESET}")" reinstall
    if [[ "$reinstall" == "y" || "$reinstall" == "Y" ]]; then
      echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
      echo -e "${COLOR_BLUE}步骤 2: 强制重新安装 ufw${COLOR_RESET}"
      echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
      log "INFO" "开始强制重新安装 ufw"
      if confirm_action; then
        if run_with_sudo pacman -S --force ufw; then
          echo "ufw 强制重新安装完成"
          log "INFO" "ufw 强制重新安装完成"
        fi
      fi
    else
      echo -e "${COLOR_RED}操作已取消${COLOR_RESET}"
      log "INFO" "操作已取消"
    fi
  else
    echo -e "${COLOR_YELLOW}ufw 未安装。${COLOR_RESET}"
    log "INFO" "ufw 未安装"
    echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
    echo -e "${COLOR_BLUE}步骤 2: 安装 ufw${COLOR_RESET}"
    echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
    log "INFO" "开始安装 ufw"
    if confirm_action; then
      if run_with_sudo pacman -S ufw; then
        echo "ufw 安装完成"
        log "INFO" "ufw 安装完成"
      fi
    fi
    
  fi
  
  FIREWALL_CONFIG
}
enable_boot_firewall() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 设置自启动 ufw${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始设置 ufw 开机自启动"
  if confirm_action; then
    if run_with_sudo systemctl enable ufw; then
      echo "ufw 开机自启动设置完成"
      log "INFO" "ufw 开机自启动设置完成"
    fi
  fi
  FIREWALL_CONFIG
}
disable_boot_firewall() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 关闭自启动 ufw${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始禁用 ufw 开机自启动"
  if confirm_action; then
    if run_with_sudo systemctl disable ufw; then
      echo "ufw 开机自启动禁用完成"
      log "INFO" "ufw 开机自启动禁用完成"
    fi
  fi
  FIREWALL_CONFIG
}
enable_firewall() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 启用 ufw${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始启用 ufw"
  if confirm_action; then
    if run_with_sudo ufw enable; then
      echo "ufw 启用完成"
      log "INFO" "ufw 启用完成"
    fi
  fi
  FIREWALL_CONFIG
}

disable_firewall() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 禁用 ufw${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始禁用 ufw"
  if confirm_action; then
    if run_with_sudo ufw disable; then
      echo "ufw 禁用完成"
      log "INFO" "ufw 禁用完成"
    fi
  fi
  FIREWALL_CONFIG
}

open_port() {
  read -p "请输入要开放的端口号: " port
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 开放端口 $port${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始开放端口 $port"
  if confirm_action; then
    if run_with_sudo ufw allow $port; then
      echo "端口 $port 开放完成"
      log "INFO" "端口 $port 开放完成"
    fi
  fi
  FIREWALL_CONFIG
}

close_port() {
  read -p "请输入要关闭的端口号: " port
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 关闭端口 $port${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始关闭端口 $port"
  if confirm_action; then
    if run_with_sudo ufw deny $port; then
      echo "端口 $port 关闭完成"
      log "INFO" "端口 $port 关闭完成"
    fi
  fi
  FIREWALL_CONFIG
}

check_firewall_status() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 查看防火墙状态${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  if run_with_sudo ufw status; then
      log "INFO" "开始查看防火墙状态"
  fi
  FIREWALL_CONFIG
}

view_firewall_rules() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 查看防火墙规则${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  if run_with_sudo ufw status verbose; then
      log "INFO" "开始查看防火墙规则"
  fi
  FIREWALL_CONFIG
}

reset_firewall_rules() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 重置防火墙规则${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始重置防火墙规则"
  if confirm_action; then
    if run_with_sudo ufw reset; then
      echo "防火墙规则重置完成"
      log "INFO" "防火墙规则重置完成"
    fi
  fi
  FIREWALL_CONFIG
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
FIREWALL_CONFIG
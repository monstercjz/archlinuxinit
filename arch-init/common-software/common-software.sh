#!/bin/bash

# common-software/common-software.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/arch-init.log"

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

confirm_action() {
  read -p "$(echo -e "${COLOR_RED}确认执行此操作? (y/n): ${COLOR_RESET}")" confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${COLOR_RED}操作已取消${COLOR_RESET}"
    log "INFO" "操作已取消"
    return 1
  fi
}

common_software_menu() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}常用软件菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 必备软件${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 其他软件${COLOR_RESET}"
  echo -e "${COLOR_BLUE}9. 清屏${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回主菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_software essential ;;
    2) other_software_menu ;;
    9) clear_screen ;;
    0) exit 0 ;; # 返回主菜单
    *) wait_right_choice ;;
  esac
}
clear_screen() {
  clear
  common_software_menu
}
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  common_software_menu
}



install_software() {
  local software="$1"
  if confirm_action; then
    if bash common-software/modules/"$software".sh; then
      log "INFO" "已经结束 $software 相关动作，返回常用软件安装菜单成功"
    else
      log "ERROR" "打开界面 $software 失败"
    fi
  fi
  common_software_menu
}

other_software_menu() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}其他软件菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo "敬请期待..."
  common_software_menu
}

# 确保日志目录和文件存在
ensure_log_dir
ensure_log_file

# 启动常用软件菜单
common_software_menu
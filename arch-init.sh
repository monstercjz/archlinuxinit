#!/bin/bash

# arch-init.sh

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

# confirm_action() {
#   read -p "$(echo -e "${COLOR_GREEN}确认执行此操作? (y/n): ${COLOR_RESET}")" confirm
#   if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
#     echo -e "${COLOR_RED}操作已取消${COLOR_RESET}"
#     log "INFO" "操作已取消"
#     return 1
#   fi
# }
confirm_actions() {
  read -p "$(echo -e "${COLOR_RED}确认执行此操作? (y/n)【除非输入N或者n,其他都默认同意】: ${COLOR_RESET}")" confirm
  if [[ "$confirm" == "n" || "$confirm" == "N" ]]; then
    echo -e "${COLOR_RED}操作已取消${COLOR_RESET}"
    log "INFO" "操作已取消"
    return 1
  fi
}

main_menu() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}ARCHLINUX-INIT--主菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 系统基础设置${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 基础软件安装${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 常用软件安装${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}4. SHELL-ZSH 美化${COLOR_RESET}"
  echo -e "${COLOR_BLUE}9. 清屏${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 退出${COLOR_RESET}"
  read -p "请选择菜单 (输入：0/1/2/3/4/9 中任一): " choice
  case $choice in
    1) system_config_menu ;;
    2) basic_software_menu ;;
    3) common_software_menu ;;
    4) zsh_manager_menu ;;
    9) clear_screen ;;
    0) exit 0 ;;
    *) wait_right_choice ;;
  esac
}
clear_screen() {
  clear
  main_menu
}
wait_right_choice() {
  clear
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  main_menu
}
system_config_menu() {
  # echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_GREEN}<<<<<<<即将打开系统基础配置菜单>>>>>>${COLOR_RESET}"
  # echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
   if confirm_actions; then
    if bash system-config/system-config.sh; then
      log "INFO" "系统基础配置完毕，成功返回主菜单"
    else
      log "ERROR" "打开系统基础配置菜单失败"
    fi
   fi
  main_menu
}

basic_software_menu() {
  # echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_GREEN}<<<<<<<即将打开基础软件安装菜单>>>>>>${COLOR_RESET}"
  # echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
   if confirm_actions; then
    if bash basic-software/basic-software.sh; then
      log "INFO" "基础软件安装完毕，成功返回主菜单"
    else
      log "ERROR" "打开基础软件安装菜单失败"
    fi
   fi
  main_menu
}

common_software_menu() {
  # echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_GREEN}<<<<<<<即将打开常用软件安装菜单>>>>>>${COLOR_RESET}"
  # echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
   if confirm_actions; then
    if bash common-software/common-software.sh; then
      log "INFO" "常用软件安装完毕，成功返回主菜单"
    else
      log "ERROR" "打开常用软件安装菜单失败"
    fi
   fi
  main_menu
}

zsh_manager_menu() {
  # echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_GREEN}<<<<<<<即将打开 SHELL-ZSH 美化配置菜单>>>>>>${COLOR_RESET}"
  # echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
   if confirm_actions; then
    if bash zsh-manager/zsh-manager.sh; then
      log "INFO" "SHELL-ZSH 美化配置完毕，成功返回主菜单"
    else
      log "ERROR" "打开 SHELL-ZSH 美化配置菜单失败"
    fi
   fi
  main_menu
}

# 确保日志目录和文件存在
ensure_log_dir
ensure_log_file

# 启动主菜单
main_menu
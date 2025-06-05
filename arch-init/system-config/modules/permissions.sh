#!/bin/bash

# system-config/modules/permissions.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/permissions_setup.log"

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

PERMISSIONS_CONFIG() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}设置窗口权限菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 允许普通用户访问窗口${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) allow_user_access_xserver ;;
    0) exit 0 ;; # 返回 system_config_menu，由 system-config.sh 处理
    *) wait_right_choice ;;
  esac
}
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  PERMISSIONS_CONFIG
}

allow_user_access_xserver() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 允许普通用户访问 X server${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始设置窗口权限"
  echo "TODO：此处功能待完善"
  # if confirm_action; then
  #   允许所有本地用户访问 X server
  #   if run_with_sudo xhost +local:; then
  #     echo "窗口权限设置完成"
  #     log "INFO" "窗口权限设置完成"
  #   else
  #     echo "窗口权限设置失败"
  #     log "ERROR" "窗口权限设置失败"
  #   fi
  # fi

  PERMISSIONS_CONFIG
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
PERMISSIONS_CONFIG
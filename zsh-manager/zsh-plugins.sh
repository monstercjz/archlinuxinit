#!/bin/bash

# system-config/system-config.sh

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

confirm_action() {
  read -p "$(echo -e "${COLOR_RED}确认执行此操作? (y/n): ${COLOR_RESET}")" confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${COLOR_RED}操作已取消${COLOR_RESET}"
    log "INFO" "操作已取消"
    return 1
  fi
}

zsh_config_menu() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}zhs及插件安装管理菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 安装zsh${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 安装oh my zsh${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 安装fzf${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}4. 安装p10k${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}5. 安装其他插件${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}6. 安装字体${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}7. 管理备份${COLOR_RESET}"
  echo -e "${COLOR_BLUE}9. 清屏${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回主菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_software zsh ;;
    2) install_software omz ;;
    3) install_software install_fzf ;;
    4) install_software p10k ;;
    5) install_software plugins ;;
    6) install_software font.0 ;;
    7) install_software backup ;;
    9) clear_screen ;;
    0) exit 0 ;; # 返回主菜单
    *) wait_right_choice ;;
  esac
}
clear_screen() {
  clear
  zsh_config_menu
}
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  zsh_config_menu
}
install_software() {
  local software="$1"
  if confirm_action; then
    if bash zsh-manager/modules/"$software".sh; then
      log "INFO" "已经结束 $software 相关动作，返回系统基础配置菜单成功"
    else
      log "ERROR" "打开界面 $software 失败"
    fi
  fi
  zsh_config_menu
}


# 确保日志目录和文件存在
ensure_log_dir
ensure_log_file

# 启动系统配置菜单
zsh_config_menu
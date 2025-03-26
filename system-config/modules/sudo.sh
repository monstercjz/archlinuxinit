#!/bin/bash

# system-config/modules/sudo.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/sudo_setup.log"

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
      color="$COLOR_GREEN"
      ;;
    WARNING)
      color="$COLOR_YELLOW"
      ;;
    ERROR)
      color="$COLOR_RED"
      ;;
    *)
      color="$COLOR_BLUE"
      ;;
  esac

  # 终端输出带颜色的日志
  echo -e "$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message" | sed "s/^/$color/" | sed "s/$/$COLOR_RESET/"

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

SUDO_CONFIG() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}sudo 权限强化菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 强化 sudo 权限 (免密)${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) enable_sudo_nopasswd ;;
    0) exit 0 ;; # 返回 system_config_menu，由 system-config.sh 处理
    *) wait_right_choice ;;
  esac
}
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  SUDO_CONFIG
}

enable_sudo_nopasswd() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 强化 sudo 权限 (免密)${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始强化 sudo 权限 (免密)"

  # 获取当前用户
  current_user=$(whoami)

  # 检查是否为root用户
  if [ "$current_user" = "root" ]; then
    echo -e "${COLOR_YELLOW}请输入要设置sudo权限的普通用户名:${COLOR_RESET}"
    read -p "用户名: " username
  else
    username=$current_user
  fi

  # 检查用户是否存在
  if ! id "$username" &>/dev/null; then
    echo -e "${COLOR_RED}错误: 用户 $username 不存在${COLOR_RESET}"
    log "ERROR" "用户 $username 不存在"
    SUDO_CONFIG
    return
  fi

  # 检查sudo是否已安装
  if ! command -v sudo &> /dev/null; then
    echo -e "${COLOR_YELLOW}sudo未安装，正在安装...${COLOR_RESET}"
    if run_with_sudo pacman -S --noconfirm sudo; then
      echo -e "${COLOR_GREEN}sudo安装成功!${COLOR_RESET}"
      log "INFO" "sudo安装成功"
    else
      echo -e "${COLOR_RED}sudo安装失败!${COLOR_RESET}"
      log "ERROR" "sudo安装失败"
      SUDO_CONFIG
      return
    fi
  fi

  # 显示sudo配置选项
  echo -e "${COLOR_YELLOW}请选择sudo权限配置:${COLOR_RESET}"
  echo -e "${COLOR_GREEN}1. 允许用户执行所有命令且无需密码${COLOR_RESET}"
  echo -e "${COLOR_GREEN}2. 允许用户执行所有命令但需要密码${COLOR_RESET}"
  echo -e "${COLOR_GREEN}3. 允许用户执行特定命令且无需密码${COLOR_RESET}"
  read -p "请输入选项: " choice

  # 创建sudoers.d目录（如果不存在）
  run_with_sudo mkdir -p /etc/sudoers.d

  case $choice in
    1)
      # 允许用户执行所有命令且无需密码
      rule="$username ALL=(ALL) NOPASSWD: ALL"
      ;;
    2)
      # 允许用户执行所有命令但需要密码
      rule="$username ALL=(ALL) ALL"
      ;;
    3)
      # 允许用户执行特定命令且无需密码
      echo -e "${COLOR_YELLOW}请输入允许执行的命令路径，多个命令用空格分隔:${COLOR_RESET}"
      echo -e "${COLOR_YELLOW}例如: /usr/bin/pacman /usr/bin/systemctl${COLOR_RESET}"
      read -p "命令路径: " commands

      # 构建sudoers规则
      rule="$username ALL=(ALL) NOPASSWD: "
      for cmd in $commands; do
        rule="$rule $cmd,"
      done
      # 移除最后一个逗号
      rule=${rule%,}
      ;;
    *)
      echo -e "${COLOR_RED}无效选项${COLOR_RESET}"
      log "ERROR" "无效选项"
      SUDO_CONFIG
      return
      ;;
  esac

  # 写入sudoers.d文件
  if echo "$rule" | run_with_sudo tee /etc/sudoers.d/$username; then
    # 验证配置文件语法
    if run_with_sudo visudo -c -f /etc/sudoers.d/$username; then
      echo -e "${COLOR_GREEN}sudo权限配置完成!${COLOR_RESET}"
      log "INFO" "sudo权限配置完成"
    else
      echo -e "${COLOR_RED}sudo 配置文件语法错误，还原配置${COLOR_RESET}"
      log "ERROR" "sudo 配置文件语法错误"
      run_with_sudo rm -f /etc/sudoers.d/$username
    fi
  else
    echo -e "${COLOR_RED}sudo权限配置失败${COLOR_RESET}"
    log "ERROR" "sudo权限配置失败"
  fi

  # 设置正确的权限
  run_with_sudo chmod 440 /etc/sudoers.d/$username

  SUDO_CONFIG
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
SUDO_CONFIG
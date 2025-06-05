#!/bin/bash

# common-software/modules/essential.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/essential_setup.log"

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

# 检查软件是否已安装
is_installed() {
  local package="$1"
  if pacman -Q "$package" &> /dev/null; then
    return 0
  else
    return 1
  fi
}

# 确认是否重新安装
confirm_reinstall() {
  local package="$1"
  read -p "$(echo -e "${COLOR_GREEN}软件 $package 已安装，是否重新安装? (y/n): ${COLOR_RESET}")" confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${COLOR_RED}重新安装已取消${COLOR_RESET}"
    log "INFO" "重新安装 $package 已取消"
    return 1
  fi
}

# 使用 pacman 安装软件
install_with_pacman() {
  local package="$1"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 使用 pacman 安装 $package${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始使用 pacman 安装 $package"
  if confirm_action; then
    if run_with_sudo pacman -S "$package" --noconfirm; then
      echo "$package 安装完成"
      log "INFO" "$package 安装完成"
      return 0
    else
      echo "使用 pacman 安装 $package 失败"
      log "ERROR" "使用 pacman 安装 $package 失败"
      return 1
    fi
  fi
}

# 使用 paru 安装软件
install_with_paru() {
  local package="$1"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 使用 paru 安装 $package${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始使用 paru 安装 $package"
  if confirm_action; then
    set -euo pipefail # 建议在所有脚本中使用此行

    # 检查当前用户是否为 root
    if [[ "$EUID" -eq 0 ]]; then
        # 如果是 root，尝试以原始用户身份执行 paru
        if [[ -n "$SUDO_USER" ]]; then
            echo "当前以 root 身份运行，尝试以用户 '$SUDO_USER' 执行 paru。"
            if sudo -u "$SUDO_USER" paru -S "$package" --noconfirm; then
              echo "$package 安装完成"
              log "INFO" "$package 安装完成"
              return 0
            else
              echo "使用 paru 安装 $package 失败"
              log "ERROR" "使用 paru 安装 $package 失败"
              return 1
            fi
        else
            echo "错误: 以 root 身份运行，但无法确定原始用户。请以非 root 用户运行此脚本，或者设置 SUDO_USER 环境变量。" >&2
            exit 1
        fi
    else
        # 如果不是 root，直接执行 paru
        echo "当前以非 root 身份运行，直接执行 paru。"
        paru -S "$package"  --noconfirm
    fi
    
  fi
}

# 使用 yay 安装软件
install_with_yay() {
  local package="$1"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 使用 yay 安装 $package${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始使用 yay 安装 $package"
  if confirm_action; then
    set -euo pipefail # 建议在所有脚本中使用此行

    # 检查当前用户是否为 root
    if [[ "$EUID" -eq 0 ]]; then
        # 如果是 root，尝试以原始用户身份执行 paru
        if [[ -n "$SUDO_USER" ]]; then
            echo "当前以 root 身份运行，尝试以用户 '$SUDO_USER' 执行 yay"
            if sudo -u "$SUDO_USER" yay -S "$package" --noconfirm; then
              echo "$package 安装完成"
              log "INFO" "$package 安装完成"
              return 0
            else
              echo "使用 yay 安装 $package 失败"
              log "ERROR" "使用 yay 安装 $package 失败"
              return 1
            fi
            
        else
            echo "错误: 以 root 身份运行，但无法确定原始用户。请以非 root 用户运行此脚本，或者设置 SUDO_USER 环境变量。" >&2
            exit 1
        fi
    else
        # 如果不是 root，直接执行 paru
        echo "当前以非 root 身份运行，直接执行 yay。"
        yay -S "$package"  --noconfirm
    fi
  fi
}

# 安装软件的通用函数
install_software() {
  local package="$1"
  local installer

  if is_installed "$package"; then
    if ! confirm_reinstall "$package"; then
      return
    fi
  fi

  local installers=("install_with_pacman" "install_with_paru" "install_with_yay")

  for installer in "${installers[@]}"; do
    local tool="${installer#install_with_}"
    if command -v "$tool" &> /dev/null; then
      echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
      echo -e "${COLOR_BLUE}尝试使用 $tool 安装 $package${COLOR_RESET}"
      echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
      log "INFO" "尝试使用 $tool 安装 $package"
      if $installer "$package"; then
        echo "$package 安装完成"
        log "INFO" "$package 安装完成"
        return 0
      else
        echo "使用 $tool 安装 $package 失败"
        log "ERROR" "使用 $tool 安装 $package 失败"
      fi
    else
      echo "未找到可用的 $tool"
      log "WARNING" "未找到可用的 $tool"
    fi
  done

  echo "所有可用的安装工具均未能成功安装 $package"
  log "ERROR" "所有可用的安装工具均未能成功安装 $package"
  return 1
}

install_vscode() {
  echo "正在安装 VSCode..."
  install_software "visual-studio-code-bin"
  ESSENTIAL_SOFTWARE_MENU
}

install_rustdesk() {
  echo "正在安装 RustDesk..."
  install_software "rustdesk"
  ESSENTIAL_SOFTWARE_MENU
}

install_edge() {
  echo "正在安装 Edge 浏览器..."
  install_software "microsoft-edge-stable-bin"
  ESSENTIAL_SOFTWARE_MENU
}

ESSENTIAL_SOFTWARE_MENU() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}必备软件菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 安装 VSCode${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 安装 RustDesk${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 安装 Edge 浏览器${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_vscode ;;
    2) install_rustdesk ;;
    3) install_edge ;;
    0) exit 0 ;; # 返回 common_software_menu，由 common-software.sh 处理
    *) wait_right_choice ;;
  esac
}
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  ESSENTIAL_SOFTWARE_MENU
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
ESSENTIAL_SOFTWARE_MENU
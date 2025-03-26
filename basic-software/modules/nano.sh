#!/bin/bash

# basic-software/modules/nano.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/nano_setup.log"

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

NANO_INSTALL() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}nano 安装菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 安装/重新安装 nano${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 设置 nano 为默认编辑器${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 配置 nano 支持语法高亮、显示行号和自动缩进${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}b. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_nano_editor ;;
    2) set_default_editor ;;
    3) configure_nano ;;
    b) exit 0 ;; # 返回 basic_software_menu，由 basic-software.sh 处理
    *) echo "无效选择" ;;
  esac
}

install_nano_editor() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 安装/重新安装 nano${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始安装/重新安装 nano"
  if pacman -Q nano &>/dev/null; then
    echo "nano 已经安装"
    log "INFO" "nano 已经安装"
    read -p "$(echo -e "${COLOR_GREEN}是否强制重新安装 nano? (y/n): ${COLOR_RESET}")" reinstall
    if [[ "$reinstall" == "y" || "$reinstall" == "Y" ]]; then
      if confirm_action; then
        if run_with_sudo pacman -S nano --noconfirm --overwrite=*; then
          echo "nano 重新安装完成"
          log "INFO" "nano 重新安装完成"
        fi
      fi
    else
      echo "跳过重新安装"
      log "INFO" "跳过重新安装"
    fi
  else
    if confirm_action; then
      if run_with_sudo pacman -S nano --noconfirm; then
        echo "nano 安装完成"
        log "INFO" "nano 安装完成"
      fi
    fi
  fi
  NANO_INSTALL
}

set_default_editor() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 2: 设置 nano 为默认编辑器${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始设置 nano 为默认编辑器"

  # 检查当前 shell
  local shell_config
  if [ "$SHELL" == "/bin/bash" ]; then
    shell_config="$HOME/.bashrc"
  elif [ "$SHELL" == "/bin/zsh" ]; then
    shell_config="$HOME/.zshrc"
  else
    echo "不支持的 shell 环境: $SHELL"
    log "ERROR" "不支持的 shell 环境: $SHELL"
    return
  fi

  # 备份当前 shell 配置文件
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="${shell_config}.no_nano_backup_${timestamp}"
  if [ -f "$shell_config" ]; then
    cp "$shell_config" "$backup_file"
    echo "备份当前 shell 配置文件到 $backup_file"
    log "INFO" "备份当前 shell 配置文件到 $backup_file"
  else
    echo "当前 shell 配置文件不存在，无需备份"
    log "INFO" "当前 shell 配置文件不存在，无需备份"
  fi

  # 检查是否已设置 EDITOR 和 VISUAL
  if grep -q "export EDITOR=nano" "$shell_config" && grep -q "export VISUAL=nano" "$shell_config"; then
    echo "nano 已经设置为默认编辑器"
    log "INFO" "nano 已经设置为默认编辑器"
  else
    if confirm_action; then
      echo "export EDITOR=nano" | tee -a "$shell_config" > /dev/null
      echo "export VISUAL=nano" | tee -a "$shell_config" > /dev/null
      echo "nano 设置为默认编辑器"
      log "INFO" "nano 设置为默认编辑器"
      echo "请手动重新加载 shell 配置文件以应用更改。"
      echo "你可以运行以下命令："
      echo "source $shell_config"
    fi
  fi
  NANO_INSTALL
}

configure_nano() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 3: 配置 nano 支持语法高亮、显示行号和自动缩进${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始配置 nano"

  if confirm_action; then
    # 检查用户配置文件
    local nano_config="$HOME/.nanorc"
    if [ ! -f "$nano_config" ]; then
      echo "创建用户配置文件 $nano_config"
      touch "$nano_config"
      log "INFO" "创建用户配置文件 $nano_config"
    fi

    # 添加配置
    if grep -q "set linenumbers" "$nano_config"; then
      echo "行号已启用"
    else
      echo "set linenumbers" | tee -a "$nano_config" > /dev/null
      log "INFO" "启用行号"
    fi

    if grep -q "set autoindent" "$nano_config"; then
      echo "自动缩进已启用"
    else
      echo "set autoindent" | tee -a "$nano_config" > /dev/null
      log "INFO" "启用自动缩进"
    fi

    if grep -q "include /usr/share/nano/*.nanorc" "$nano_config"; then
      echo "语法高亮已启用"
    else
      echo "include /usr/share/nano/*.nanorc" | tee -a "$nano_config" > /dev/null
      log "INFO" "启用语法高亮"
    fi

    echo "nano 配置完成"
    log "INFO" "nano 配置完成"
  fi
  NANO_INSTALL
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
NANO_INSTALL
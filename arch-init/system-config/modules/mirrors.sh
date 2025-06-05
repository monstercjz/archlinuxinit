#!/bin/bash

# system-config/modules/mirrors.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/mirrors_setup.log"

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

MIRRORS_MENU() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}换源菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 换官方源${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 添加 archlinuxcn 源配置${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 导入 archlinuxcn GPG key${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}4. 刷新 GPG key${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}5. 添加 flathub 仓库${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) change_to_official_mirrors ;;
    2) add_archlinuxcn_mirror_config ;;
    3) import_archlinuxcn_gpg_key ;;
    4) refresh_gpg_keys ;;
    5) add_flathub_repo ;;
    0) exit 0 ;; # 返回 system_config_menu，由 system-config.sh 处理
    *) wait_right_choice ;;
  esac
}
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  MIRRORS_MENU
}

change_to_official_mirrors() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 备份当前 /etc/pacman.d/mirrorlist${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始备份当前 mirrorlist"
  if run_with_sudo cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.backup.current; then
    echo "备份完成: /etc/pacman.d/mirrorlist.backup.current"
    log "INFO" "成功将 /etc/pacman.d/mirrorlist 备份到 /etc/pacman.d/mirrorlist.backup.current"
  else
    echo "备份失败"
    log "ERROR" "备份 /etc/pacman.d/mirrorlist 失败"
    MIRRORS_MENU
    return
  fi

  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 2: 选择镜像源${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo "请选择镜像源："
  echo -e "${COLOR_YELLOW}1. 清华源${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 阿里源${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 中科大源${COLOR_RESET}"
  read -p "请输入数字选择镜像源: " mirror_choice
  case $mirror_choice in
    1)
      new_mirror="https://mirrors.tuna.tsinghua.edu.cn/archlinux/\$repo/os/\$arch"
      log "INFO" "选择的镜像源: 清华源"
      ;;
    2)
      new_mirror="http://mirrors.aliyun.com/archlinux/\$repo/os/\$arch"
      log "INFO" "选择的镜像源: 阿里源"
      ;;
    3)
      new_mirror="https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch"
      log "INFO" "选择的镜像源: 中科大源"
      ;;
    *)
      echo "无效选择，使用默认源"
      new_mirror="https://mirrors.ustc.edu.cn/archlinux/\$repo/os/\$arch"
      log "WARNING" "无效选择，使用默认源"
      ;;
  esac

  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 3: 替换 mirrorlist 为选择的源列表${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始替换 mirrorlist 为选择的源列表"
  if confirm_action; then
    if run_with_sudo sed -i "s/^#Server = https:\/\/mirrors\.ustc\.edu\.cn\/archlinux\/\$repo\/os\/\$arch/Server = $new_mirror/" /etc/pacman.d/mirrorlist; then
      echo "官方源更换完成"
      log "INFO" "官方源更换完成"
      echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
      echo -e "${COLOR_BLUE}步骤 4: 更新源${COLOR_RESET}"
      echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
      log "INFO" "开始更新源"
      if confirm_action; then
        if run_with_sudo pacman -Syyu; then
          echo "源更新完成"
          log "INFO" "源更新完成"
        fi
      fi
    fi
  fi
  MIRRORS_MENU
}

add_archlinuxcn_mirror_config() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 添加 archlinuxcn 源配置到 pacman.conf${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始添加 archlinuxcn 源配置到 pacman.conf"
  if confirm_action; then
    if run_with_sudo bash -c 'echo -e "\n[archlinuxcn]\nSigLevel = Optional TrustedOnly\n#清华源\nServer = https://mirrors.tuna.tsinghua.edu.cn/archlinuxcn/\$arch\n#中科大源\nServer = https://mirrors.ustc.edu.cn/archlinuxcn/\$arch\n#阿里源\nServer = https://mirrors.aliyun.com/archlinuxcn/\$arch" >> /etc/pacman.conf'; then
      echo "archlinuxcn 源配置添加完成"
      log "INFO" "archlinuxcn 源配置添加完成"
    fi
  fi
  MIRRORS_MENU
}

import_archlinuxcn_gpg_key() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 导入 archlinuxcn GPG key${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始导入 archlinuxcn GPG key"
  if confirm_action; then
    if run_with_sudo pacman -Sy archlinuxcn-keyring; then
      echo "archlinuxcn GPG key 导入完成"
      log "INFO" "archlinuxcn GPG key 导入完成"
      echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
      echo -e "${COLOR_BLUE}步骤 2: 刷新 pacman 源${COLOR_RESET}"
      echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
      log "INFO" "开始刷新 pacman 源"
      if confirm_action; then
        if run_with_sudo pacman -Sy; then
          echo "pacman 源刷新完成"
          log "INFO" "pacman 源刷新完成"
        fi
      fi
    fi
  fi
  MIRRORS_MENU
}

refresh_gpg_keys() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 1: 刷新 GPG key${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始刷新 GPG key"
  if confirm_action; then
    if run_with_sudo pacman-key --refresh-keys; then
      echo "GPG key 刷新完成"
      echo "密钥会存储在以下目录中/etc/pacman.d/gnupg/"
      echo "pacman-key --list-keys 查看密钥列表"
      log "INFO" "GPG key 刷新完成"
    fi
  fi
  MIRRORS_MENU
}

check_flatpak_installed() {
  if ! command -v flatpak &> /dev/null; then
    echo -e "${COLOR_RED}flatpak 未安装，请先安装 flatpak。${COLOR_RESET}"
    log "ERROR" "flatpak 未安装，请先安装 flatpak"
    return 1
  fi
  return 0
}

add_flathub_repo() {
  if check_flatpak_installed; then
    echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
    echo -e "${COLOR_BLUE}步骤 1: 添加 flathub 仓库${COLOR_RESET}"
    echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
    log "INFO" "开始添加 flathub 仓库"
    if confirm_action; then
      if run_with_sudo flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
        echo "flathub 仓库添加完成"
        log "INFO" "flathub 仓库添加完成"
        echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
        echo -e "${COLOR_BLUE}步骤 2: 刷新 flathub 仓库${COLOR_RESET}"
        echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
        log "INFO" "开始刷新 flathub 仓库"
        if confirm_action; then
          if run_with_sudo flatpak update --system flathub; then
            echo "flathub 仓库刷新完成"
            log "INFO" "flathub 仓库刷新完成"
          fi
        fi
      fi
    fi
  fi
  MIRRORS_MENU
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
MIRRORS_MENU
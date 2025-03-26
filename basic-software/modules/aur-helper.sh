
#!/bin/bash

# basic-software/modules/aur-helper.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/aur_helper_setup.log"

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

# 检查是否配置了 [archlinuxcn] 源
check_archlinuxcn_source() {
  if grep -q "\[archlinuxcn\]" /etc/pacman.conf; then
    return 0  # 配置了 [archlinuxcn] 源
  else
    return 1  # 未配置 [archlinuxcn] 源
  fi
}

AUR_HELPER_MENU() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}安装 AUR 助手菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 安装 yay${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 安装 paru${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 安装 octopi${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_yay ;;
    2) install_paru ;;
    3) install_octopi ;;
    0) exit 0 ;; # 返回 basic_software_menu，由 basic-software.sh 处理
    *) wait_right_choice ;;
  esac
}
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  AUR_HELPER_MENU
}


install_yay() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}安装 yay${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始安装 yay"

  # 步骤 1: 检查是否已安装 git
  echo -e "${COLOR_BLUE}步骤 1/5: 检查是否已安装 git${COLOR_RESET}"
  if ! command -v git &> /dev/null; then
    echo -e "${COLOR_YELLOW}git 未安装，正在安装...${COLOR_RESET}"
    log "INFO" "git 未安装，正在安装..."
    if run_with_sudo pacman -S --noconfirm git; then
      echo -e "${COLOR_GREEN}git 安装完成${COLOR_RESET}"
      log "INFO" "git 安装完成"
    else
      echo -e "${COLOR_RED}git 安装失败!${COLOR_RESET}"
      log "ERROR" "git 安装失败"
      read -n 1 -s -r -p "按任意键继续..."
      return 1
    fi
  else
    echo -e "${COLOR_GREEN}git 已经安装${COLOR_RESET}"
    log "INFO" "git 已经安装"
  fi

  # 步骤 2: 检查是否配置了 [archlinuxcn] 源
  echo -e "${COLOR_BLUE}步骤 2/5: 检查是否配置了 [archlinuxcn] 源${COLOR_RESET}"
  if check_archlinuxcn_source; then
    echo -e "${COLOR_GREEN}[archlinuxcn] 源已配置，使用 pacman 安装 yay${COLOR_RESET}"
    log "INFO" "[archlinuxcn] 源已配置，使用 pacman 安装 yay"
    if run_with_sudo pacman -S --noconfirm yay; then
      echo -e "${COLOR_GREEN}yay 安装完成${COLOR_RESET}"
      log "INFO" "yay 安装完成"
    else
      echo -e "${COLOR_RED}yay 安装失败!${COLOR_RESET}"
      log "ERROR" "yay 安装失败"
    fi
  else
    echo -e "${COLOR_YELLOW}[archlinuxcn] 源未配置，使用源码编译安装 yay${COLOR_RESET}"
    log "INFO" "[archlinuxcn] 源未配置，使用源码编译安装 yay"

    # 步骤 3: 创建临时目录
    echo -e "${COLOR_BLUE}步骤 3/5: 创建临时目录${COLOR_RESET}"
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    echo "临时目录创建完成: $temp_dir"
    log "INFO" "临时目录创建完成: $temp_dir"

    # 步骤 4: 克隆 yay 仓库
    echo -e "${COLOR_BLUE}步骤 4/5: 克隆 yay 仓库${COLOR_RESET}"
    if git clone https://aur.archlinux.org/yay.git; then
      echo "yay 仓库克隆完成"
      log "INFO" "yay 仓库克隆完成"
      cd yay

      # 步骤 5: 编译安装 yay
      echo -e "${COLOR_BLUE}步骤 5/5: 编译安装 yay${COLOR_RESET}"
      if makepkg -si --noconfirm; then
        echo -e "${COLOR_GREEN}yay 安装完成${COLOR_RESET}"
        log "INFO" "yay 安装完成"
      else
        echo -e "${COLOR_RED}yay 安装失败!${COLOR_RESET}"
        log "ERROR" "yay 安装失败"
      fi
    else
      echo -e "${COLOR_RED}克隆 yay 仓库失败!${COLOR_RESET}"
      log "ERROR" "克隆 yay 仓库失败"
    fi

    # 清理临时目录
    cd
    rm -rf "$temp_dir"
    echo "临时目录已清理: $temp_dir"
    log "INFO" "临时目录已清理: $temp_dir"
  fi

  read -n 1 -s -r -p "按任意键继续..."
  AUR_HELPER_MENU
}

install_paru() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}安装 paru${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始安装 paru"
# 步骤 3: 检查是否配置了 [archlinuxcn] 源
  echo -e "${COLOR_BLUE}步骤 1/6: 检查是否配置了 [archlinuxcn] 源${COLOR_RESET}"
  if check_archlinuxcn_source; then
    echo -e "${COLOR_GREEN}[archlinuxcn] 源已配置，使用 pacman 安装 paru${COLOR_RESET}"
    log "INFO" "[archlinuxcn] 源已配置，使用 pacman 安装 paru"
    if run_with_sudo pacman -S --noconfirm paru; then
      echo -e "${COLOR_GREEN}paru 安装完成${COLOR_RESET}"
      log "INFO" "paru 安装完成"
    else
      echo -e "${COLOR_RED}paru 安装失败!${COLOR_RESET}"
      log "ERROR" "paru 安装失败"
    fi
  else
    # 步骤 1: 检查是否已安装 git
    echo -e "${COLOR_BLUE}步骤 2/6: 检查是否已安装 git${COLOR_RESET}"
    if ! command -v git &> /dev/null; then
      echo -e "${COLOR_YELLOW}git 未安装，正在安装...${COLOR_RESET}"
      log "INFO" "git 未安装，正在安装..."
      if run_with_sudo pacman -S --noconfirm git; then
        echo -e "${COLOR_GREEN}git 安装完成${COLOR_RESET}"
        log "INFO" "git 安装完成"
      else
        echo -e "${COLOR_RED}git 安装失败!${COLOR_RESET}"
        log "ERROR" "git 安装失败"
        read -n 1 -s -r -p "按任意键继续..."
        return 1
      fi
    else
      echo -e "${COLOR_GREEN}git 已经安装${COLOR_RESET}"
      log "INFO" "git 已经安装"
    fi

    # 步骤 2: 检查是否已安装 rust
    echo -e "${COLOR_BLUE}步骤 3/6: 检查是否已安装 rust${COLOR_RESET}"
    if ! command -v rustc &> /dev/null; then
      echo -e "${COLOR_YELLOW}rust 未安装，正在安装...${COLOR_RESET}"
      log "INFO" "rust 未安装，正在安装..."
      if run_with_sudo pacman -S --noconfirm rust; then
        echo -e "${COLOR_GREEN}rust 安装完成${COLOR_RESET}"
        log "INFO" "rust 安装完成"
      else
        echo -e "${COLOR_RED}rust 安装失败!${COLOR_RESET}"
        log "ERROR" "rust 安装失败"
        read -n 1 -s -r -p "按任意键继续..."
        return 1
      fi
    else
      echo -e "${COLOR_GREEN}rust 已经安装${COLOR_RESET}"
      log "INFO" "rust 已经安装"
    fi

  
    echo -e "${COLOR_YELLOW}[archlinuxcn] 源未配置，使用源码编译安装 paru${COLOR_RESET}"
    log "INFO" "[archlinuxcn] 源未配置，使用源码编译安装 paru"

    # 步骤 4: 创建临时目录
    echo -e "${COLOR_BLUE}步骤 4/6: 创建临时目录${COLOR_RESET}"
    temp_dir=$(mktemp -d)
    cd "$temp_dir"
    echo "临时目录创建完成: $temp_dir"
    log "INFO" "临时目录创建完成: $temp_dir"

    # 步骤 5: 克隆 paru 仓库
    echo -e "${COLOR_BLUE}步骤 5/6: 克隆 paru 仓库${COLOR_RESET}"
    if git clone https://aur.archlinux.org/paru.git; then
      echo "paru 仓库克隆完成"
      log "INFO" "paru 仓库克隆完成"
      cd paru

      # 步骤 6: 编译安装 paru
      echo -e "${COLOR_BLUE}步骤 6/6: 编译安装 paru${COLOR_RESET}"
      # 降低编译优化级别，减少内存使用
      # makepkg -si --noconfirm;
      if makepkg -si --noconfirm --mflags "--jobs=1"; then
        echo -e "${COLOR_GREEN}paru 安装完成${COLOR_RESET}"
        log "INFO" "paru 安装完成"
      else
        echo -e "${COLOR_RED}paru 安装失败!${COLOR_RESET}"
        log "ERROR" "paru 安装失败"
      fi
    else
      echo -e "${COLOR_RED}克隆 paru 仓库失败!${COLOR_RESET}"
      log "ERROR" "克隆 paru 仓库失败"
    fi

    # 清理临时目录
    cd
    rm -rf "$temp_dir"
    echo "临时目录已清理: $temp_dir"
    log "INFO" "临时目录已清理: $temp_dir"
  fi

  read -n 1 -s -r -p "按任意键继续..."
  AUR_HELPER_MENU
}

install_octopi() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}安装 octopi${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始安装 octopi"

  # 检查是否已安装 octopi
  if pacman -Q octopi &>/dev/null; then
    echo -e "${COLOR_GREEN}octopi 已经安装${COLOR_RESET}"
    log "INFO" "octopi 已经安装"
  else
    # 步骤 1: 检查是否已安装 yay 或 paru
    echo -e "${COLOR_BLUE}步骤 1/3: 检查是否已安装 yay 或 paru${COLOR_RESET}"
    if command -v paru &> /dev/null; then
      echo -e "${COLOR_YELLOW}正在使用 paru 安装 octopi...${COLOR_RESET}"
      log "INFO" "正在使用 paru 安装 octopi..."
      if paru -S --noconfirm octopi; then
        echo -e "${COLOR_GREEN}octopi 安装成功!${COLOR_RESET}"
        log "INFO" "octopi 安装成功"
      else
        echo -e "${COLOR_RED}octopi 安装失败!${COLOR_RESET}"
        log "ERROR" "octopi 安装失败"
      fi
    elif command -v yay &> /dev/null; then
      echo -e "${COLOR_YELLOW}正在使用 yay 安装 octopi...${COLOR_RESET}"
      log "INFO" "正在使用 yay 安装 octopi..."
      if yay -S --noconfirm octopi; then
        echo -e "${COLOR_GREEN}octopi 安装成功!${COLOR_RESET}"
        log "INFO" "octopi 安装成功"
      else
        echo -e "${COLOR_RED}octopi 安装失败!${COLOR_RESET}"
        log "ERROR" "octopi 安装失败"
      fi
    else
      echo -e "${COLOR_RED}请先安装 yay 或 paru!${COLOR_RESET}"
      log "ERROR" "请先安装 yay 或 paru"
      read -n 1 -s -r -p "按任意键继续..."
      return 1
    fi
  fi

  # 步骤 2: 完成
  echo -e "${COLOR_BLUE}步骤 2/3: 完成${COLOR_RESET}"

  read -n 1 -s -r -p "按任意键继续..."
  AUR_HELPER_MENU
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
AUR_HELPER_MENU
#!/bin/bash

# basic-software/modules/nano.sh

# 获取调用 sudo 的原始用户
# SUDO_USER 变量在 sudo 模式下会被设置为原始用户的用户名。
# 如果脚本不是通过 sudo 运行（例如直接作为 root 运行），则 SUDO_USER 可能为空，
# 此时使用 whoami 来获取当前执行用户的用户名。
ORIGINAL_USER="${SUDO_USER:-$(whoami)}"

# 获取原始用户的家目录
# 如果 ORIGINAL_USER 是 root，其家目录就是 /root。
# 否则，使用 eval echo "~$ORIGINAL_USER" 来安全地获取该用户的家目录。
if [ "$ORIGINAL_USER" == "root" ]; then
    ORIGINAL_HOME="/root"
else
    ORIGINAL_HOME=$(eval echo "~$ORIGINAL_USER")
    # 也可以使用 getent passwd "$ORIGINAL_USER" | cut -d: -f6
    # 但 eval echo "~$USER" 在大多数情况下更简洁有效
fi

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
      sudo chmod 644 "$LOG_FILE" # 确保日志文件只有 root 用户可写，组和其他用户可读
      log "INFO" "设置日志文件权限为 640"
    else
      echo "日志文件创建失败"
      log "ERROR" "日志文件创建失败"
      exit 1
    fi
  fi
}

# 日志记录函数
log() {
  local level="$1"
  local message="$2"
  local color_code

  case "$level" in
    INFO)
      color_code="${COLOR_GREEN}" # Green
      ;;
    WARNING)
      color_code="${COLOR_YELLOW}" # Yellow
      ;;
    ERROR)
      color_code="${COLOR_RED}" # Red
      ;;
    *) # Default to blue for other levels
      color_code="${COLOR_BLUE}" # Blue
      ;;
  esac

  # 终端输出带颜色的日志
  echo -e "${color_code}$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message${COLOR_RESET}"

  # 文件中写入纯文本日志 (使用 sudo tee -a 确保以 root 权限写入日志文件)
  echo "$(date '+%Y-%m-%d %H:%M:%S') - [$level] $message" | sudo tee -a "$LOG_FILE" > /dev/null
}

# 以 sudo 运行命令的包装函数，并记录日志
run_with_sudo() {
  if sudo "$@"; then
    log "INFO" "命令 '$*' 执行成功"
  else
    log "ERROR" "命令 '$*' 执行失败"
    return 1 # 返回非零状态码表示失败
  fi
}

# 确认操作函数
confirm_action() {
  read -p "$(echo -e "${COLOR_GREEN}确认执行此操作? (y/n): ${COLOR_RESET}")" confirm
  if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    echo -e "${COLOR_RED}操作已取消${COLOR_RESET}"
    log "INFO" "操作已取消"
    return 1 # 返回非零状态码表示取消
  fi
  return 0 # 返回零状态码表示确认
}

# nano 主菜单
NANO_INSTALL() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}nano 安装菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 安装/重新安装 nano${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 设置 nano 为默认编辑器${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 配置 nano 支持语法高亮、显示行号和自动缩进${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) install_nano_editor ;;
    2) set_default_editor ;;
    3) configure_nano ;;
    0) return 0 ;; # 返回调用者 (basic_software_menu)
    *) wait_right_choice ;;
  esac
}

# 处理无效选择
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  NANO_INSTALL
}

# 安装或重新安装 nano 编辑器
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
        # --overwrite=* 强制覆盖文件，适用于系统升级或修复
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

# 设置 nano 为默认编辑器
set_default_editor() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 2: 设置 nano 为默认编辑器${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始设置 nano 为默认编辑器"

  # 检查 ORIGINAL_USER 的默认 shell，以确定修改哪个配置文件
  local user_shell=$(getent passwd "$ORIGINAL_USER" | cut -d: -f7) # 获取用户的默认shell
  local shell_config

  if [ "$user_shell" == "/bin/bash" ]; then
    shell_config="${ORIGINAL_HOME}/.bashrc"
  elif [ "$user_shell" == "/bin/zsh" ]; then
    shell_config="${ORIGINAL_HOME}/.zshrc"
  else
    echo "警告: 用户 '$ORIGINAL_USER' 的默认 shell ($user_shell) 不受支持，无法自动配置 EDITOR/VISUAL。"
    log "WARNING" "用户 '$ORIGINAL_USER' 的默认 shell ($user_shell) 不受支持，无法自动配置 EDITOR/VISUAL。"
    NANO_INSTALL # 返回菜单
    return
  fi

  # 确保目标配置文件存在 (如果不存在就创建它)
  if [ ! -f "$shell_config" ]; then
    echo "用户配置文件 $shell_config 不存在，正在创建..."
    run_with_sudo touch "$shell_config" || { log "ERROR" "无法创建用户配置文件 $shell_config"; NANO_INSTALL; return; }
    # 确保新创建的文件归原始用户所有
    run_with_sudo chown "$ORIGINAL_USER":"$(id -gn "$ORIGINAL_USER")" "$shell_config"
    log "INFO" "创建用户配置文件 $shell_config 并设置所有者为 $ORIGINAL_USER"
  fi

  # 备份当前 shell 配置文件 (备份文件也归原始用户所有)
  local timestamp=$(date +%Y%m%d_%H%M%S)
  local backup_file="${shell_config}.bak_${timestamp}"
  
  if run_with_sudo cp "$shell_config" "$backup_file"; then
    run_with_sudo chown "$ORIGINAL_USER":"$(id -gn "$ORIGINAL_USER")" "$backup_file"
    echo "备份当前 shell 配置文件到 $backup_file"
    log "INFO" "备份当前 shell 配置文件到 $backup_file"
  else
    echo "警告: 无法备份用户配置文件 $shell_config"
    log "WARNING" "无法备份用户配置文件 $shell_config"
  fi


  # 检查是否已设置 EDITOR 和 VISUAL
  # 使用 sudo -u "$ORIGINAL_USER" 以原始用户权限检查文件内容
  if sudo -u "$ORIGINAL_USER" grep -qE "^export EDITOR=nano$" "$shell_config" && \
     sudo -u "$ORIGINAL_USER" grep -qE "^export VISUAL=nano$" "$shell_config"; then
    echo "nano 已经设置为默认编辑器"
    log "INFO" "nano 已经设置为默认编辑器"
  else
    if confirm_action; then
      # 使用 sudo tee -a 写入文件，然后修正文件所有权
      echo "export EDITOR=nano" | sudo tee -a "$shell_config" > /dev/null
      echo "export VISUAL=nano" | sudo tee -a "$shell_config" > /dev/null
      
      # 确保被修改的配置文件归原始用户所有
      run_with_sudo chown "$ORIGINAL_USER":"$(id -gn "$ORIGINAL_USER")" "$shell_config"
      log "INFO" "设置 $shell_config 的所有者为 $ORIGINAL_USER"
      
      echo "nano 设置为默认编辑器"
      log "INFO" "nano 设置为默认编辑器"
      echo -e "${COLOR_YELLOW}请注意：更改需要手动重新加载 shell 配置文件才能生效。${COLOR_RESET}"
      echo -e "${COLOR_YELLOW}你可以运行 'source ${shell_config}' 或重新登录。${COLOR_RESET}"
    fi
  fi
  NANO_INSTALL
}

# 配置 nano 支持语法高亮、显示行号和自动缩进
configure_nano() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}步骤 3: 配置 nano 支持语法高亮、显示行号和自动缩进${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  log "INFO" "开始配置 nano"

  if confirm_action; then
    # 用户配置文件路径
    local nano_config="${ORIGINAL_HOME}/.nanorc"

    # 确保用户配置文件存在 (如果不存在就创建它)
    if [ ! -f "$nano_config" ]; then
      echo "用户配置文件 $nano_config 不存在，正在创建..."
      run_with_sudo touch "$nano_config" || { log "ERROR" "无法创建用户配置文件 $nano_config"; NANO_INSTALL; return; }
      # 确保新创建的文件归原始用户所有
      run_with_sudo chown "$ORIGINAL_USER":"$(id -gn "$ORIGINAL_USER")" "$nano_config"
      log "INFO" "创建用户配置文件 $nano_config 并设置所有者为 $ORIGINAL_USER"
    fi

    # 检查并添加配置项
    # 使用 sudo -u "$ORIGINAL_USER" 以原始用户权限检查文件内容
    # 使用 sudo tee -a 写入文件，并确保文件所有者在操作后是正确的
    
    # 行号
    if ! sudo -u "$ORIGINAL_USER" grep -qE "^set linenumbers$" "$nano_config"; then
      echo "set linenumbers" | sudo tee -a "$nano_config" > /dev/null
      log "INFO" "启用行号"
    else
      echo "行号已启用"
    fi

    # 自动缩进
    if ! sudo -u "$ORIGINAL_USER" grep -qE "^set autoindent$" "$nano_config"; then
      echo "set autoindent" | sudo tee -a "$nano_config" > /dev/null
      log "INFO" "启用自动缩进"
    else
      echo "自动缩进已启用"
    fi

    # 语法高亮
    if ! sudo -u "$ORIGINAL_USER" grep -qE "^include /usr/share/nano/\*\.nanorc$" "$nano_config"; then
      echo "include /usr/share/nano/*.nanorc" | sudo tee -a "$nano_config" > /dev/null
      log "INFO" "启用语法高亮"
    else
      echo "语法高亮已启用"
    fi

    # 再次确保 .nanorc 文件归原始用户所有，以防中间操作改变了权限
    run_with_sudo chown "$ORIGINAL_USER":"$(id -gn "$ORIGINAL_USER")" "$nano_config"
    log "INFO" "更新 $nano_config 的所有者为 $ORIGINAL_USER"

    echo "nano 配置完成"
    log "INFO" "nano 配置完成"
  fi
  NANO_INSTALL
}

# 清理函数：在脚本退出时执行
cleanup() {
  log "INFO" "脚本退出"
}

# 设置 trap 以捕获退出信号 (EXIT, ERR, INT, TERM)
# EXIT: 脚本正常退出时执行
# ERR: 任何命令返回非零状态码时执行 (配合 set -e)
# INT: 收到中断信号 (Ctrl+C) 时执行
# TERM: 收到终止信号时执行
trap cleanup EXIT ERR INT TERM

# 确保日志目录和文件存在
ensure_log_dir
ensure_log_file

# 启动菜单
NANO_INSTALL
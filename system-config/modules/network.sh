#!/bin/bash

# system-config/modules/network.sh

# 颜色变量
COLOR_BLUE="\e[34m"
COLOR_GREEN="\e[32m"
COLOR_RED="\e[31m"
COLOR_YELLOW="\e[33m"
COLOR_RESET="\e[0m"

# 日志变量
LOG_DIR="/var/log/arch-init"
LOG_FILE="$LOG_DIR/network_setup.log"

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
    NETWORK_CONFIG
    return 1
  fi
}

show_current_ip() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}当前 IP 信息${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  nmcli device show
  log "INFO" "展示当前 IP 信息"
}

get_interfaces() {
  nmcli -t -f DEVICE,TYPE device | grep 'ethernet\|wifi' | awk -F: '{print $1}'
}

get_connection_name() {
  local interface="$1"
  nmcli -t -f NAME,DEVICE connection show | grep "^.*:$interface$" | awk -F: '{print $1}'
}

set_ip_address() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}设置 IP 地址${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"

  # 获取所有网络接口
  interfaces=($(get_interfaces))
  if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "${COLOR_RED}没有可用的网络接口${COLOR_RESET}"
    log "ERROR" "没有可用的网络接口"
    NETWORK_CONFIG
    return
  fi

  echo "请选择网络接口:"
  for i in "${!interfaces[@]}"; do
    echo -e "${COLOR_YELLOW}$((i+1)). ${interfaces[$i]}${COLOR_RESET}"
  done
  read -p "请输入数字选择接口: " choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#interfaces[@]} ]; then
    interface=${interfaces[$((choice-1))]}
  else
    echo -e "${COLOR_RED}无效选择${COLOR_RESET}"
    log "ERROR" "无效选择"
    NETWORK_CONFIG
    return
  fi

  # 获取连接名称
  connection_name=$(get_connection_name "$interface")
  if [ -z "$connection_name" ]; then
    echo -e "${COLOR_RED}未找到与接口 $interface 对应的连接名称${COLOR_RESET}"
    log "ERROR" "未找到与接口 $interface 对应的连接名称"
    NETWORK_CONFIG
    return
  fi

  read -p "请输入 IP 地址 (例如 192.168.1.100): " ip_address

  echo "请选择子网掩码:"
  echo -e "${COLOR_YELLOW}1. 255.255.255.0 (24)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 255.255.0.0 (16)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 255.0.0.0 (8)${COLOR_RESET}"
  read -p "请输入数字选择子网掩码: " mask_choice

  case $mask_choice in
    1) prefix_length=24 ;;
    2) prefix_length=16 ;;
    3) prefix_length=8 ;;
    *)
      echo -e "${COLOR_RED}无效选择，默认使用 255.255.255.0 (24)${COLOR_RESET}"
      log "WARNING" "无效选择，默认使用 255.255.255.0 (24)"
      prefix_length=24
      ;;
  esac

  read -p "请输入网关 (例如 192.168.1.1): " gateway

  echo "请选择 DNS 服务器:"
  echo -e "${COLOR_YELLOW}1. Google DNS (8.8.8.8, 8.8.4.4)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. Cloudflare DNS (1.1.1.1, 1.0.0.1)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. AliDNS (223.5.5.5, 223.6.6.6)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}4. 自定义 DNS 服务器 (输入多个地址，用逗号分隔)${COLOR_RESET}"
  read -p "请输入数字选择 DNS 服务器: " dns_choice

  case $dns_choice in
    1) dns="8.8.8.8,8.8.4.4" ;;
    2) dns="1.1.1.1,1.0.0.1" ;;
    3) dns="223.5.5.5,223.6.6.6" ;;
    4)
      read -p "请输入自定义 DNS 服务器地址 (例如 8.8.8.8,8.8.4.4): " dns
      # 验证输入是否为有效的 IP 地址列表
      IFS=',' read -ra dns_array <<< "$dns"
      for ip in "${dns_array[@]}"; do
        if ! [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          echo -e "${COLOR_RED}无效的 DNS 地址: $ip${COLOR_RESET}"
          log "ERROR" "无效的 DNS 地址: $ip"
          NETWORK_CONFIG
          return
        fi
      done
      ;;
    *)
      echo -e "${COLOR_RED}无效选择，默认使用 Google DNS (8.8.8.8, 8.8.4.4)${COLOR_RESET}"
      log "WARNING" "无效选择，默认使用 Google DNS (8.8.8.8, 8.8.4.4)"
      dns="8.8.8.8,8.8.4.4"
      ;;
  esac

  if confirm_action; then
    # 禁用当前连接
    run_with_sudo nmcli connection down "$connection_name"
    
    # 修改连接配置
    run_with_sudo nmcli connection modify "$connection_name" ipv4.addresses "$ip_address/$prefix_length"
    run_with_sudo nmcli connection modify "$connection_name" ipv4.gateway "$gateway"
    run_with_sudo nmcli connection modify "$connection_name" ipv4.dns "$dns"
    run_with_sudo nmcli connection modify "$connection_name" ipv4.method manual
    
    # 启用连接
    run_with_sudo nmcli connection up "$connection_name"
    
    echo "IP 地址设置完成"
    log "INFO" "IP 地址设置完成: $ip_address/$prefix_length on $connection_name"
  fi
  NETWORK_CONFIG
}

modify_dns() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}修改 DNS 服务器${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"

  # 获取所有网络接口
  interfaces=($(get_interfaces))
  if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "${COLOR_RED}没有可用的网络接口${COLOR_RESET}"
    log "ERROR" "没有可用的网络接口"
    NETWORK_CONFIG
    return
  fi

  echo "请选择网络接口:"
  for i in "${!interfaces[@]}"; do
    echo -e "${COLOR_YELLOW}$((i+1)). ${interfaces[$i]}${COLOR_RESET}"
  done
  read -p "请输入数字选择接口: " choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#interfaces[@]} ]; then
    interface=${interfaces[$((choice-1))]}
  else
    echo -e "${COLOR_RED}无效选择${COLOR_RESET}"
    log "ERROR" "无效选择"
    NETWORK_CONFIG
    return
  fi

  # 获取连接名称
  connection_name=$(get_connection_name "$interface")
  if [ -z "$connection_name" ]; then
    echo -e "${COLOR_RED}未找到与接口 $interface 对应的连接名称${COLOR_RESET}"
    log "ERROR" "未找到与接口 $interface 对应的连接名称"
    NETWORK_CONFIG
    return
  fi

  echo "请选择 DNS 服务器:"
  echo -e "${COLOR_YELLOW}1. Google DNS (8.8.8.8, 8.8.4.4)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. Cloudflare DNS (1.1.1.1, 1.0.0.1)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. AliDNS (223.5.5.5, 223.6.6.6)${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}4. 自定义 DNS 服务器 (输入多个地址，用逗号分隔)${COLOR_RESET}"
  read -p "请输入数字选择 DNS 服务器: " dns_choice

  case $dns_choice in
    1) dns="8.8.8.8,8.8.4.4" ;;
    2) dns="1.1.1.1,1.0.0.1" ;;
    3) dns="223.5.5.5,223.6.6.6" ;;
    4)
      read -p "请输入自定义 DNS 服务器地址 (例如 8.8.8.8,8.8.4.4): " dns
      # 验证输入是否为有效的 IP 地址列表
      IFS=',' read -ra dns_array <<< "$dns"
      for ip in "${dns_array[@]}"; do
        if ! [[ $ip =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
          echo -e "${COLOR_RED}无效的 DNS 地址: $ip${COLOR_RESET}"
          log "ERROR" "无效的 DNS 地址: $ip"
          NETWORK_CONFIG
          return
        fi
      done
      ;;
    *)
      echo -e "${COLOR_RED}无效选择，默认使用 Google DNS (8.8.8.8, 8.8.4.4)${COLOR_RESET}"
      log "WARNING" "无效选择，默认使用 Google DNS (8.8.8.8, 8.8.4.4)"
      dns="8.8.8.8,8.8.4.4"
      ;;
  esac

  if confirm_action; then
    # 禁用当前连接
    run_with_sudo nmcli connection down "$connection_name"
    # 修改连接配置
    run_with_sudo nmcli connection modify "$connection_name" ipv4.dns "$dns"
    # 启用当前连接
    run_with_sudo nmcli connection up "$connection_name"
    echo "DNS 服务器设置完成"
    log "INFO" "DNS 服务器设置完成: $dns on $connection_name"
  fi
  NETWORK_CONFIG
}

modify_gateway() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}修改网关${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"

  # 获取所有网络接口
  interfaces=($(get_interfaces))
  if [ ${#interfaces[@]} -eq 0 ]; then
    echo -e "${COLOR_RED}没有可用的网络接口${COLOR_RESET}"
    log "ERROR" "没有可用的网络接口"
    NETWORK_CONFIG
    return
  fi

  echo "请选择网络接口:"
  for i in "${!interfaces[@]}"; do
    echo -e "${COLOR_YELLOW}$((i+1)). ${interfaces[$i]}${COLOR_RESET}"
  done
  read -p "请输入数字选择接口: " choice

  if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#interfaces[@]} ]; then
    interface=${interfaces[$((choice-1))]}
  else
    echo -e "${COLOR_RED}无效选择${COLOR_RESET}"
    log "ERROR" "无效选择"
    NETWORK_CONFIG
    return
  fi

  # 获取连接名称
  connection_name=$(get_connection_name "$interface")
  if [ -z "$connection_name" ]; then
    echo -e "${COLOR_RED}未找到与接口 $interface 对应的连接名称${COLOR_RESET}"
    log "ERROR" "未找到与接口 $interface 对应的连接名称"
    NETWORK_CONFIG
    return
  fi

  read -p "请输入新的网关地址 (例如 192.168.1.1): " gateway

  if confirm_action; then
    # 禁用当前连接
    run_with_sudo nmcli connection down "$connection_name"
    # 修改连接配置
    run_with_sudo nmcli connection modify "$connection_name" ipv4.gateway "$gateway"
    # 启用当前连接
    run_with_sudo nmcli connection up "$connection_name"
    echo "网关设置完成"
    log "INFO" "网关设置完成: $gateway on $connection_name"
  fi
  NETWORK_CONFIG
}

NETWORK_CONFIG() {
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_BLUE}网络地址设定菜单${COLOR_RESET}"
  echo -e "${COLOR_BLUE}==============================${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}1. 展示当前 IP 信息${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}2. 设置 IP 地址${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}3. 修改 DNS 服务器${COLOR_RESET}"
  echo -e "${COLOR_YELLOW}4. 修改网关${COLOR_RESET}"
  echo -e "${COLOR_RED}0. 返回上一级菜单${COLOR_RESET}"
  read -p "请选择菜单: " choice
  case $choice in
    1) show_current_ip ;;
    2) set_ip_address ;;
    3) modify_dns ;;
    4) modify_gateway ;;
    0) exit 0 ;; # 返回 system_config_menu，由 system-config.sh 处理
    *) wait_right_choice ;;
  esac
}
wait_right_choice() {
  echo -e "${COLOR_RED}无效选择，返回当前菜单继续等待选择${COLOR_RESET}"
  NETWORK_CONFIG
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
NETWORK_CONFIG
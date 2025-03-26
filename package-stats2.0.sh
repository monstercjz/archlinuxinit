#!/bin/bash

# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; NC='\033[0m'

# 获取系统初始安装日期
get_install_date() {
    # 首先尝试从/etc/machine-id获取系统安装时间
    if [ -f "/etc/machine-id" ]; then
        install_date=$(stat -c %y /etc/machine-id | cut -d' ' -f1,2)
        if [ -n "$install_date" ]; then
            echo "$install_date"
            return 0
        fi
    fi
    
    # 如果无法从/etc/machine-id获取，尝试从pacman日志中获取系统初始安装日期
    if [ -f "/var/log/pacman.log" ]; then
        # 获取最早的pacman日志日期，支持ISO 8601格式
        first_log_line=$(head -n 1 /var/log/pacman.log)
        
        # 尝试匹配ISO 8601格式 [YYYY-MM-DDThh:mm:ss+0000]
        if [[ "$first_log_line" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4})\] ]]; then
            # 提取日期并转换格式
            iso_date="${BASH_REMATCH[1]}"
            # 转换为标准格式 YYYY-MM-DD HH:MM
            install_date=$(echo "$iso_date" | sed 's/T/ /' | cut -d'+' -f1 | cut -d'-' -f1-3 | cut -c1-16)
            echo "$install_date"
            return 0
        else
            # 尝试旧格式
            install_date=$(echo "$first_log_line" | cut -d' ' -f1,2)
            if [ -n "$install_date" ]; then
                echo "$install_date"
                return 0
            fi
        fi
    fi
    
    # 如果无法从日志获取，则使用pacman.log文件的创建时间
    if [ -f "/var/log/pacman.log" ]; then
        install_date=$(stat -c %y /var/log/pacman.log | cut -d' ' -f1,2)
        echo "$install_date"
        return 0
    fi
    
    # 如果都无法获取，则使用当前时间减去30天作为估计
    echo "$(date -d "30 days ago" "+%Y-%m-%d %H:%M")"
    return 1
}

# 获取手动安装的软件包列表
get_manually_installed_packages() {
    local install_date=$1
    local sort_by=$2
    
    echo -e "${BLUE}系统初始安装日期: $install_date${NC}"
    echo -e "${YELLOW}正在统计手动安装的软件包...${NC}"
    
    # 获取所有明确安装的包（非依赖）
    explicit_packages=$(pacman -Qe | cut -d' ' -f1)
    
    # 创建临时文件
    temp_file=$(mktemp)
    
    # 遍历所有明确安装的包，检查安装日期
    for pkg in $explicit_packages; do
        # 从pacman日志中获取安装日期
        install_log=$(grep "\[ALPM\] installed $pkg" /var/log/pacman.log | head -n 1)
        
        if [ -n "$install_log" ]; then
            # 提取并格式化日期，处理类似 "[2025-03-23T19:52:45+0000] [ALPM]" 的格式
            if [[ "$install_log" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4})\] ]]; then
                # 使用bash正则表达式捕获组提取日期
                pkg_date="${BASH_REMATCH[1]}"
            else
                # 如果没有匹配到新格式，尝试旧格式
                pkg_date=$(echo "$install_log" | cut -d' ' -f1,2)
            fi
            pkg_size=$(pacman -Qi "$pkg" | grep "Installed Size" | cut -d':' -f2 | tr -d ' ')
            
            # 比较日期，只保留系统初始安装日期之后的包
            # 处理不同格式的日期比较
            install_date_for_compare="$install_date"
            pkg_date_for_compare="$pkg_date"
            
            # 如果是ISO 8601格式，转换为date命令可以理解的格式
            if [[ "$pkg_date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
                # 提取日期部分和时间部分，去除时区信息
                date_part=$(echo "$pkg_date" | cut -dT -f1)
                time_part=$(echo "$pkg_date" | cut -dT -f2 | cut -d+ -f1 | cut -d- -f1)
                pkg_date_for_compare="$date_part $time_part"
            fi
            
            # 转换为Unix时间戳进行比较
            install_date_epoch=$(date -d "$install_date_for_compare" +%s 2>/dev/null)
            pkg_date_epoch=$(date -d "$pkg_date_for_compare" +%s 2>/dev/null)
            
            # 如果日期转换成功，则进行比较
            if [ -n "$install_date_epoch" ] && [ -n "$pkg_date_epoch" ] && [ "$pkg_date_epoch" -gt "$install_date_epoch" ]; then
                # 检查是否为AUR包
                if pacman -Qi "$pkg" 2>/dev/null | grep -q "^Repository.*local$"; then
                    repo="AUR/Local"
                else
                    repo="Official"
                fi
                
                # 写入临时文件: 日期 | 包名 | 大小 | 仓库
                echo "$pkg_date|$pkg|$pkg_size|$repo" >> "$temp_file"
            fi
        fi
    done
    
    # 根据排序方式对结果进行排序
    case "$sort_by" in
        "date")
            # 按日期排序（最新的在前）
            sort -r -t'|' -k1 "$temp_file"
            ;;
        "size")
            # 按大小排序（最大的在前）
            sort -t'|' -k3hr "$temp_file"
            ;;
        "name")
            # 按名称排序
            sort -t'|' -k2 "$temp_file"
            ;;
        *)
            # 默认按日期排序
            sort -r -t'|' -k1 "$temp_file"
            ;;
    esac
    
    # 删除临时文件
    rm -f "$temp_file"
}

# 显示软件包统计信息
show_package_stats() {
    # 显示排序选项
    echo -e "${CYAN}========== 软件包统计 ===========${NC}"
    echo -e "${GREEN}请选择排序方式:${NC}"
    echo -e "${GREEN}1. 按安装日期排序（最新的在前）${NC}"
    echo -e "${GREEN}2. 按软件包大小排序（最大的在前）${NC}"
    echo -e "${GREEN}3. 按软件包名称排序${NC}"
    echo -e "${CYAN}=================================${NC}"
    
    read -p "请输入选项: " choice
    
    # 获取系统初始安装日期
    install_date=$(get_install_date)
    
    # 根据选择的排序方式获取软件包列表
    case $choice in
        1) packages=$(get_manually_installed_packages "$install_date" "date") ;;
        2) packages=$(get_manually_installed_packages "$install_date" "size") ;;
        3) packages=$(get_manually_installed_packages "$install_date" "name") ;;
        *) 
            echo -e "${RED}无效选项${NC}"
            packages=$(get_manually_installed_packages "$install_date" "date")
            ;;
    esac
    
    # 显示结果
    echo -e "\n${CYAN}========== 手动安装的软件包 ===========${NC}"
    echo -e "${YELLOW}日期          | 软件包名称                | 大小      | 仓库${NC}"
    echo -e "${YELLOW}------------------------------------------------${NC}"
    
    # 格式化输出
    echo "$packages" | while IFS='|' read -r date name size repo; do
        # 格式化日期显示，将ISO 8601格式转换为更友好的格式
        if [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
            # 处理ISO 8601格式
            # 提取日期部分和时间部分
            date_part=$(echo "$date" | cut -dT -f1)
            time_part=$(echo "$date" | cut -dT -f2 | cut -d+ -f1 | cut -d- -f1 | cut -c1-5)
            formatted_date="$date_part $time_part"
        else
            formatted_date="$date"
        fi
        printf "%-14s | %-25s | %-9s | %s\n" "$formatted_date" "$name" "$size" "$repo"
    done
    
    # 统计总数
    total=$(echo "$packages" | wc -l)
    official=$(echo "$packages" | grep -c "Official")
    aur=$(echo "$packages" | grep -c "AUR/Local")
    
    echo -e "\n${CYAN}========== 统计信息 ===========${NC}"
    echo -e "${GREEN}总共手动安装的软件包: $total${NC}"
    echo -e "${GREEN}官方仓库软件包: $official${NC}"
    echo -e "${GREEN}AUR/本地软件包: $aur${NC}"
}

# 如果直接执行此脚本，则运行统计函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    show_package_stats
fi
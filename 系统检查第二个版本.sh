#!/bin/bash

# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; NC='\033[0m'

# 获取系统环境信息
get_system_info() {
    echo -e "${YELLOW}正在收集系统环境信息...${NC}" >&2
    
    # 创建临时文件
    temp_system_info=$(mktemp)
    
    # 收集系统版本信息
    echo -e "${BLUE}正在获取系统版本信息...${NC}" >&2
    if [ -f "/etc/os-release" ]; then
        os_name=$(grep -E "^NAME=" /etc/os-release | cut -d'"' -f2)
        os_version=$(grep -E "^VERSION=" /etc/os-release | cut -d'"' -f2)
        os_id=$(grep -E "^ID=" /etc/os-release | cut -d'=' -f2)
        
        # 检查系统版本是否为空
        if [ -z "$os_version" ]; then
            echo -e "${YELLOW}os-release文件中VERSION字段为空，尝试其他方法获取系统版本...${NC}" >&2
            
            # 检查是否为Arch Linux
            if [ "$os_id" = "arch" ] || [ -f "/etc/arch-release" ]; then
                echo -e "${BLUE}检测到Arch Linux系统，尝试获取版本信息...${NC}" >&2
                
                # 对于Arch Linux，使用pacman获取系统版本
                if command -v pacman &> /dev/null; then
                    # 获取pacman版本作为系统版本参考
                    pacman_version=$(pacman -Q pacman | cut -d' ' -f2)
                    os_version="Rolling Release (pacman $pacman_version)"
                    echo -e "${GREEN}成功获取Arch Linux版本信息${NC}" >&2
                fi
            fi
            
            # 尝试使用lsb_release命令获取系统版本
            if [ -z "$os_version" ] && command -v lsb_release &> /dev/null; then
                echo -e "${BLUE}尝试使用lsb_release命令获取系统版本...${NC}" >&2
                os_version=$(lsb_release -r | cut -f2)
                echo -e "${GREEN}成功使用lsb_release获取系统版本${NC}" >&2
            fi
            
            # 如果仍然无法获取版本，设置为默认值
            if [ -z "$os_version" ]; then
                os_version="Rolling Release"
                echo -e "${YELLOW}无法获取具体版本号，使用默认值${NC}" >&2
            fi
        fi
        
        echo "系统名称: $os_name" >> "$temp_system_info"
        echo "系统版本: $os_version" >> "$temp_system_info"
        echo "系统ID: $os_id" >> "$temp_system_info"
        echo -e "${GREEN}系统版本信息获取成功${NC}" >&2
    else
        echo "系统名称: 未知" >> "$temp_system_info"
        echo "系统版本: 未知" >> "$temp_system_info"
        echo -e "${RED}无法获取系统版本信息${NC}" >&2
    fi
    
    # 收集内核版本信息
    echo -e "${BLUE}正在获取内核版本信息...${NC}" >&2
    kernel_version=$(uname -r)
    echo "内核版本: $kernel_version" >> "$temp_system_info"
    echo -e "${GREEN}内核版本信息获取成功${NC}" >&2
    
    # 收集CPU信息
    echo -e "${BLUE}正在获取CPU信息...${NC}" >&2
    if [ -f "/proc/cpuinfo" ]; then
        cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | cut -d':' -f2 | sed 's/^[ \t]*//')
        cpu_cores=$(grep -c "processor" /proc/cpuinfo)
        echo "CPU型号: $cpu_model" >> "$temp_system_info"
        echo "CPU核心数: $cpu_cores" >> "$temp_system_info"
        echo -e "${GREEN}CPU信息获取成功${NC}" >&2
    else
        echo "CPU型号: 未知" >> "$temp_system_info"
        echo "CPU核心数: 未知" >> "$temp_system_info"
        echo -e "${RED}无法获取CPU信息${NC}" >&2
    fi
    
    # 收集内存信息
    echo -e "${BLUE}正在获取内存信息...${NC}" >&2
    if [ -f "/proc/meminfo" ]; then
        total_mem=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
        # 转换为GB并保留两位小数
        total_mem_gb=$(echo "scale=2; $total_mem/1024/1024" | bc)
        echo "内存大小: ${total_mem_gb}GB" >> "$temp_system_info"
        echo -e "${GREEN}内存信息获取成功${NC}" >&2
    else
        echo "内存大小: 未知" >> "$temp_system_info"
        echo -e "${RED}无法获取内存信息${NC}" >&2
    fi
    
    # 收集显卡信息
    echo -e "${BLUE}正在获取显卡信息...${NC}" >&2
    if command -v lspci &> /dev/null; then
        gpu_info=$(lspci | grep -E 'VGA|3D|Display' | sed 's/^.*: //')
        if [ -n "$gpu_info" ]; then
            echo "显卡信息: $gpu_info" >> "$temp_system_info"
            echo -e "${GREEN}显卡信息获取成功${NC}" >&2
        else
            echo "显卡信息: 未检测到" >> "$temp_system_info"
            echo -e "${YELLOW}未检测到显卡信息${NC}" >&2
        fi
    else
        echo "显卡信息: 未知（lspci命令不可用）" >> "$temp_system_info"
        echo -e "${RED}无法获取显卡信息（lspci命令不可用）${NC}" >&2
    fi
    
    # 收集磁盘使用情况
    echo -e "${BLUE}正在获取磁盘使用情况...${NC}" >&2
    if command -v df &> /dev/null; then
        root_usage=$(df -h / | awk 'NR==2 {print "总大小: "$2", 已用: "$3", 可用: "$4", 使用率: "$5}')
        echo "根分区使用情况: $root_usage" >> "$temp_system_info"
        echo -e "${GREEN}磁盘使用情况获取成功${NC}" >&2
    else
        echo "根分区使用情况: 未知" >> "$temp_system_info"
        echo -e "${RED}无法获取磁盘使用情况${NC}" >&2
    fi
    
    # 收集系统运行时间
    echo -e "${BLUE}正在获取系统运行时间...${NC}" >&2
    if command -v uptime &> /dev/null; then
        uptime_info=$(uptime -p | sed 's/^up //')
        echo "系统运行时间: $uptime_info" >> "$temp_system_info"
        echo -e "${GREEN}系统运行时间获取成功${NC}" >&2
    else
        echo "系统运行时间: 未知" >> "$temp_system_info"
        echo -e "${RED}无法获取系统运行时间${NC}" >&2
    fi
    
    # 收集系统语言环境
    echo -e "${BLUE}正在获取系统语言环境...${NC}" >&2
    if [ -n "$LANG" ]; then
        echo "系统语言环境: $LANG" >> "$temp_system_info"
        echo -e "${GREEN}系统语言环境获取成功${NC}" >&2
    else
        echo "系统语言环境: 未知" >> "$temp_system_info"
        echo -e "${RED}无法获取系统语言环境${NC}" >&2
    fi
    
    # 输出收集到的系统信息
    cat "$temp_system_info"
    
    # 删除临时文件
    rm -f "$temp_system_info"
    
    echo -e "${GREEN}系统环境信息收集完成!${NC}" >&2
}

# 获取系统初始安装日期
get_install_date() {
    echo -e "${YELLOW}正在获取系统初始安装日期...${NC}" >&2
    
    # 首先尝试从/etc/machine-id获取系统安装时间
    if [ -f "/etc/machine-id" ]; then
        echo -e "${BLUE}尝试从 /etc/machine-id 文件的创建时间获取系统安装日期...${NC}" >&2
        install_date=$(stat -c %y /etc/machine-id | cut -d' ' -f1,2)
        if [ -n "$install_date" ]; then
            echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: /etc/machine-id 文件创建时间)${NC}" >&2
            echo "$install_date"
            return 0
        fi
    fi
    # 尝试使用/lost+found目录的创建时间作为系统安装日期
    if [ -d "/lost+found" ]; then
        echo -e "${BLUE}尝试使用 /lost+found 目录的创建时间作为系统安装日期...${NC}" >&2
        # 使用stat -c %w获取/lost+found的创建时间
        install_date=$(stat -c %w /lost+found | cut -d' ' -f1,2)
        if [ -n "$install_date" ]; then
            echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: /lost+found 目录创建时间)${NC}" >&2
            echo "$install_date"
            return 0
        fi
    fi
    # 尝试使用journalctl --list-boots获取最早的启动记录时间
    if command -v journalctl &> /dev/null; then
        echo -e "${BLUE}尝试从 journalctl 启动记录获取系统安装日期...${NC}" >&2
        # 获取最早的启动记录（IDX值最小的那条记录）
        earliest_boot=$(journalctl --list-boots | sort -n | grep -v "^$" | head -n 1)
        if [ -n "$earliest_boot" ]; then
            # 提取第一次启动的时间，格式类似：Mon 2025-03-24 03:54:41 CST
            boot_date=$(echo "$earliest_boot" | awk '{print $4, $5, $6}')
            # 转换为标准格式 YYYY-MM-DD HH:MM
            install_date=$(date -d "$boot_date" "+%Y-%m-%d %H:%M" 2>/dev/null)
            if [ -n "$install_date" ]; then
                echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: journalctl 最早启动记录)${NC}" >&2
                echo "$install_date"
                return 0
            fi
        fi
    fi
    
    # 如果无法从/etc/machine-id获取，尝试从pacman日志中获取系统初始安装日期
    if [ -f "/var/log/pacman.log" ]; then
        echo -e "${BLUE}尝试从 pacman.log 日志文件获取系统初始安装日期...${NC}" >&2
        # 获取最早的pacman日志日期，支持ISO 8601格式
        first_log_line=$(head -n 1 /var/log/pacman.log)
        
        # 尝试匹配ISO 8601格式 [YYYY-MM-DDThh:mm:ss+0000]
        if [[ "$first_log_line" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4})\] ]]; then
            # 提取日期并转换格式
            iso_date="${BASH_REMATCH[1]}"
            # 转换为标准格式 YYYY-MM-DD HH:MM
            install_date=$(echo "$iso_date" | sed 's/T/ /' | cut -d'+' -f1 | cut -d'-' -f1-3 | cut -c1-16)
            echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: pacman.log 第一行日志时间 - ISO 8601格式)${NC}" >&2
            echo "$install_date"
            return 0
        else
            # 尝试旧格式
            install_date=$(echo "$first_log_line" | cut -d' ' -f1,2)
            if [ -n "$install_date" ]; then
                echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: pacman.log 第一行日志时间 - 旧格式)${NC}" >&2
                echo "$install_date"
                return 0
            fi
        fi
    fi
    
    # 如果无法从日志获取，则使用pacman.log文件的创建时间
    if [ -f "/var/log/pacman.log" ]; then
        echo -e "${BLUE}尝试使用 pacman.log 文件的创建时间作为系统安装日期...${NC}" >&2
        install_date=$(stat -c %y /var/log/pacman.log | cut -d' ' -f1,2)
        echo -e "${GREEN}成功获取系统安装日期: $install_date (来源: pacman.log 文件创建时间)${NC}" >&2
        echo "$install_date"
        return 0
    fi
    
    
    
    # 如果都无法获取，则使用当前时间减去30天作为估计
    echo -e "${YELLOW}无法获取准确的系统安装日期，使用当前时间减去30天作为估计值...${NC}" >&2
    install_date=$(date -d "30 days ago" "+%Y-%m-%d %H:%M")
    echo -e "${GREEN}估计的系统安装日期: $install_date (来源: 当前时间减去30天)${NC}" >&2
    echo "$install_date"
    return 1
}

# 获取手动安装的软件包列表
get_manually_installed_packages() {
    local install_date=$1
    local sort_by=$2
    
    # 创建临时文件
    temp_file=$(mktemp)
    temp_output_file=$(mktemp)
    
    # 输出调试信息到标准错误，而不是标准输出
    echo -e "${BLUE}系统初始安装日期: $install_date${NC}" >&2
    echo -e "${YELLOW}正在统计手动安装的软件包...${NC}" >&2
    
    # 获取所有明确安装的包（非依赖）
    echo -e "${BLUE}正在获取所有明确安装的软件包（非依赖）...${NC}" >&2
    explicit_packages=$(pacman -Qe | cut -d' ' -f1)
    total_packages=$(echo "$explicit_packages" | wc -l)
    echo -e "${GREEN}找到 $total_packages 个明确安装的软件包${NC}" >&2
    
    # 遍历所有明确安装的包，检查安装日期
    echo -e "${BLUE}正在分析每个软件包的安装日期...${NC}" >&2
    counter=0
    for pkg in $explicit_packages; do
        # 更新计数器并显示进度
        counter=$((counter + 1))
        if [ $((counter % 10)) -eq 0 ] || [ $counter -eq 1 ] || [ $counter -eq $total_packages ]; then
            echo -e "${YELLOW}正在处理: $counter / $total_packages ($(($counter * 100 / $total_packages))%)${NC}" >&2
        fi
        
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
                # 检查是否为AUR包（使用pacman -Qm命令）
                if pacman -Qm | grep -q "^$pkg "; then
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
    echo -e "${BLUE}正在按 $sort_by 对结果进行排序...${NC}" >&2
    case "$sort_by" in
        "date")
            # 按日期排序（最新的在前）
            echo -e "${GREEN}按安装日期排序（最新的在前）${NC}" >&2
            sort -r -t'|' -k1 "$temp_file" > "$temp_output_file"
            ;;
        "size")
            # 按大小排序（最大的在前）
            echo -e "${GREEN}按软件包大小排序（最大的在前）${NC}" >&2
            sort -t'|' -k3hr "$temp_file" > "$temp_output_file"
            ;;
        "name")
            # 按名称排序
            echo -e "${GREEN}按软件包名称排序（字母顺序）${NC}" >&2
            sort -t'|' -k2 "$temp_file" > "$temp_output_file"
            ;;
        *)
            # 默认按日期排序
            echo -e "${GREEN}使用默认排序方式：按安装日期排序（最新的在前）${NC}" >&2
            sort -r -t'|' -k1 "$temp_file" > "$temp_output_file"
            ;;
    esac
    
    # 输出排序后的结果到标准输出
    cat "$temp_output_file"
    
    # 删除临时文件
    rm -f "$temp_file" "$temp_output_file"
}

# 显示软件包统计信息
show_package_stats() {
    echo -e "${CYAN}========== 开始软件包统计 ===========${NC}"
    echo -e "${BLUE}此工具将分析您系统中手动安装的软件包和系统环境信息，并提供详细统计信息${NC}"
    
    # 显示排序选项
    echo -e "${CYAN}========== 软件包统计 ===========${NC}"
    echo -e "${GREEN}请选择排序方式:${NC}"
    echo -e "${GREEN}1. 按安装日期排序（最新的在前）${NC}"
    echo -e "${GREEN}2. 按软件包大小排序（最大的在前）${NC}"
    echo -e "${GREEN}3. 按软件包名称排序${NC}"
    echo -e "${CYAN}=================================${NC}"
    
    # 创建保存目录
    echo -e "${BLUE}正在准备保存目录...${NC}"
    save_dir="$HOME/package-stats"
    if [ ! -d "$save_dir" ]; then
        echo -e "${YELLOW}创建保存目录: $save_dir${NC}"
        mkdir -p "$save_dir"
    else
        echo -e "${GREEN}保存目录已存在: $save_dir${NC}"
    fi
    
    read -p "请输入选项: " choice
    
    # 获取系统初始安装日期
    echo -e "${BLUE}正在获取系统初始安装日期...${NC}"
    install_date=$(get_install_date)
    
    # 获取系统环境信息
    echo -e "${BLUE}正在获取系统环境信息...${NC}"
    system_info=$(get_system_info)
    
    # 根据选择的排序方式获取软件包列表
    echo -e "${BLUE}根据您的选择获取软件包列表...${NC}"
    case $choice in
        1) 
            echo -e "${GREEN}您选择了: 按安装日期排序${NC}"
            packages=$(get_manually_installed_packages "$install_date" "date") 
            ;;
        2) 
            echo -e "${GREEN}您选择了: 按软件包大小排序${NC}"
            packages=$(get_manually_installed_packages "$install_date" "size") 
            ;;
        3) 
            echo -e "${GREEN}您选择了: 按软件包名称排序${NC}"
            packages=$(get_manually_installed_packages "$install_date" "name") 
            ;;
        *) 
            echo -e "${RED}无效选项，使用默认排序方式（按安装日期）${NC}"
            packages=$(get_manually_installed_packages "$install_date" "date")
            ;;
    esac
    
    # 显示结果
    echo -e "\n${CYAN}========== 手动安装的软件包 ===========${NC}"
    echo -e "${BLUE}正在格式化并显示结果...${NC}"
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
    
    # 创建临时文件来存储包信息，避免管道处理导致的变量内容丢失
    temp_count_file=$(mktemp)
    
    # 将包信息写入临时文件
    echo "$packages" > "$temp_count_file"
    
    # 统计总数
    echo -e "${BLUE}正在统计软件包数量...${NC}"
    if [ ! -s "$temp_count_file" ]; then
        # 如果文件为空，设置所有计数为0
        echo -e "${YELLOW}未找到任何手动安装的软件包${NC}"
        total=0
        official=0
        aur=0
    else
        # 使用临时文件进行统计，避免管道处理可能导致的问题
        # 统计包含竖线分隔符的行数作为总数，排除标题行
        total=$(grep -c "|" "$temp_count_file")
        # 统计包含Official的行数
        official=$(grep -c "Official" "$temp_count_file")
        # 统计包含AUR/Local的行数
        aur=$(grep -c "AUR/Local" "$temp_count_file")
        
        # 确保计数不为空
        [ -z "$total" ] && total=0
        [ -z "$official" ] && official=0
        [ -z "$aur" ] && aur=0
        
        echo -e "${GREEN}统计完成: 找到 $total 个手动安装的软件包${NC}"
    fi
    
    # 清理临时文件
    rm -f "$temp_count_file"
    
    echo -e "\n${CYAN}========== 系统环境信息 ===========${NC}"
    echo -e "${BLUE}正在显示系统环境信息...${NC}"
    echo "$system_info" | while IFS= read -r line; do
        echo -e "${GREEN}$line${NC}"
    done
    
    echo -e "\n${CYAN}========== 统计信息 ===========${NC}"
    echo -e "${GREEN}总共手动安装的软件包: $total${NC}"
    echo -e "${GREEN}官方仓库软件包: $official${NC}"
    echo -e "${GREEN}AUR/本地软件包: $aur${NC}"
    
    # 生成保存文件名（使用日期时间作为文件名的一部分）
    echo -e "${BLUE}正在准备保存统计结果...${NC}"
    timestamp=$(date +"%Y%m%d_%H%M%S")
    save_file="$save_dir/package_stats_$timestamp.txt"
    echo -e "${GREEN}将保存结果到文件: $save_file${NC}"
    
    # 将结果保存到文件
    echo -e "${BLUE}正在将统计结果保存到文件...${NC}"
    {
        echo "========== 软件包统计 ==========="
        echo "系统初始安装日期: $install_date"
        echo ""
        echo "========== 系统环境信息 ==========="
        echo "$system_info"
        echo ""
        echo "========== 手动安装的软件包 ==========="
        echo "日期          | 软件包名称                | 大小      | 仓库"
        echo "------------------------------------------------"
        
        # 将包信息写入文件
        echo "$packages" | while IFS='|' read -r date name size repo; do
            # 格式化日期显示
            if [[ "$date" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]; then
                date_part=$(echo "$date" | cut -dT -f1)
                time_part=$(echo "$date" | cut -dT -f2 | cut -d+ -f1 | cut -d- -f1 | cut -c1-5)
                formatted_date="$date_part $time_part"
            else
                formatted_date="$date"
            fi
            printf "%-14s | %-25s | %-9s | %s\n" "$formatted_date" "$name" "$size" "$repo"
        done
        
        echo ""
        echo "========== 统计信息 ==========="
        echo "总共手动安装的软件包: $total"
        echo "官方仓库软件包: $official"
        echo "AUR/本地软件包: $aur"
    } > "$save_file"
    echo -e "${GREEN}统计结果已成功保存到文件!${NC}"
    
    echo -e "\n${YELLOW}统计结果已保存到: ${CYAN}$save_file${NC}"
    
    # 创建仅包含软件包名称的列表文件，用于一键安装
    echo -e "${BLUE}正在创建软件包名称列表文件（用于一键安装）...${NC}"
    manual_list_file="$save_dir/manual_packages_$timestamp.txt"
    
    # 提取软件包名称并保存到文件
    echo -e "${YELLOW}正在提取软件包名称...${NC}"
    echo "$packages" | while IFS='|' read -r date name size repo; do
        echo "$name"
    done > "$manual_list_file"
    
    echo -e "${GREEN}软件包名称列表已成功创建!${NC}"
    echo -e "${YELLOW}软件包名称列表已保存到: ${CYAN}$manual_list_file${NC}"
    echo -e "${BLUE}提示: 您可以使用此列表文件进行一键安装，例如:${NC}"
    echo -e "${CYAN}  sudo pacman -S --needed - < $manual_list_file${NC}"
}

# 如果直接执行此脚本，则运行统计函数
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${CYAN}========== 软件包统计工具 ===========${NC}"
    echo -e "${BLUE}此工具将帮助您分析系统中手动安装的软件包${NC}"
    echo -e "${BLUE}并提供详细的统计信息和报告${NC}"
    echo -e "${CYAN}===================================${NC}"
    echo ""
    show_package_stats
    
    echo -e "\n${CYAN}========== 使用提示 ===========${NC}"
    echo -e "${BLUE}1. 统计结果已保存到 $HOME/package-stats 目录${NC}"
    echo -e "${BLUE}2. 软件包名称列表也已保存到 $HOME/package-stats 目录${NC}"
    echo -e "${BLUE}3. 您可以使用此列表在新系统上一键安装所有软件包:${NC}"
    echo -e "${CYAN}   sudo pacman -S --needed - < $manual_list_file${NC}"
    echo -e "${CYAN}===================================${NC}"
fi
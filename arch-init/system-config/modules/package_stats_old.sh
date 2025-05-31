#!/bin/bash
# ==========================
# 脚本名称: package_stats4.0.sh
# 描述: 此脚本用于分析Arch Linux系统中手动安装的软件包，并提供详细的统计信息和报告。
# 功能:
#   1. 获取系统初始安装日期。
#   2. 获取用户首次执行命令的时间。
#   3. 统计手动安装的软件包列表，包括安装日期、软件包名称、大小和仓库来源。
#   4. 提供排序选项，按安装日期、软件包大小或软件包名称排序。
#   5. 将统计结果保存到文件，并生成一个仅包含软件包名称的列表文件，便于一键安装。
# 使用方法:
#   1. 直接运行脚本，根据提示选择排序方式。
#   2. 统计结果将保存到 save_dir="$HOME/arch-linux-init/info-logs" 目录。
#   3. 可以使用生成的软件包名称列表文件在新系统上一键安装所有软件包。
# 说明：1. 通过 journalctl、bash 历史记录和 分析第一条pacman -S 等方式获取用户首次执行命令的时间。这个时间作为参考，用于过滤出系统初始安装日期之后安装的软件包。
#    2. 通过分析 pacman -Qi 获取包的大小
#    3. 查找每个包在日志里第一次出现的时间，然后将时间和上面的参考时间作为对比。
#    4. 这也是和1.0版本的区别。
#    5. 为什么不用pacman -Qi里的安装日期，更新软件，会修改这个安装日期
# vs 2.0版本：- 预先将系统安装日期转换为时间戳，避免重复转换
#   - 使用关联数组存储AUR包信息，减少重复查询
#   - 使用数组存储结果，避免频繁的文件IO操作
#   - 优化日期处理逻辑，减少格式转换次数
#   - 使用`grep -m 1` 限制搜索结果，提高效率
#   - 移除了临时文件的使用，减少磁盘IO
#   - 使用`while read` 替代`for` 循环，提高大数据处理效率
# 示例:
#   sudo pacman -S --needed - < $manual_list_file
# 作者: [您的名字]
# 版本: 2.0
# 日期: 2023-10-01
# ==========================
# 颜色定义
RED='\033[0;31m'; GREEN='\033[0;32m'
YELLOW='\033[0;33m'; BLUE='\033[0;34m'
CYAN='\033[0;36m'; NC='\033[0m'

# 获取用户执行的第一条命令时间
get_first_command_time() {
    echo -e "${YELLOW}正在获取用户第一次执行命令的时间...${NC}" >&2
    
    # 方法一：尝试从journalctl日志中获取最早的用户命令记录
    if command -v journalctl &> /dev/null; then
        echo -e "${BLUE}尝试从journalctl日志获取最早的用户命令记录...${NC}" >&2
        # 获取最早的用户会话记录
        earliest_session=$(journalctl _UID=1000 --output=short-iso --reverse | tail -n 1)
        if [ -n "$earliest_session" ]; then
            # 提取时间戳并转换格式，处理ISO 8601格式
            if [[ "$earliest_session" =~ ([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{2}:[0-9]{2}) ]]; then
                # 使用bash正则表达式捕获组提取日期
                session_date="${BASH_REMATCH[1]}"
                # 转换为标准格式 YYYY-MM-DD HH:MM
                session_date=$(date -d "$session_date" "+%Y-%m-%d %H:%M" 2>/dev/null)
                if [ -n "$session_date" ]; then
                    echo -e "${GREEN}成功获取用户首次活动时间: $session_date (来源: journalctl用户会话记录)${NC}" >&2
                    echo "$session_date"
                    return 0
                fi
            fi
        fi
    fi
    # 方法二：从pacmaninstall.log获取第一条pacman -S命令时间
 if [ -f "/var/log/pacman.log" ]; then
        echo -e "${BLUE}尝试从pacman.log获取第一条pacman -S命令时间...${NC}" >&2
        # 获取第一条pacman -S命令的时间
        first_install=$(grep -E "\[PACMAN\] Running 'pacman -S" /var/log/pacman.log | head -n 1)
        if [ -n "$first_install" ]; then
            # 尝试匹配ISO 8601格式 [YYYY-MM-DDThh:mm:ss+0800]
            if [[ "$first_install" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\+[0-9]{4})\] ]]; then
                # 使用bash正则表达式捕获组提取日期
                install_time="${BASH_REMATCH[1]}"
                # 转换为标准格式 YYYY-MM-DD HH:MM
                install_time=$(date -d "$install_time" "+%Y-%m-%d %H:%M" 2>/dev/null)
                if [ -n "$install_time" ]; then
                    echo -e "${GREEN}成功获取用户首次安装软件时间: $install_time (来源: pacman.log第一条安装命令)${NC}" >&2
                    echo "$install_time"
                    return 0
                fi
            fi
        fi
    fi
    # 方法三：尝试从bash历史记录获取最早命令时间
    if [ -f "$HOME/.bash_history" ]; then
        echo -e "${BLUE}尝试从bash历史记录获取最早命令时间...${NC}" >&2
        # 获取历史记录文件的创建时间
        history_date=$(stat -c %y "$HOME/.bash_history" | cut -d' ' -f1,2)
        if [ -n "$history_date" ]; then
            echo -e "${GREEN}成功获取用户首次活动时间: $history_date (来源: bash历史记录创建时间)${NC}" >&2
            echo "$history_date"
            return 0
        fi
    fi
    # 如果都无法获取，则调用get_install_date获取系统安装时间
    echo -e "${YELLOW}无法获取用户首次活动时间，使用系统安装时间作为参考...${NC}" >&2
    install_date=$(get_install_date)
    echo "$install_date"
    return 1
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
    
    # 预先将install_date转换为时间戳，避免重复转换
    local install_date_epoch=$(date -d "$install_date" +%s 2>/dev/null)
    
    # 输出调试信息到标准错误，而不是标准输出
    echo -e "${BLUE}系统初始安装日期: $install_date${NC}" >&2
    echo -e "${YELLOW}正在统计手动安装的软件包...${NC}" >&2
    
    # 获取所有明确安装的包（非依赖）和AUR包
    echo -e "${BLUE}正在获取所有明确安装的软件包（非依赖）...${NC}" >&2
    local explicit_packages=$(pacman -Qe | cut -d' ' -f1)
    local aur_packages=$(pacman -Qm | cut -d' ' -f1)
    declare -A is_aur_package
    for pkg in $aur_packages; do
        is_aur_package[$pkg]=1
    done
    
    local total_packages=$(echo "$explicit_packages" | wc -l)
    echo -e "${GREEN}找到 $total_packages 个明确安装的软件包${NC}" >&2
    
    # 使用数组存储结果，避免频繁IO操作
    declare -a results
    local counter=0
    
    # 遍历所有明确安装的包，检查安装日期
    echo -e "${BLUE}正在分析每个软件包的安装日期...${NC}" >&2
    while read -r pkg; do
        # 更新计数器并显示进度
        ((counter++))
        if [ $((counter % 10)) -eq 0 ] || [ $counter -eq 1 ] || [ $counter -eq $total_packages ]; then
            echo -e "${YELLOW}正在处理: $counter / $total_packages ($(($counter * 100 / $total_packages))%)${NC}" >&2
        fi
        
        # 从pacman日志中获取安装日期
        local install_log=$(grep -m 1 "\[ALPM\] installed $pkg" /var/log/pacman.log)
        
        if [ -n "$install_log" ]; then
            local pkg_date
            # 提取并格式化日期，处理类似 "[2025-03-23T19:52:45+0000] [ALPM]" 的格式
            if [[ "$install_log" =~ \[([0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{4})\] ]]; then
                pkg_date=$(date -d "${BASH_REMATCH[1]}" +%s 2>/dev/null)
            else
                pkg_date=$(date -d "$(echo "$install_log" | cut -d' ' -f1,2)" +%s 2>/dev/null)
            fi
            
            # 如果日期转换成功且在系统安装日期之后
            if [ -n "$pkg_date" ] && [ "$pkg_date" -gt "$install_date_epoch" ]; then
                local pkg_size=$(pacman -Qi "$pkg" | grep "安装后大小" | cut -d':' -f2 | tr -d ' ')
                local repo="Official"
                [ -n "${is_aur_package[$pkg]}" ] && repo="AUR/Local"
                
                # 将结果添加到数组
                results+=("$(date -d @"$pkg_date" "+%Y-%m-%d %H:%M:%S")|$pkg|$pkg_size|$repo")
            fi
        fi
    done <<< "$explicit_packages"
    
    # 根据排序方式对结果进行排序并输出
    echo -e "${BLUE}正在按 $sort_by 对结果进行排序...${NC}" >&2
    case "$sort_by" in
        "date")
            echo -e "${GREEN}按安装日期排序（最新的在前）${NC}" >&2
            printf "%s\n" "${results[@]}" | sort -r -t'|' -k1
            ;;
        "size")
            echo -e "${GREEN}按软件包大小排序（最大的在前）${NC}" >&2
            printf "%s\n" "${results[@]}" | sort -t'|' -k3hr
            ;;
        "name")
            echo -e "${GREEN}按软件包名称排序（字母顺序）${NC}" >&2
            printf "%s\n" "${results[@]}" | sort -t'|' -k2
            ;;
        *)
            echo -e "${GREEN}使用默认排序方式：按安装日期排序（最新的在前）${NC}" >&2
            printf "%s\n" "${results[@]}" | sort -r -t'|' -k1
            ;;
    esac
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
    #save_dir="$HOME/arch-linux-init/info-logs"
    save_dir="/var/log/arch-init/info-logs"
    if [ ! -d "$save_dir" ]; then
        echo -e "${YELLOW}创建保存目录: $save_dir${NC}"
        sudo mkdir -p "$save_dir"
    else
        echo -e "${GREEN}保存目录已存在: $save_dir${NC}"
    fi
    
    read -p "请输入选项: " choice
    
    # 获取用户首次活动时间或系统初始安装日期
    echo -e "${BLUE}正在获取用户首次活动时间或系统初始安装日期...${NC}"
    install_date=$(get_first_command_time)
    
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
    echo -e "${BLUE}1. 统计结果已保存到 /var/log/arch-init/info-logs 目录${NC}"
    echo -e "${BLUE}2. 软件包名称列表也已保存到 /var/log/arch-init/info-logs 目录${NC}"
    echo -e "${BLUE}3. 您可以使用此列表在新系统上一键安装所有软件包:${NC}"
    echo -e "${CYAN}   sudo pacman -S --needed - < $manual_list_file${NC}"
    echo -e "${CYAN}===================================${NC}"
fi
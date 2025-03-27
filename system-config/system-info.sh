#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 获取系统环境信息
get_system_info() {
    echo -e "${YELLOW}正在收集系统环境信息...${NC}" >&2
    
    # 创建临时文件
    temp_system_info=$(mktemp)
    
    # 收集系统基本信息
    echo -e "${BLUE}正在获取系统基本信息...${NC}" >&2
    echo "========== 系统基本信息 ==========" >> "$temp_system_info"
    echo "主机名: $(hostname)" >> "$temp_system_info"
    echo "内核版本: $(uname -r)" >> "$temp_system_info"
    echo "架构: $(uname -m)" >> "$temp_system_info"
    echo -e "${GREEN}系统基本信息获取成功${NC}" >&2
    
    # 收集系统版本信息
    echo -e "${BLUE}正在获取系统版本信息...${NC}" >&2
    version_detected=false
    
    if [ -f "/etc/os-release" ]; then
        echo "发行版信息:" >> "$temp_system_info"
        source /etc/os-release 2>/dev/null
        echo "  名称: $NAME" >> "$temp_system_info"
        
        # 优先使用VERSION_ID，因为它通常更简洁
        if [ -n "$VERSION_ID" ]; then
            echo "  版本: $VERSION_ID" >> "$temp_system_info"
            version_detected=true
        # 其次使用VERSION
        elif [ -n "$VERSION" ]; then
            echo "  版本: $VERSION" >> "$temp_system_info"
            version_detected=true
        fi
        
        echo "  ID: $ID" >> "$temp_system_info"
        [ -n "$BUILD_ID" ] && echo "  构建ID: $BUILD_ID" >> "$temp_system_info"
        
        # 如果版本信息仍然为空，尝试其他方法
        if ! $version_detected; then
            echo -e "${YELLOW}os-release文件中版本字段为空，尝试其他方法获取系统版本...${NC}" >&2
            
            # 检查是否为Arch Linux
            if [ "$ID" = "arch" ] || [ -f "/etc/arch-release" ]; then
                echo -e "${BLUE}检测到Arch Linux系统，尝试获取版本信息...${NC}" >&2
                
                # 对于Arch Linux，使用pacman获取系统版本
                if command -v pacman &> /dev/null; then
                    # 获取pacman版本作为系统版本参考
                    pacman_version=$(pacman -Q pacman | cut -d' ' -f2)
                    echo "  版本: Rolling Release (pacman $pacman_version)" >> "$temp_system_info"
                    echo -e "${GREEN}成功获取Arch Linux版本信息${NC}" >&2
                    version_detected=true
                fi
            fi
            
            # 尝试使用lsb_release命令获取系统版本
            if ! $version_detected && command -v lsb_release &> /dev/null; then
                echo -e "${BLUE}尝试使用lsb_release命令获取系统版本...${NC}" >&2
                lsb_version=$(lsb_release -r | cut -f2)
                if [ -n "$lsb_version" ]; then
                    echo "  版本(lsb): $lsb_version" >> "$temp_system_info"
                    echo -e "${GREEN}成功使用lsb_release获取系统版本${NC}" >&2
                    version_detected=true
                fi
            fi
            
            # 尝试从/etc/issue文件获取版本信息
            if ! $version_detected && [ -f "/etc/issue" ]; then
                echo -e "${BLUE}尝试从/etc/issue文件获取系统版本...${NC}" >&2
                issue_version=$(head -n 1 /etc/issue | sed 's/\\.*$//' | sed 's/^[^0-9]*\([0-9].*\)/\1/' | tr -d '\n')
                if [ -n "$issue_version" ]; then
                    echo "  版本(issue): $issue_version" >> "$temp_system_info"
                    echo -e "${GREEN}成功从/etc/issue获取系统版本${NC}" >&2
                    version_detected=true
                fi
            fi
            
            # 如果仍然无法获取版本信息，添加一个默认值
            if ! $version_detected; then
                echo "  版本: 未知" >> "$temp_system_info"
                echo -e "${YELLOW}无法获取具体版本信息，使用'未知'作为默认值${NC}" >&2
            fi
        fi
        
        echo -e "${GREEN}系统版本信息获取成功${NC}" >&2
    else
        echo "发行版信息: 未知" >> "$temp_system_info"
        echo -e "${RED}无法获取系统版本信息${NC}" >&2
    fi
    
    # 收集桌面环境信息
    echo -e "${BLUE}正在获取桌面环境信息...${NC}" >&2
    echo "" >> "$temp_system_info"
    echo "桌面环境:" >> "$temp_system_info"
    
    # 改进桌面环境检测方法
    desktop_detected=false
    
    # 检查XDG_CURRENT_DESKTOP环境变量
    if [ -n "$XDG_CURRENT_DESKTOP" ]; then
        echo "  当前桌面: $XDG_CURRENT_DESKTOP" >> "$temp_system_info"
        echo -e "${GREEN}桌面环境信息获取成功${NC}" >&2
        desktop_detected=true
    fi
    
    # 检查DESKTOP_SESSION环境变量
    if [ -n "$DESKTOP_SESSION" ]; then
        echo "  桌面会话: $DESKTOP_SESSION" >> "$temp_system_info"
        echo -e "${GREEN}桌面会话信息获取成功${NC}" >&2
        desktop_detected=true
    fi
    
    # 尝试通过进程检测常见桌面环境
    if ! $desktop_detected && command -v ps &> /dev/null; then
        if ps -e | grep -E 'gnome-session|kwin|xfwm4|i3|sway|openbox|fluxbox|bspwm|dwm' &> /dev/null; then
            detected_de=$(ps -e | grep -E 'gnome-session|kwin|xfwm4|i3|sway|openbox|fluxbox|bspwm|dwm' | head -n 1 | awk '{print $4}')
            echo "  检测到桌面环境进程: $detected_de" >> "$temp_system_info"
            echo -e "${GREEN}通过进程检测到桌面环境${NC}" >&2
            desktop_detected=true
        fi
    fi
    
    # 如果仍未检测到桌面环境
    if ! $desktop_detected; then
        echo "  未检测到桌面环境" >> "$temp_system_info"
        echo -e "${YELLOW}未检测到桌面环境${NC}" >&2
    fi
    
    # 收集显示管理器信息
    echo -e "${BLUE}正在获取显示管理器信息...${NC}" >&2
    if command -v systemctl &> /dev/null; then
        if systemctl is-active --quiet display-manager 2>/dev/null; then
            dm=$(systemctl status display-manager 2>/dev/null | grep 'Loaded:' | cut -d'(' -f2 | cut -d';' -f1)
            if [ -n "$dm" ]; then
                echo "  显示管理器: $dm" >> "$temp_system_info"
                echo -e "${GREEN}显示管理器信息获取成功${NC}" >&2
            fi
        else
            echo "  显示管理器: 未运行" >> "$temp_system_info"
            echo -e "${YELLOW}未检测到运行中的显示管理器${NC}" >&2
        fi
    fi
    
    # 收集窗口管理器信息
    echo -e "${BLUE}正在获取窗口管理器信息...${NC}" >&2
    if command -v wmctrl &> /dev/null; then
        wm=$(wmctrl -m 2>/dev/null | grep "Name:" | cut -d: -f2 | tr -d ' ')
        if [ -n "$wm" ]; then
            echo "  窗口管理器: $wm" >> "$temp_system_info"
            echo -e "${GREEN}窗口管理器信息获取成功${NC}" >&2
        else
            echo "  窗口管理器: 未检测到" >> "$temp_system_info"
            echo -e "${YELLOW}未检测到窗口管理器${NC}" >&2
        fi
    else
        echo "  窗口管理器: wmctrl命令不可用" >> "$temp_system_info"
        echo -e "${YELLOW}wmctrl命令不可用，无法获取窗口管理器信息${NC}" >&2
    fi
    
    # 收集硬件信息
    echo -e "${BLUE}正在获取硬件信息...${NC}" >&2
    echo "" >> "$temp_system_info"
    echo "========== 硬件信息 ==========" >> "$temp_system_info"
    
    # 收集CPU信息
    echo -e "${BLUE}正在获取CPU信息...${NC}" >&2
    if [ -f "/proc/cpuinfo" ]; then
        cpu_model=$(grep -m 1 "model name" /proc/cpuinfo | cut -d':' -f2 | sed 's/^[ \t]*//')
        cpu_cores=$(grep -c "processor" /proc/cpuinfo)
        echo "CPU: $cpu_model ($cpu_cores 核)" >> "$temp_system_info"
        echo -e "${GREEN}CPU信息获取成功${NC}" >&2
    else
        echo "CPU: 未知" >> "$temp_system_info"
        echo -e "${RED}无法获取CPU信息${NC}" >&2
    fi
    
    # 收集内存信息
    echo -e "${BLUE}正在获取内存信息...${NC}" >&2
    if [ -f "/proc/meminfo" ]; then
        total_mem=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
        # 转换为GB并保留两位小数，使用awk替代bc，因为bc可能不存在
        total_mem_gb=$(awk -v mem="$total_mem" 'BEGIN {printf "%.2f", mem/1024/1024}')
        echo "内存: ${total_mem_gb}GB" >> "$temp_system_info"
        echo -e "${GREEN}内存信息获取成功${NC}" >&2
    else
        echo "内存: 未知" >> "$temp_system_info"
        echo -e "${RED}无法获取内存信息${NC}" >&2
    fi
    
    # 收集显卡信息
    echo -e "${BLUE}正在获取显卡信息...${NC}" >&2
    if command -v lspci &> /dev/null; then
        gpu_info=$(lspci | grep -E 'VGA|3D|Display' | sed 's/^.*: //')
        if [ -n "$gpu_info" ]; then
            echo "显卡:" >> "$temp_system_info"
            lspci | grep -E 'VGA|3D|Display' | sed 's/^/  /' >> "$temp_system_info"
            echo -e "${GREEN}显卡信息获取成功${NC}" >&2
            
            # 检测图形处理器(如llvmpipe)
            echo -e "${BLUE}正在检测图形处理器...${NC}" >&2
            if command -v glxinfo &> /dev/null; then
                renderer=$(glxinfo | grep "OpenGL renderer string" | cut -d':' -f2 | sed 's/^[ \t]*//')
                if [ -n "$renderer" ]; then
                    echo "图形处理器: $renderer" >> "$temp_system_info"
                    echo -e "${GREEN}图形处理器信息获取成功${NC}" >&2
                fi
            fi
        else
            echo "显卡: 未检测到" >> "$temp_system_info"
            echo -e "${YELLOW}未检测到显卡信息${NC}" >&2
        fi
    else
        echo "显卡: 未知（lspci命令不可用）" >> "$temp_system_info"
        echo -e "${RED}无法获取显卡信息（lspci命令不可用）${NC}" >&2
    fi
    
    # 检测图形平台(Wayland/X11)
    echo -e "${BLUE}正在检测图形平台...${NC}" >&2
    if [ -n "$XDG_SESSION_TYPE" ]; then
        echo "图形平台: $XDG_SESSION_TYPE" >> "$temp_system_info"
        echo -e "${GREEN}图形平台信息获取成功${NC}" >&2
    elif [ -n "$WAYLAND_DISPLAY" ]; then
        echo "图形平台: Wayland" >> "$temp_system_info"
        echo -e "${GREEN}检测到Wayland图形平台${NC}" >&2
    elif [ -n "$DISPLAY" ]; then
        echo "图形平台: X11" >> "$temp_system_info"
        echo -e "${GREEN}检测到X11图形平台${NC}" >&2
    else
        echo "图形平台: 未知" >> "$temp_system_info"
        echo -e "${YELLOW}无法检测图形平台${NC}" >&2
    fi
    
    # 检测制造商和产品名称
    echo -e "${BLUE}正在检测制造商和产品信息...${NC}" >&2
    if command -v dmidecode &> /dev/null; then
        # 需要root权限运行dmidecode
        if [ "$(id -u)" -eq 0 ]; then
            manufacturer=$(dmidecode -s system-manufacturer 2>/dev/null)
            product_name=$(dmidecode -s system-product-name 2>/dev/null)
            
            if [ -n "$manufacturer" ]; then
                echo "制造商: $manufacturer" >> "$temp_system_info"
                echo -e "${GREEN}制造商信息获取成功${NC}" >&2
            fi
            
            if [ -n "$product_name" ]; then
                echo "产品名称: $product_name" >> "$temp_system_info"
                echo -e "${GREEN}产品名称信息获取成功${NC}" >&2
            fi
        else
            echo -e "${YELLOW}需要root权限才能获取制造商和产品信息${NC}" >&2
            # 尝试从其他来源获取信息
            if [ -f "/sys/devices/virtual/dmi/id/sys_vendor" ]; then
                manufacturer=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null)
                if [ -n "$manufacturer" ]; then
                    echo "制造商: $manufacturer" >> "$temp_system_info"
                    echo -e "${GREEN}制造商信息获取成功${NC}" >&2
                fi
            fi
            
            if [ -f "/sys/devices/virtual/dmi/id/product_name" ]; then
                product_name=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)
                if [ -n "$product_name" ]; then
                    echo "产品名称: $product_name" >> "$temp_system_info"
                    echo -e "${GREEN}产品名称信息获取成功${NC}" >&2
                fi
            fi
        fi
    elif [ -f "/sys/devices/virtual/dmi/id/sys_vendor" ] && [ -f "/sys/devices/virtual/dmi/id/product_name" ]; then
        manufacturer=$(cat /sys/devices/virtual/dmi/id/sys_vendor 2>/dev/null)
        product_name=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null)
        
        if [ -n "$manufacturer" ]; then
            echo "制造商: $manufacturer" >> "$temp_system_info"
            echo -e "${GREEN}制造商信息获取成功${NC}" >&2
        fi
        
        if [ -n "$product_name" ]; then
            echo "产品名称: $product_name" >> "$temp_system_info"
            echo -e "${GREEN}产品名称信息获取成功${NC}" >&2
        fi
    else
        echo -e "${YELLOW}无法获取制造商和产品信息${NC}" >&2
    fi
    
    # 收集磁盘使用情况
    echo -e "${BLUE}正在获取磁盘使用情况...${NC}" >&2
    if command -v df &> /dev/null; then
        echo "" >> "$temp_system_info"
        echo "磁盘信息:" >> "$temp_system_info"
        df -h | grep -E "^/dev/|^tmpfs" | sort >> "$temp_system_info"
        echo -e "${GREEN}磁盘使用情况获取成功${NC}" >&2
    else
        echo "磁盘信息: 未知" >> "$temp_system_info"
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
    
    # 收集关键软件版本信息
    echo -e "${BLUE}正在获取关键软件版本信息...${NC}" >&2
    echo "" >> "$temp_system_info"
    echo "========== 关键软件版本 ==========" >> "$temp_system_info"
    
    # 检查常见的关键软件包
    if command -v pacman &> /dev/null; then
        key_packages=("systemd" "bash" "glibc" "gcc" "mesa" "xorg-server" "wayland" "plasma-desktop" "gnome-shell" "xfce4-session" "i3" "sway")
        
        for pkg in "${key_packages[@]}"; do
            if pacman -Q "$pkg" &> /dev/null; then
                pkg_version=$(pacman -Q "$pkg" | awk '{print $2}')
                echo "$pkg: $pkg_version" >> "$temp_system_info"
            fi
        done
        echo -e "${GREEN}关键软件版本信息获取成功${NC}" >&2
        
        # 检测KDE框架版本
        echo -e "${BLUE}正在检测KDE框架版本...${NC}" >&2
        if pacman -Q kf6-config &> /dev/null; then
            kde_framework_version=$(pacman -Q kf6-config | awk '{print $2}' | cut -d'-' -f1)
            echo "KDE框架版本: $kde_framework_version" >> "$temp_system_info"
            echo -e "${GREEN}KDE框架版本检测成功${NC}" >&2
        elif pacman -Q kf5-config &> /dev/null; then
            kde_framework_version=$(pacman -Q kf5-config | awk '{print $2}' | cut -d'-' -f1)
            echo "KDE框架版本: $kde_framework_version" >> "$temp_system_info"
            echo -e "${GREEN}KDE框架版本检测成功${NC}" >&2
        elif command -v kf6-config &> /dev/null; then
            kde_framework_version=$(kf6-config --version | grep KDE | awk '{print $3}')
            echo "KDE框架版本: $kde_framework_version" >> "$temp_system_info"
            echo -e "${GREEN}KDE框架版本检测成功${NC}" >&2
        elif command -v kf5-config &> /dev/null; then
            kde_framework_version=$(kf5-config --version | grep KDE | awk '{print $3}')
            echo "KDE框架版本: $kde_framework_version" >> "$temp_system_info"
            echo -e "${GREEN}KDE框架版本检测成功${NC}" >&2
        fi
        
        # 检测Qt版本
        echo -e "${BLUE}正在检测Qt版本...${NC}" >&2
        if pacman -Q qt6-base &> /dev/null; then
            qt_version=$(pacman -Q qt6-base | awk '{print $2}' | cut -d'-' -f1)
            echo "Qt版本: $qt_version" >> "$temp_system_info"
            echo -e "${GREEN}Qt版本检测成功${NC}" >&2
        elif pacman -Q qt5-base &> /dev/null; then
            qt_version=$(pacman -Q qt5-base | awk '{print $2}' | cut -d'-' -f1)
            echo "Qt版本: $qt_version" >> "$temp_system_info"
            echo -e "${GREEN}Qt版本检测成功${NC}" >&2
        elif command -v qmake6 &> /dev/null; then
            qt_version=$(qmake6 -query QT_VERSION)
            echo "Qt版本: $qt_version" >> "$temp_system_info"
            echo -e "${GREEN}Qt版本检测成功${NC}" >&2
        elif command -v qmake &> /dev/null; then
            qt_version=$(qmake -query QT_VERSION)
            echo "Qt版本: $qt_version" >> "$temp_system_info"
            echo -e "${GREEN}Qt版本检测成功${NC}" >&2
        fi
    else
        echo "无法获取软件包信息（pacman命令不可用）" >> "$temp_system_info"
        echo -e "${RED}无法获取软件包信息（pacman命令不可用）${NC}" >&2
    fi
    
    # 收集系统服务信息
    echo -e "${BLUE}正在获取系统服务信息...${NC}" >&2
    if command -v systemctl &> /dev/null; then
        echo "" >> "$temp_system_info"
        echo "========== 系统服务状态 ==========" >> "$temp_system_info"
        echo "已启用的服务:" >> "$temp_system_info"
        systemctl list-unit-files --state=enabled --no-pager 2>/dev/null | grep -v "^UNIT" | grep -v "^$" | head -n 20 >> "$temp_system_info"
        echo "..." >> "$temp_system_info"
        echo -e "${GREEN}系统服务信息获取成功${NC}" >&2
    fi
    
    # 输出收集到的系统信息
    cat "$temp_system_info"
    
    # 删除临时文件
    rm -f "$temp_system_info"
    
    echo -e "${GREEN}系统环境信息收集完成!${NC}" >&2
}

# 如果直接执行此脚本，则运行 get_system_info 函数并将结果保存到文件
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    system_info=$(get_system_info)
    
    # 定义保存目录
    save_dir="$HOME/system-info"
    
    # 创建保存目录，如果不存在
    if [ ! -d "$save_dir" ]; then
        mkdir -p "$save_dir"
    fi
    
    # 生成保存文件名（使用日期时间作为文件名的一部分）
    timestamp=$(date +"%Y%m%d_%H%M%S")
    save_file="$save_dir/system_info_$timestamp.txt"
    
    # 将系统信息保存到文件
    echo -e "${BLUE}正在将系统信息保存到文件: ${CYAN}$save_file${NC}...${NC}" >&2
    echo "$system_info" > "$save_file"
    echo -e "${GREEN}系统信息已成功保存到: ${CYAN}$save_file${NC}${NC}" >&2
fi
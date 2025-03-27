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
    echo "========== 桌面环境信息 ==========" >> "$temp_system_info"
    
    # 检测图形平台
    echo -e "${BLUE}正在获取图形平台信息...${NC}" >&2
    if [ -n "$XDG_SESSION_TYPE" ]; then
        echo "图形平台: $XDG_SESSION_TYPE" >> "$temp_system_info"
        echo -e "${GREEN}图形平台信息获取成功${NC}" >&2
    else
        echo "图形平台: 未知" >> "$temp_system_info"
        echo -e "${YELLOW}无法获取图形平台信息${NC}" >&2
    fi

    # 检测图形处理器
    echo -e "${BLUE}正在获取图形处理器信息...${NC}" >&2
    if [ -n "$LIBGL_ALWAYS_SOFTWARE" ] || [ -n "$GALLIUM_DRIVER" ]; then
        echo "图形处理器: llvmpipe (软件渲染)" >> "$temp_system_info"
        echo -e "${GREEN}图形处理器信息获取成功${NC}" >&2
    fi

    # 检测KDE框架版本
    echo -e "${BLUE}正在获取KDE框架版本...${NC}" >&2
    kde_version=""
    
    # 优先使用kf6-config命令
    if command -v kf6-config &> /dev/null; then
        kde_version=$(kf6-config --version | grep "KDE Frameworks" | cut -d':' -f2 | tr -d ' ')
    # 其次使用kf5-config命令
    elif command -v kf5-config &> /dev/null; then
        kde_version=$(kf5-config --version | grep "KDE Frameworks" | cut -d':' -f2 | tr -d ' ')
    fi
    
    # 如果命令行工具无法获取版本，尝试通过软件包版本获取
    if [ -z "$kde_version" ] && command -v pacman &> /dev/null; then
        # 检查KF6
        if pacman -Q kf6-frameworks-meta &> /dev/null; then
            kde_version=$(pacman -Q kf6-frameworks-meta | cut -d' ' -f2)
        # 检查KF5
        elif pacman -Q kf5-frameworks-meta &> /dev/null; then
            kde_version=$(pacman -Q kf5-frameworks-meta | cut -d' ' -f2)
        # 检查plasma-framework作为备选
        elif pacman -Q plasma-framework &> /dev/null; then
            kde_version=$(pacman -Q plasma-framework | cut -d' ' -f2)
        fi
    fi
    
    if [ -n "$kde_version" ]; then
        echo "KDE框架版本: $kde_version" >> "$temp_system_info"
        echo -e "${GREEN}KDE框架版本获取成功${NC}" >&2
    else
        echo "KDE框架版本: 未检测到" >> "$temp_system_info"
        echo -e "${YELLOW}无法获取KDE框架版本${NC}" >&2
    fi

    # 检测Qt版本
    echo -e "${BLUE}正在获取Qt版本...${NC}" >&2
    if command -v qmake &> /dev/null; then
        qt_version=$(qmake --version | grep "Qt version" | awk '{print $4}')
        if [ -n "$qt_version" ]; then
            echo "Qt版本: $qt_version" >> "$temp_system_info"
            echo -e "${GREEN}Qt版本获取成功${NC}" >&2
        fi
    fi

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

    # 获取CPU信息
    if [ -f "/proc/cpuinfo" ]; then
        cpu_model=$(grep "model name" /proc/cpuinfo | head -n 1 | cut -d':' -f2 | sed 's/^[ \t]*//')
        cpu_cores=$(grep -c "^processor" /proc/cpuinfo)
        if [ -n "$cpu_model" ]; then
            echo "CPU型号: $cpu_model" >> "$temp_system_info"
            echo "CPU核心数: $cpu_cores" >> "$temp_system_info"
            echo -e "${GREEN}CPU信息获取成功${NC}" >&2
        else
            echo "CPU信息: 未知" >> "$temp_system_info"
            echo -e "${YELLOW}无法获取CPU信息${NC}" >&2
        fi
    else
        echo "CPU信息: /proc/cpuinfo不可用" >> "$temp_system_info"
        echo -e "${YELLOW}/proc/cpuinfo不可用${NC}" >&2
    fi
    
    # 获取内存信息
    if [ -f "/proc/meminfo" ]; then
        total_mem=$(grep "MemTotal" /proc/meminfo | awk '{print $2}')
        if [ -n "$total_mem" ]; then
            # 转换为GB并保留一位小数
            total_mem_gb=$(echo "scale=1; $total_mem/1024/1024" | bc)
            echo "内存大小: ${total_mem_gb}GB" >> "$temp_system_info"
            echo -e "${GREEN}内存信息获取成功${NC}" >&2
        else
            echo "内存大小: 未知" >> "$temp_system_info"
            echo -e "${YELLOW}无法获取内存信息${NC}" >&2
        fi
    else
        echo "内存信息: /proc/meminfo不可用" >> "$temp_system_info"
        echo -e "${YELLOW}/proc/meminfo不可用${NC}" >&2
    fi
    
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
            echo "显卡: $gpu_info" >> "$temp_system_info"
            echo -e "${GREEN}显卡信息获取成功${NC}" >&2
        else
            echo "显卡: 未检测到" >> "$temp_system_info"
            echo -e "${YELLOW}未检测到显卡信息${NC}" >&2
        fi
    else
        echo "显卡: lspci命令不可用" >> "$temp_system_info"
        echo -e "${YELLOW}lspci命令不可用，无法获取显卡信息${NC}" >&2
    fi
    
    # 收集磁盘信息
    echo -e "${BLUE}正在获取磁盘信息...${NC}" >&2
    if command -v df &> /dev/null; then
        # 获取根分区信息
        root_info=$(df -h / | tail -n 1)
        root_size=$(echo "$root_info" | awk '{print $2}')
        root_used=$(echo "$root_info" | awk '{print $3}')
        root_avail=$(echo "$root_info" | awk '{print $4}')
        root_use=$(echo "$root_info" | awk '{print $5}')
        
        echo "根分区:" >> "$temp_system_info"
        echo "  总大小: $root_size" >> "$temp_system_info"
        echo "  已使用: $root_used ($root_use)" >> "$temp_system_info"
        echo "  可用: $root_avail" >> "$temp_system_info"
        
        # 获取home分区信息（如果存在）
        if [ -d "/home" ]; then
            home_info=$(df -h /home | tail -n 1)
            home_size=$(echo "$home_info" | awk '{print $2}')
            home_used=$(echo "$home_info" | awk '{print $3}')
            home_avail=$(echo "$home_info" | awk '{print $4}')
            home_use=$(echo "$home_info" | awk '{print $5}')
            
            echo "home分区:" >> "$temp_system_info"
            echo "  总大小: $home_size" >> "$temp_system_info"
            echo "  已使用: $home_used ($home_use)" >> "$temp_system_info"
            echo "  可用: $home_avail" >> "$temp_system_info"
        fi
        
        echo -e "${GREEN}磁盘信息获取成功${NC}" >&2
    else
        echo "磁盘信息: df命令不可用" >> "$temp_system_info"
        echo -e "${YELLOW}df命令不可用，无法获取磁盘信息${NC}" >&2
    fi
    
    # 收集系统运行时间
    echo -e "${BLUE}正在获取系统运行时间...${NC}" >&2
    if command -v uptime &> /dev/null; then
        uptime_info=$(uptime -p | sed 's/^up //')
        echo "系统运行时间: $uptime_info" >> "$temp_system_info"
        echo -e "${GREEN}系统运行时间获取成功${NC}" >&2
    else
        echo "系统运行时间: 未知" >> "$temp_system_info"
        echo -e "${YELLOW}uptime命令不可用，无法获取系统运行时间${NC}" >&2
    fi

    # 收集系统语言环境
    echo -e "${BLUE}正在获取系统语言环境...${NC}" >&2
    if command -v locale &> /dev/null; then
        lang=$(locale | grep LANG= | cut -d'=' -f2)
        echo "系统语言环境: $lang" >> "$temp_system_info"
        echo -e "${GREEN}系统语言环境获取成功${NC}" >&2
    else
        echo "系统语言环境: 未知" >> "$temp_system_info"
        echo -e "${YELLOW}locale命令不可用，无法获取系统语言环境${NC}" >&2
    fi

    # 收集关键软件版本
    echo -e "${BLUE}正在获取关键软件版本...${NC}" >&2
    echo "" >> "$temp_system_info"
    echo "========== 关键软件版本 ==========" >> "$temp_system_info"
    
    # 检查系统基础组件版本
    echo -e "${BLUE}正在获取系统基础组件版本...${NC}" >&2
    if command -v pacman &> /dev/null; then
        # 使用pacman -Q查询包版本
        packages=("systemd" "bash" "glibc" "gcc" "mesa" "xorg-server" "wayland" "plasma-desktop")
        for pkg in "${packages[@]}"; do
            if pacman -Q "$pkg" &> /dev/null; then
                version=$(pacman -Q "$pkg" | cut -d' ' -f2)
                echo "$pkg: $version" >> "$temp_system_info"
            else
                echo "$pkg: 未安装" >> "$temp_system_info"
            fi
        done
        echo -e "${GREEN}系统基础组件版本获取成功${NC}" >&2
    else
        echo -e "${YELLOW}pacman命令不可用，无法获取系统基础组件版本${NC}" >&2
    fi

    # 检查KDE框架版本
    echo -e "${BLUE}正在获取KDE框架版本...${NC}" >&2
    kde_version=""
    kde_detected=false

    # 首先通过包管理器检查KDE框架版本
    if command -v pacman &> /dev/null; then
        # 检查frameworkintegration包
        if pacman -Q frameworkintegration &> /dev/null; then
            kde_version=$(pacman -Q frameworkintegration | cut -d' ' -f2)
            kde_detected=true
        # 检查KDE框架元包
        elif pacman -Q kf6-frameworks-meta &> /dev/null; then
            kde_version=$(pacman -Q kf6-frameworks-meta | cut -d' ' -f2)
            kde_detected=true
        elif pacman -Q kf5-frameworks-meta &> /dev/null; then
            kde_version=$(pacman -Q kf5-frameworks-meta | cut -d' ' -f2)
            kde_detected=true
        # 检查plasma-framework包
        elif pacman -Q plasma-framework &> /dev/null; then
            kde_version=$(pacman -Q plasma-framework | cut -d' ' -f2)
            kde_detected=true
        fi
    fi

    # 如果包管理器检测失败，尝试使用命令行工具检测
    if ! $kde_detected; then
        if command -v kf6-config &> /dev/null; then
            kde_version=$(kf6-config --version | grep "KDE Frameworks" | cut -d':' -f2 | tr -d ' ')
            kde_detected=true
        elif command -v kf5-config &> /dev/null; then
            kde_version=$(kf5-config --version | grep "KDE Frameworks" | cut -d':' -f2 | tr -d ' ')
            kde_detected=true
        # 尝试通过qdbus获取KDE版本信息
        elif command -v qdbus &> /dev/null && qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.version &> /dev/null; then
            kde_version=$(qdbus org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.version)
            kde_detected=true
        fi
    fi

    if $kde_detected; then
        echo "KDE框架版本: $kde_version" >> "$temp_system_info"
        echo -e "${GREEN}KDE框架版本获取成功${NC}" >&2
    else
        echo "KDE框架版本: 未安装" >> "$temp_system_info"
        echo -e "${YELLOW}未检测到KDE框架${NC}" >&2
    fi

    # 检查Qt版本
    echo -e "${BLUE}正在获取Qt版本...${NC}" >&2
    qt_version=""
    if command -v qmake6 &> /dev/null; then
        qt_version=$(qmake6 --version | grep "Qt version" | awk '{print $4}')
    elif command -v qmake &> /dev/null; then
        qt_version=$(qmake --version | grep "Qt version" | awk '{print $4}')
    fi

    if [ -n "$qt_version" ]; then
        echo "Qt版本: $qt_version" >> "$temp_system_info"
        echo -e "${GREEN}Qt版本获取成功${NC}" >&2
    else
        echo "Qt版本: 未安装" >> "$temp_system_info"
        echo -e "${YELLOW}未检测到Qt${NC}" >&2
    fi

    # 检查常用开发工具版本
    echo -e "${BLUE}正在获取开发工具版本...${NC}" >&2
    dev_tools=("python3" "java" "node" "go" "rust" "docker")
    for tool in "${dev_tools[@]}"; do
        if command -v "$tool" &> /dev/null; then
            version=$($tool --version 2>/dev/null | head -n 1)
            echo "$tool: $version" >> "$temp_system_info"
        fi
    done
    echo -e "${GREEN}关键软件版本获取成功${NC}" >&2

    # 收集分区信息
    echo -e "${BLUE}正在获取分区信息...${NC}" >&2
    echo "" >> "$temp_system_info"
    echo "========== 分区信息 ==========" >> "$temp_system_info"
    
    if command -v lsblk &> /dev/null; then
        echo "分区挂载关系:" >> "$temp_system_info"
        lsblk -f | grep -v "^loop" >> "$temp_system_info"
        echo -e "${GREEN}分区信息获取成功${NC}" >&2
    else
        echo "分区信息: lsblk命令不可用" >> "$temp_system_info"
        echo -e "${YELLOW}lsblk命令不可用，无法获取分区信息${NC}" >&2
    fi

    # 收集网络信息
    echo -e "${BLUE}正在获取网络信息...${NC}" >&2
    echo "" >> "$temp_system_info"
    echo "========== 网络信息 ==========" >> "$temp_system_info"
    
    # 获取默认网络接口
    if command -v ip &> /dev/null; then
        default_interface=$(ip route | grep '^default' | awk '{print $5}' | head -n 1)
        if [ -n "$default_interface" ]; then
            echo "默认网络接口: $default_interface" >> "$temp_system_info"
            
            # 获取IP地址
            ip_addr=$(ip addr show "$default_interface" | grep 'inet ' | awk '{print $2}' | cut -d'/' -f1)
            if [ -n "$ip_addr" ]; then
                echo "IP地址: $ip_addr" >> "$temp_system_info"
            else
                echo "IP地址: 未分配" >> "$temp_system_info"
            fi
            
            # 获取MAC地址
            mac_addr=$(ip link show "$default_interface" | grep 'link/ether' | awk '{print $2}')
            if [ -n "$mac_addr" ]; then
                echo "MAC地址: $mac_addr" >> "$temp_system_info"
            fi

            # 获取网关信息
            gateway=$(ip route | grep '^default' | awk '{print $3}' | head -n 1)
            if [ -n "$gateway" ]; then
                echo "默认网关: $gateway" >> "$temp_system_info"
            fi

            # 获取DNS信息
            if [ -f "/etc/resolv.conf" ]; then
                dns_servers=$(grep '^nameserver' /etc/resolv.conf | awk '{print $2}' | tr '\n' ' ')
                if [ -n "$dns_servers" ]; then
                    echo "DNS服务器: $dns_servers" >> "$temp_system_info"
                fi
            fi
            
            echo -e "${GREEN}网络信息获取成功${NC}" >&2
        else
            echo "网络接口: 未检测到默认接口" >> "$temp_system_info"
            echo -e "${YELLOW}未检测到默认网络接口${NC}" >&2
        fi
    else
        echo "网络信息: ip命令不可用" >> "$temp_system_info"
        echo -e "${YELLOW}ip命令不可用，无法获取网络信息${NC}" >&2
    fi
    
    # 读取临时文件内容
    system_info=$(cat "$temp_system_info")
    
    # 删除临时文件
    rm -f "$temp_system_info"
    
    # 返回收集到的系统信息
    echo "$system_info"
}

# 显示系统环境信息
show_system_info() {
    echo -e "${CYAN}========== 系统环境信息 ===========${NC}"
    echo -e "${BLUE}正在收集系统环境信息...${NC}"
    
    # 获取系统环境信息
    system_info=$(get_system_info)
    
    # 显示系统环境信息
    echo "$system_info" | while IFS= read -r line; do
        echo -e "${GREEN}$line${NC}"
    done
    
    # 生成保存文件名（使用日期时间作为文件名的一部分）
    echo -e "${BLUE}正在准备保存系统信息...${NC}"
    save_dir="$HOME/system-info"
    if [ ! -d "$save_dir" ]; then
        echo -e "${YELLOW}创建保存目录: $save_dir${NC}"
        mkdir -p "$save_dir"
    else
        echo -e "${GREEN}保存目录已存在: $save_dir${NC}"
    fi
    
    timestamp=$(date +"%Y%m%d_%H%M%S")
    save_file="$save_dir/system_info_$timestamp.txt"
    echo -e "${GREEN}将保存结果到文件: $save_file${NC}"
    
    # 将结果保存到文件
    echo -e "${BLUE}正在将系统信息保存到文件...${NC}"
    echo "$system_info" > "$save_file"
    echo -e "${GREEN}系统信息已保存到: $save_file${NC}"
}

# 如果直接运行此脚本，则显示系统信息
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
    show_system_info
fi
#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 获取软件包的软件名称（这里只是简单地使用包名作为软件名，后续可以完善）
get_software_name() {
    echo "$1"
}

# 获取软件包的服务名称
get_service_name() {
    package_name="$1"
    
    # 尝试使用 systemctl list-units 查找服务名
    service_name=$(systemctl list-units --type=service --all | grep "$package_name" | awk '{print $1}' | head -n 1)
    
    if [ -n "$service_name" ]; then
        echo "$service_name"
    else
        # 如果找不到，则使用默认的服务名（包名.service）
        echo "$package_name.service"
    fi
}

# 检查服务是否运行
is_service_active() {
    if systemctl is-active --quiet "$1"; then
        echo "true"
    else
        echo "false"
    fi
}

# 检查服务是否开机启动
is_service_enabled() {
    if systemctl is-enabled --quiet "$1"; then
        echo "true"
    else
        echo "false"
    fi
}

# 检查软件包的服务状态
check_service_status() {
    package_name="$1"
    software_name=$(get_software_name "$package_name")
    service_name=$(get_service_name "$package_name")

    if ! systemctl status "$service_name" >/dev/null 2>&1; then
        echo -e "${YELLOW}未找到服务: ${service_name}${NC}" >&2
        echo -e "${YELLOW}软件名字: ${software_name} | 包名: ${package_name} | 服务名: ${service_name} | 开启启动: N/A | 运行状态: N/A${NC}"
        return
    fi

    service_active=$(is_service_active "$service_name")
    service_enabled=$(is_service_enabled "$service_name")

    if [ "$service_active" = "true" ]; then
        active_status="${GREEN}是${NC}"
    else
        active_status="${RED}否${NC}"
    fi

    if [ "$service_enabled" = "true" ]; then
        enabled_status="${GREEN}是${NC}"
    else
        enabled_status="${RED}否${NC}"
    fi

    service_description=$(get_service_description "$service_name")
    echo -e "软件名字: ${software_name} | 包名: ${package_name} | 服务名: ${service_name} | 描述: ${service_description} | 开启启动: ${enabled_status} | 运行状态: ${active_status}"
}

# 获取服务描述
get_service_description() {
    service_name="$1"
    description=$(systemctl show "$service_name" --no-pager | grep Description= | cut -d '=' -f2)
    if [ -z "$description" ]; then
        description="N/A"
    fi
    echo "$description"
}

# 主程序
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo -e "${CYAN}========== 软件包服务状态检查工具 ===========${NC}"
    echo -e "${CYAN}=====================================================================================${NC}"
    echo -e "${YELLOW}软件名字             | 包名                  | 服务名                | 描述                        | 开启启动 | 运行状态 ${NC}"
    echo -e "${CYAN}------------------------------------------------------------------------------------=${NC}"

    # 使用 pacman -Qe 获取手动安装的软件包列表
    package_list=$(pacman -Qe | cut -d' ' -f1)

    # 逐个检查手动安装的软件包
    for package in $package_list; do
        check_service_status "$package"
    done

    echo -e "${CYAN}=====================================================================================${NC}"
fi

check_service_status() {
    package_name="$1"
    software_name=$(get_software_name "$package_name")
    service_name=$(get_service_name "$package_name")
    service_description=$(get_service_description "$service_name")
    
    if ! systemctl status "$service_name" >/dev/null 2>&1; then
        echo -e "${YELLOW}未找到服务: ${service_name}${NC}" >&2
        printf "%-25s | %-25s | %-25s | %-30s | %-8s | %-8s\n" "$software_name" "$package_name" "$service_name" "N/A" "N/A" "N/A"
        return
    fi

    service_active=$(is_service_active "$service_name")
    service_enabled=$(is_service_enabled "$service_name")

    if [ "$service_active" = "true" ]; then
        active_status="${GREEN}是${NC}"
    else
        active_status="${RED}否${NC}"
    fi

    if [ "$service_enabled" = "true" ]; then
        enabled_status="${GREEN}是${NC}"
    else
        enabled_status="${RED}否${NC}"
    fi

    printf "%-25s | %-25s | %-25s | %-30s | %-8s | %-8s\n" "$software_name" "$package_name" "$service_name" "$service_description" "$enabled_status" "$active_status"
}
=======
    echo -e "${CYAN}========== 软件包服务状态检查工具 ===========${NC}"
    printf "%-25s | %-25s | %-25s | %-30s | %-8s | %-8s\n" "软件名字" "包名" "服务名" "描述" "开启启动" "运行状态"
    echo -e "${CYAN}------------------------------------------------------------------------------------=${NC}"

    # 使用 pacman -Qe 获取手动安装的软件包列表
    package_list=$(pacman -Qe | cut -d' ' -f1)

    # 逐个检查手动安装的软件包
    for package in $package_list; do
        check_service_status "$package"
    done

    echo -e "${CYAN}=====================================================================================${NC}"
fi

check_service_status() {
    package_name="$1"
    software_name=$(get_software_name "$package_name")
    service_name=$(get_service_name "$package_name")
    service_description=$(get_service_description "$service_name")
    
    if ! systemctl status "$service_name" >/dev/null 2>&1; then
        echo -e "${YELLOW}未找到服务: ${service_name}${NC}" >&2
        printf "%-25s | %-25s | %-25s | %-30s | %-8s | %-8s\n" "$software_name" "$package_name" "$service_name" "N/A" "N/A" "N/A"
        return
    fi

    service_active=$(is_service_active "$service_name")
    service_enabled=$(is_service_enabled "$service_name")

    if [ "$service_active" = "true" ]; then
        active_status="${GREEN}是${NC}"
    else
        active_status="${RED}否${NC}"
    fi

    if [ "$service_enabled" = "true" ]; then
        enabled_status="${GREEN}是${NC}"
    else
        enabled_status="${RED}否${NC}"
    fi

    printf "%-25s | %-25s | %-25s | %-30s | %-8s | %-8s\n" "$software_name" "$package_name" "$service_name" "$service_description" "$enabled_status" "$active_status"
}
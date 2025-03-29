#!/bin/bash

#
# Arch Linux 备份脚本 (按配置建议组织目录结构，区分文件和目录)
#

# --- 配置 ---
# 备份目标根目录 (请根据实际情况修改)
backup_destination_root="/mnt/backup"

# 需要备份的系统配置文件和目录 (根据 archlinux_backup_config.md)
backup_sources_system=(
    "/etc/pacman.conf"
    "/etc/mkinitcpio.conf"
    "/etc/fstab"
    "/etc/locale.conf"
    "/etc/hostname"
    "/etc/hosts"
    "/etc/vconsole.conf"
    "/etc/default/grub"          # 或 /etc/systemd-boot/
    "/etc/systemd"
    "/etc/NetworkManager"
    "/etc/X11"
    "/etc/security"
    "/etc/sudoers"
    "/etc/ssh"
    "/etc/systemd/timesyncd.conf"
    # --- 可选的服务特定配置目录 ---
    # "/etc/nginx"
    # "/etc/apache2"
    # "/etc/php"
    # "/etc/mysql"
    # "/etc/postgresql"
    # --- 请根据您的实际安装和配置的服务，取消注释并添加相应的目录 ---
)

# 需要备份的用户配置和数据目录
backup_sources_user=(
    "$HOME"
)

backup_package_lists=true
backup_pacman_log=true
backup_system_log=false # 默认不备份系统日志
backup_database=false     # 默认不备份数据库

# --- 函数 ---

# 检查是否以 root 权限运行
check_root_privileges() {
    if [[ $EUID -ne 0 ]]; then
        echo "警告: 备份系统配置需要 root 权限，请使用 sudo 运行脚本。"
        return 1
    fi
    return 0
}

# 检查备份目标目录是否存在
check_destination_directory() {
    if [ ! -d "$backup_destination_root" ]; then
        echo "错误: 备份目标目录 '$backup_destination_root' 不存在，请检查挂载或配置。"
        return 1
    fi
    return 0
}

# 备份文件 (使用 cp)
backup_file() {
    local source="$1"
    local destination="$2"
    local description="$3"

    echo "  - 备份文件: $description"
    if cp "$source" "$destination" ; then
        echo "    - 成功: $description"
    else
        echo "    - 失败: $description"
        return 1
    fi
    return 0
}

# 执行 rsync 备份目录
rsync_backup_dir() {
    local source="$1"
    local destination="$2"
    local description="$3"

    echo "  - 备份目录: $description"
    if rsync -avz --delete "$source/" "$destination/" ; then
        echo "    - 成功: $description"
    else
        echo "    - 失败: $description"
        return 1
    fi
    return 0
}

# 备份系统配置
backup_system_config() {
    if check_root_privileges; then
        echo "开始备份: 系统配置"
        backup_system_config_dir="$backup_destination/系统配置"
        mkdir -p "$backup_system_config_dir"
        for source_path in "${backup_sources_system[@]}"; do
            destination_path="$backup_system_config_dir/$(basename "$source_path")"
            if [ -f "$source_path" ]; then
                backup_file "$source_path" "$destination_path" "系统配置 - $(basename "$source_path")"
            elif [ -d "$source_path" ]; then
                rsync_backup_dir "$source_path" "$destination_path" "系统配置 - $(basename "$source_path")"
            else
                echo "  - 警告: 系统配置项 '$source_path' 不是文件也不是目录，跳过备份。"
            fi
        done
    fi
}

# 备份用户配置和数据
backup_user_config() {
    echo "开始备份: 用户配置"
    backup_user_config_dir="$backup_destination/用户配置"
    mkdir -p "$backup_user_config_dir"
    for source_dir in "${backup_sources_user[@]}"; do
        rsync_backup_dir "$source_dir" "$backup_user_config_dir/$HOME" "用户配置和数据 - $HOME"
    done
}

# 备份软件包列表
backup_package_lists_func() {
    if [[ "$backup_package_lists" == true ]]; then
        echo "开始备份: 软件包管理 - 软件包列表"
        backup_package_dir="$backup_destination/软件包管理"
        mkdir -p "$backup_package_dir"
        echo "  - 备份: 手动安装的软件包列表"
        pacman -Qe > "$backup_package_dir/package-list-explicit.txt"
        echo "  - 备份: 所有安装的软件包列表"
        pacman -Q > "$backup_package_dir/package-list-all.txt"
        echo "软件包列表备份完成。"
    fi
}

# 备份 Pacman 日志
backup_pacman_log_func() {
    if [[ "$backup_pacman_log" == true ]]; then
        echo "开始备份: 软件包管理 - Pacman 日志"
        backup_package_dir="$backup_destination/软件包管理"
        mkdir -p "$backup_package_dir"
        backup_file "/var/log/pacman.log" "$backup_package_dir/pacman.log" "Pacman 日志"
    fi
}

# 备份系统日志 (journalctl)
backup_system_log_func() {
    if [[ "$backup_system_log" == true ]]; then
        echo "开始备份: 系统日志"
        backup_log_dir="$backup_destination/系统日志"
        mkdir -p "$backup_log_dir"
        journalctl --since "today" > "$backup_log_dir/system-log-$(date +%Y%m%d).log"
        echo "系统日志备份完成。"
    fi
}

# 备份数据库 (需要用户手动配置数据库备份命令)
backup_database_func() {
    if [[ "$backup_database" == true ]]; then
        echo "开始备份: 数据库数据 (未配置)"
        backup_db_dir="$backup_destination/数据库数据"
        mkdir -p "$backup_db_dir"
        echo "  - 警告: 数据库备份功能未配置，请手动添加数据库备份命令到 backup_database_func 函数中。"
        # 用户需要在此处添加数据库备份命令
    fi
}

# --- 主程序 ---

# 检查备份目标目录
if ! check_destination_directory; then
    exit 1
fi

# 生成时间戳作为备份目录名
timestamp=$(date +%Y%m%d_%H%M%S)
backup_destination="$backup_destination_root/backup_$timestamp"
mkdir -p "$backup_destination"

echo "--- 备份开始 ---"
echo "备份目录: $backup_destination"

# 执行备份
backup_system_config
backup_user_config
backup_package_lists_func
backup_pacman_log_func
backup_system_log_func
backup_database_func

echo "--- 所有备份任务完成 ---"
echo "备份目录: $backup_destination"

exit 0
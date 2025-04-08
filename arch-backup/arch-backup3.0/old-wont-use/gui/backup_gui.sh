#!/bin/bash

#############################################################
# Arch Linux 备份系统图形界面
#
# 功能:
#   提供简单的图形界面操作备份系统
#   支持配置备份选项、执行备份、查看备份历史等功能
#   基于zenity工具实现，轻量级且易于使用
#
# 依赖项:
#   - 外部命令: zenity, bash
#   - 核心脚本: arch-backup-main.sh 及其依赖
#
# 使用示例:
#   $ ./backup_gui.sh
#
#############################################################

# 获取脚本所在目录
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
PARENT_DIR=$(dirname "$SCRIPT_DIR")

# 检查zenity是否安装
check_zenity() {
    if ! command -v zenity &> /dev/null; then
        echo "错误: 未找到zenity命令，请安装zenity包"
        echo "在Arch Linux上，可以运行: sudo pacman -S zenity"
        exit 1
    fi
}

# 加载配置文件
load_config() {
    CONFIG_FILE="$PARENT_DIR/arch-backup.conf"
    if [ -f "$CONFIG_FILE" ]; then
        source "$CONFIG_FILE"
    else
        zenity --error --title="配置错误" --text="未找到配置文件: $CONFIG_FILE"
        exit 1
    fi
}

# 显示主菜单
show_main_menu() {
    local choice=$(zenity --list --title="Arch Linux 备份系统" \
        --text="请选择操作:" \
        --column="操作" \
        "执行备份" \
        "配置备份选项" \
        "查看备份历史" \
        "恢复备份" \
        "退出")
    
    case "$choice" in
        "执行备份")
            run_backup
            ;;
        "配置备份选项")
            configure_backup
            ;;
        "查看备份历史")
            view_backup_history
            ;;
        "恢复备份")
            restore_backup
            ;;
        "退出")
            exit 0
            ;;
        *)
            # 用户取消或关闭窗口
            exit 0
            ;;
    esac
}

# 执行备份
run_backup() {
    # 确认备份选项
    local confirm_text="将执行以下备份:\n"
    confirm_text+="- 备份根目录: $BACKUP_ROOT\n"
    confirm_text+="- 备份系统配置: $BACKUP_SYSTEM_CONFIG\n"
    confirm_text+="- 备份用户配置: $BACKUP_USER_CONFIG\n"
    confirm_text+="- 备份自定义路径: $BACKUP_CUSTOM_PATHS\n"
    confirm_text+="- 备份软件包列表: $BACKUP_PACKAGES\n"
    confirm_text+="- 备份系统日志: $BACKUP_LOGS\n\n"
    confirm_text+="- 差异备份: $DIFF_BACKUP\n"
    confirm_text+="- 增量备份: ${INCREMENTAL_BACKUP:-false}\n"
    confirm_text+="- 加密备份: ${ENCRYPT_BACKUP:-false}\n"
    confirm_text+="- 压缩备份: $COMPRESS_BACKUP\n"
    confirm_text+="- 并行备份: $PARALLEL_BACKUP\n"
    
    if ! zenity --question --title="确认备份" --text="$confirm_text" --ok-label="开始备份" --cancel-label="取消"; then
        show_main_menu
        return
    fi
    
    # 检查是否需要sudo权限
    local use_sudo=false
    if [ "$(id -u)" -ne 0 ]; then
        if zenity --question --title="权限确认" --text="某些系统文件可能需要root权限才能备份。\n是否使用sudo运行备份?" --ok-label="使用sudo" --cancel-label="不使用sudo"; then
            use_sudo=true
        fi
    fi
    
    # 创建进度窗口
    (
        echo "0"; echo "# 准备开始备份..."
        
        # 执行备份命令
        local backup_cmd="$PARENT_DIR/arch-backup-main.sh"
        local log_file="/tmp/arch-backup-$$.log"
        
        if [ "$use_sudo" = true ]; then
            echo "10"; echo "# 使用sudo权限执行备份..."
            sudo "$backup_cmd" > "$log_file" 2>&1 &
        else
            echo "10"; echo "# 开始执行备份..."
            "$backup_cmd" > "$log_file" 2>&1 &
        fi
        
        local pid=$!
        
        # 监控备份进度
        local progress=10
        while kill -0 $pid 2>/dev/null; do
            if [ $progress -lt 90 ]; then
                progress=$((progress + 1))
            fi
            
            # 从日志中获取最后一行作为状态信息
            local status=$(tail -n 1 "$log_file" 2>/dev/null | sed 's/\[[^]]*\]//g' | sed 's/^[ \t]*//')
            if [ -n "$status" ]; then
                echo "$progress"; echo "# $status"
            else
                echo "$progress"; echo "# 正在备份..."
            fi
            
            sleep 1
        done
        
        # 检查备份是否成功
        wait $pid
        local exit_code=$?
        
        if [ $exit_code -eq 0 ]; then
            echo "100"; echo "# 备份完成!"
        else
            echo "100"; echo "# 备份失败，退出码: $exit_code"
        fi
        
        sleep 1
    ) | zenity --progress --title="备份进行中" --text="准备开始备份..." --percentage=0 --auto-close --width=400
    
    # 备份完成后显示结果
    if [ ${PIPESTATUS[1]} -eq 0 ]; then
        zenity --info --title="备份完成" --text="备份已成功完成!\n\n备份目录: $BACKUP_ROOT"
    else
        zenity --error --title="备份失败" --text="备份过程中发生错误，请查看日志获取详细信息。\n\n日志文件: $LOG_FILE"
    fi
    
    show_main_menu
}

# 配置备份选项
configure_backup() {
    local config_choice=$(zenity --list --title="配置备份选项" \
        --text="请选择要配置的选项:" \
        --column="选项" \
        "备份目标目录" \
        "备份内容选择" \
        "备份方式设置" \
        "高级选项" \
        "返回主菜单")
    
    case "$config_choice" in
        "备份目标目录")
            configure_backup_dir
            ;;
        "备份内容选择")
            configure_backup_content
            ;;
        "备份方式设置")
            configure_backup_method
            ;;
        "高级选项")
            configure_advanced_options
            ;;
        "返回主菜单")
            show_main_menu
            ;;
        *)
            # 用户取消或关闭窗口
            show_main_menu
            ;;
    esac
}

# 配置备份目标目录
configure_backup_dir() {
    local new_backup_root=$(zenity --file-selection --directory --title="选择备份根目录" --filename="$BACKUP_ROOT")
    
    if [ -n "$new_backup_root" ]; then
        # 更新配置文件中的备份根目录
        sed -i "s|^BACKUP_ROOT=.*|BACKUP_ROOT=\"$new_backup_root\"|" "$CONFIG_FILE"
        zenity --info --title="配置已更新" --text="备份根目录已更新为:\n$new_backup_root"
    fi
    
    configure_backup
}

# 配置备份内容
configure_backup_content() {
    local content_options=$(zenity --list --title="备份内容选择" \
        --text="选择要备份的内容:" \
        --checklist --column="选择" --column="内容" --column="当前设置" \
        $BACKUP_SYSTEM_CONFIG "系统配置" "$BACKUP_SYSTEM_CONFIG" \
        $BACKUP_USER_CONFIG "用户配置" "$BACKUP_USER_CONFIG" \
        $BACKUP_CUSTOM_PATHS "自定义路径" "$BACKUP_CUSTOM_PATHS" \
        $BACKUP_PACKAGES "软件包列表" "$BACKUP_PACKAGES" \
        $BACKUP_LOGS "系统日志" "$BACKUP_LOGS")
    
    if [ -n "$content_options" ]; then
        # 更新配置文件中的备份内容选项
        if [[ $content_options == *"系统配置"* ]]; then
            sed -i "s/^BACKUP_SYSTEM_CONFIG=.*/BACKUP_SYSTEM_CONFIG=true/" "$CONFIG_FILE"
        else
            sed -i "s/^BACKUP_SYSTEM_CONFIG=.*/BACKUP_SYSTEM_CONFIG=false/" "$CONFIG_FILE"
        fi
        
        if [[ $content_options == *"用户配置"* ]]; then
            sed -i "s/^BACKUP_USER_CONFIG=.*/BACKUP_USER_CONFIG=true/" "$CONFIG_FILE"
        else
            sed -i "s/^BACKUP_USER_CONFIG=.*/BACKUP_USER_CONFIG=false/" "$CONFIG_FILE"
        fi
        
        if [[ $content_options == *"自定义路径"* ]]; then
            sed -i "s/^BACKUP_CUSTOM_PATHS=.*/BACKUP_CUSTOM_PATHS=true/" "$CONFIG_FILE"
        else
            sed -i "s/^BACKUP_CUSTOM_PATHS=.*/BACKUP_CUSTOM_PATHS=false/" "$CONFIG_FILE"
        fi
        
        if [[ $content_options == *"软件包列表"* ]]; then
            sed -i "s/^BACKUP_PACKAGES=.*/BACKUP_PACKAGES=true/" "$CONFIG_FILE"
        else
            sed -i "s/^BACKUP_PACKAGES=.*/BACKUP_PACKAGES=false/" "$CONFIG_FILE"
        fi
        
        if [[ $content_options == *"系统日志"* ]]; then
            sed -i "s/^BACKUP_LOGS=.*/BACKUP_LOGS=true/" "$CONFIG_FILE"
        else
            sed -i "s/^BACKUP_LOGS=.*/BACKUP_LOGS=false/" "$CONFIG_FILE"
        fi
        
        zenity --info --title="配置已更新" --text="备份内容选项已更新"
    fi
    
    configure_backup
}

# 配置备份方式
configure_backup_method() {
    local method_options=$(zenity --list --title="备份方式设置" \
        --text="选择备份方式:" \
        --checklist --column="选择" --column="方式" --column="当前设置" \
        $DIFF_BACKUP "差异备份" "$DIFF_BACKUP" \
        ${INCREMENTAL_BACKUP:-false} "增量备份" "${INCREMENTAL_BACKUP:-false}" \
        ${ENCRYPT_BACKUP:-false} "加密备份" "${ENCRYPT_BACKUP:-false}" \
        $COMPRESS_BACKUP "压缩备份" "$COMPRESS_BACKUP" \
        $PARALLEL_BACKUP "并行备份" "$PARALLEL_BACKUP")
    
    if [ -n "$method_options" ]; then
        # 更新配置文件中的备份方式选项
        if [[ $method_options == *"差异备份"* ]]; then
            sed -i "s/^DIFF_BACKUP=.*/DIFF_BACKUP=true/" "$CONFIG_FILE"
        else
            sed -i "s/^DIFF_BACKUP=.*/DIFF_BACKUP=false/" "$CONFIG_FILE"
        fi
        
        # 增量备份选项可能不存在，需要检查并添加
        if [[ $method_options == *"增量备份"* ]]; then
            if grep -q "^INCREMENTAL_BACKUP=" "$CONFIG_FILE"; then
                sed -i "s/^INCREMENTAL_BACKUP=.*/INCREMENTAL_BACKUP=true/" "$CONFIG_FILE"
            else
                # 在DIFF_BACKUP后面添加INCREMENTAL_BACKUP选项
                sed -i "/^DIFF_BACKUP=/a\INCREMENTAL_BACKUP=true" "$CONFIG_FILE"
            fi
        else
            if grep -q "^INCREMENTAL_BACKUP=" "$CONFIG_FILE"; then
                sed -i "s/^INCREMENTAL_BACKUP=.*/INCREMENTAL_BACKUP=false/" "$CONFIG_FILE"
            else
                sed -i "/^DIFF_BACKUP=/a\INCREMENTAL_BACKUP=false" "$CONFIG_FILE"
            fi
        fi
        
        # 加密备份选项可能不存在，需要检查并添加
        if [[ $method_options == *"加密备份"* ]]; then
            if grep -q "^ENCRYPT_BACKUP=" "$CONFIG_FILE"; then
                sed -i "s/^ENCRYPT_BACKUP=.*/ENCRYPT_BACKUP=true/" "$CONFIG_FILE"
            else
                # 在INCREMENTAL_BACKUP后面添加ENCRYPT_BACKUP选项
                sed -i "/^INCREMENTAL_BACKUP=/a\ENCRYPT_BACKUP=true" "$CONFIG_FILE"
                # 如果没有INCREMENTAL_BACKUP，则在DIFF_BACKUP后面添加
                if [ $? -ne 0 ]; then
                    sed -i "/^DIFF_BACKUP=/a\ENCRYPT_BACKUP=true" "$CONFIG_FILE"
                fi
            fi
            
            # 如果启用了加密，询问加密密码
            local encrypt_password=$(zenity --entry --title="加密密码" --text="请输入备份加密密码:" --hide-text)
            if [ -n "$encrypt_password" ]; then
                if grep -q "^ENCRYPT_PASSWORD=" "$CONFIG_FILE"; then
                    sed -i "s/^ENCRYPT_PASSWORD=.*/ENCRYPT_PASSWORD=\"$encrypt_password\"/" "$CONFIG_FILE"
                else
                    sed -i "/^ENCRYPT_BACKUP=/a\ENCRYPT_PASSWORD=\"$encrypt_password\"" "$CONFIG_FILE"
                fi
            fi
        else
            if grep -q "^ENCRYPT_BACKUP=" "$CONFIG_FILE"; then
                sed -i "s/^ENCRYPT_BACKUP=.*/ENCRYPT_BACKUP=false/" "$CONFIG_FILE"
            else
                sed -i "/^INCREMENTAL_BACKUP=/a\ENCRYPT_BACKUP=false" "$CONFIG_FILE"
                # 如果没有INCREMENTAL_BACKUP，则在DIFF_BACKUP后面添加
                if [ $? -ne 0 ]; then
                    sed -i "/^DIFF_BACKUP=/a\ENCRYPT_BACKUP=false" "$CONFIG_FILE"
                fi
            fi
        fi
        
        if [[ $method_options == *"压缩备份"* ]]; then
            sed -i "s/^COMPRESS_BACKUP=.*/COMPRESS_BACKUP=true/" "$CONFIG_FILE"
        else
            sed -i "s/^COMPRESS_BACKUP=.*/COMPRESS_BACKUP=false/" "$CONFIG_FILE"
        fi
        
        if [[ $method_options == *"并行备份"* ]]; then
            sed -i "s/^PARALLEL_BACKUP=.*/PARALLEL_BACKUP=true/" "$CONFIG_FILE"
        else
            sed -i "s/^PARALLEL_BACKUP=.*/PARALLEL_BACKUP=false/" "$CONFIG_FILE"
        fi
        
        zenity --info --title="配置已更新" --text="备份方式选项已更新"
    fi
    
    configure_backup
}

# 主函数
main() {
    # 检查zenity是否安装
    check_zenity
    
    # 加载配置文件
    load_config
    
    # 显示主菜单
    show_main_menu
}

# 执行主函数
main
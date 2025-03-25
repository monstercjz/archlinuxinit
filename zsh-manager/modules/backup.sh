#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

# 使用SOURCE_DIR确保正确引用utils.sh
source "$SOURCE_DIR/core/utils.sh"

BACKUP_TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
BACKUP_FILE="$BACKUP_DIR/zsh_backup_$BACKUP_TIMESTAMP.tar.gz"

manage_backup() {
    local operation=$1
    
    case $operation in
        "backup")
            show_status "info" "开始备份 Zsh 配置"
            
            # 确保备份目录存在
            mkdir -p "$BACKUP_DIR"
            
            # 创建临时目录
            local temp_dir="/tmp/zsh_backup_$BACKUP_TIMESTAMP"
            mkdir -p "$temp_dir"
            
            # 复制配置文件到临时目录
            cp -f "$ZSHRC" "$temp_dir/" 2>/dev/null
            cp -f "$P10K_CONFIG" "$temp_dir/" 2>/dev/null
            
            # 创建备份文件
            tar -czf "$BACKUP_FILE" -C "$(dirname "$temp_dir")" "$(basename "$temp_dir")" && {
                show_status "success" "备份已创建: $BACKUP_FILE"
                rm -rf "$temp_dir"
            } || {
                show_status "error" "备份创建失败"
                rm -rf "$temp_dir"
                return 1
            }
            ;;
            
        "restore")
            # 列出可用的备份文件
            local backups=("$BACKUP_DIR"/*.tar.gz)
            
            if [ ${#backups[@]} -eq 0 ] || [ ! -f "${backups[0]}" ]; then
                show_status "error" "没有找到可用的备份文件"
                return 1
            fi
            
            echo "可用的备份文件:"
            for i in "${!backups[@]}"; do
                echo "$((i+1)). $(basename "${backups[$i]}")"
            done
            
            read -p "选择要恢复的备份文件 (1-${#backups[@]}): " choice
            
            if [[ ! $choice =~ ^[0-9]+$ ]] || [ $choice -lt 1 ] || [ $choice -gt ${#backups[@]} ]; then
                show_status "error" "无效的选择"
                return 1
            fi
            
            local selected_backup="${backups[$((choice-1))]}"
            
            # 确认恢复操作
            confirm_action "restore" "从 $(basename "$selected_backup") 恢复配置" || return 0
            
            # 创建临时目录
            local temp_dir="/tmp/zsh_restore_$BACKUP_TIMESTAMP"
            mkdir -p "$temp_dir"
            
            # 解压备份文件
            tar -xzf "$selected_backup" -C "$temp_dir" && {
                # 恢复配置文件
                local extracted_dir=$(find "$temp_dir" -type d -name "zsh_backup_*")
                
                if [ -z "$extracted_dir" ]; then
                    show_status "error" "备份文件格式错误"
                    rm -rf "$temp_dir"
                    return 1
                fi
                
                # 备份当前配置
                backup_files
                
                # 恢复配置文件
                cp -f "$extracted_dir"/.zshrc "$HOME/" 2>/dev/null
                cp -f "$extracted_dir"/.p10k.zsh "$HOME/" 2>/dev/null
                
                show_status "success" "配置已恢复"
                rm -rf "$temp_dir"
            } || {
                show_status "error" "恢复失败"
                rm -rf "$temp_dir"
                return 1
            }
            ;;
            
        "list")
            local backups=("$BACKUP_DIR"/*.tar.gz)
            
            if [ ${#backups[@]} -eq 0 ] || [ ! -f "${backups[0]}" ]; then
                show_status "info" "没有找到备份文件"
                return 0
            fi
            
            show_status "info" "可用的备份文件:"
            for backup in "${backups[@]}"; do
                echo "- $(basename "$backup") ($(du -h "$backup" | cut -f1))"
            done
            ;;
            
        "delete")
            local backups=("$BACKUP_DIR"/*.tar.gz)
            
            if [ ${#backups[@]} -eq 0 ] || [ ! -f "${backups[0]}" ]; then
                show_status "error" "没有找到可用的备份文件"
                return 1
            fi
            
            echo "可用的备份文件:"
            for i in "${!backups[@]}"; do
                echo "$((i+1)). $(basename "${backups[$i]}")"
            done
            
            read -p "选择要删除的备份文件 (1-${#backups[@]}, 'all' 删除所有): " choice
            
            if [ "$choice" = "all" ]; then
                confirm_action "delete" "所有备份文件" || return 0
                rm -f "$BACKUP_DIR"/*.tar.gz
                show_status "success" "所有备份文件已删除"
            elif [[ $choice =~ ^[0-9]+$ ]] && [ $choice -ge 1 ] && [ $choice -le ${#backups[@]} ]; then
                local selected_backup="${backups[$((choice-1))]}"
                confirm_action "delete" "备份文件 $(basename "$selected_backup")" || return 0
                rm -f "$selected_backup"
                show_status "success" "备份文件已删除"
            else
                show_status "error" "无效的选择"
                return 1
            fi
            ;;
    esac
}
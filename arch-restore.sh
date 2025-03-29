#!/bin/bash

#############################################################
# Arch Linux 恢复脚本
# 配套 back_archlinux*.sh 脚本使用
# 功能：从备份中恢复系统配置、用户配置、自定义路径和软件包列表
# 支持选择性恢复、恢复前备份、交互式界面和恢复后验证
#############################################################

# 获取实际用户（处理sudo情况）
if [ -n "$SUDO_USER" ]; then
    REAL_USER="$SUDO_USER"
    REAL_HOME="/home/$SUDO_USER"
else
    REAL_USER=$(whoami)
    REAL_HOME="$HOME"
fi

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 默认配置 (会被配置文件覆盖)
BACKUP_ROOT="/mnt/backup/arch-backup"
CONFIG_FILE="$REAL_HOME/.config/arch-backup.conf"
RESTORE_LOG_FILE="${BACKUP_ROOT}/restore_$(date +%Y-%m-%d_%H-%M-%S).log"
BACKUP_BEFORE_RESTORE=true
BACKUP_SUFFIX="_pre_restore_$(date +%Y%m%d%H%M%S)"

# 创建日志函数
log() {
    local level=$1
    local message=$2
    local color=$NC

    case $level in
        "INFO") color=$GREEN ;;
        "WARN") color=$YELLOW ;;
        "ERROR") color=$RED ;;
        "FATAL") color=$RED ;;
        "DEBUG") color=$BLUE ;;
        *) color=$BLUE ;;
    esac

    echo -e "${color}[$(date '+%Y-%m-%d %H:%M:%S')] [${level}] ${message}${NC}" | tee -a "$RESTORE_LOG_FILE"

    # 如果是致命错误，退出脚本
    if [ "$level" == "FATAL" ]; then
        echo -e "${RED}恢复过程中遇到致命错误，退出脚本${NC}" | tee -a "$RESTORE_LOG_FILE"
        exit 1
    fi
}

# 检查命令是否存在
check_command() {
    command -v "$1" >/dev/null 2>&1 || { log "FATAL" "命令 $1 未安装，请先安装该命令"; exit 1; }
}

# 检查必要的命令
check_dependencies() {
    log "INFO" "检查恢复所需依赖..."
    local missing_deps=0
    local deps=("rsync" "tar" "gzip" "bzip2" "xz" "diff" "cmp" "pacman")
    local desc=("文件同步工具" "归档工具" "gzip解压" "bzip2解压" "xz解压" "文件比较" "字节比较" "包管理器")

    for i in "${!deps[@]}"; do
        if ! command -v "${deps[$i]}" >/dev/null 2>&1; then
            # pacman 不是所有恢复都必须，但恢复软件包列表需要
            if [ "${deps[$i]}" == "pacman" ]; then
                 log "WARN" "依赖 ${deps[$i]} (${desc[$i]}) 未安装，将无法恢复软件包列表"
            else
                 log "ERROR" "核心依赖 ${deps[$i]} (${desc[$i]}) 未安装"
                 log "INFO" "请使用以下命令安装: sudo pacman -S ${deps[$i]}"
                 missing_deps=$((missing_deps + 1))
            fi
        else
            log "INFO" "依赖 ${deps[$i]} 已安装"
        fi
    done

    if [ $missing_deps -gt 0 ]; then
        log "FATAL" "检测到 $missing_deps 个必要依赖缺失，请安装后再运行脚本"
        exit 1
    else
        log "INFO" "所有必要依赖检查通过"
        return 0
    fi
}

# 加载配置文件
load_config() {
    if [ -f "$CONFIG_FILE" ]; then
        log "INFO" "加载配置文件: $CONFIG_FILE"
        # 加载配置，同时保留脚本中的默认值（如果配置文件中未定义）
        # shellcheck source=/dev/null
        source <(grep -v '^\s*#' "$CONFIG_FILE" | sed -e 's/^\(.*\)=\(.*\)$/:\ ${\1=\2}/')
    else
        log "WARN" "配置文件 $CONFIG_FILE 不存在，将使用默认配置。"
        log "WARN" "强烈建议您先运行备份脚本生成配置文件，或手动创建。"
        # 可以在这里提示用户是否继续，或者直接退出
        read -p "配置文件不存在，是否继续使用默认设置? (y/N): " confirm < /dev/tty # Read from tty
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            log "FATAL" "用户选择中止操作。"
            exit 1
        fi
    fi

    # 确保 BACKUP_ROOT 存在且可读
    if [ ! -d "$BACKUP_ROOT" ] || [ ! -r "$BACKUP_ROOT" ]; then
        log "FATAL" "备份根目录 '$BACKUP_ROOT' 不存在或不可读，请检查配置或权限。"
        exit 1
    fi

    # 创建日志目录
    mkdir -p "$(dirname "$RESTORE_LOG_FILE")"
    touch "$RESTORE_LOG_FILE"
}

# --- 恢复功能函数 ---

# 选择恢复选项
# $1: 选定的备份目录路径
# 返回用户选择要恢复的组件列表 (空格分隔) 和是否执行恢复前备份的标志 (true/false)
# 使用全局变量存储选择结果以避免复杂的返回值处理
SELECTED_COMPONENTS=""
DO_BACKUP_BEFORE_RESTORE=$BACKUP_BEFORE_RESTORE # 初始化为配置文件或默认值

select_restore_options() {
    local backup_dir=$1
    local available_components=()
    local component_options=()
    local i=1

    log "INFO" "检查备份目录 '$backup_dir' 中的可用恢复组件..."

    # 检查各组件是否存在
    if [ -d "${backup_dir}/etc" ]; then
        available_components+=("etc")
        component_options+=("$i) 系统配置 (/etc)")
        i=$((i + 1))
    else
        log "DEBUG" "备份中未找到 'etc' 组件。"
    fi

    if [ -d "${backup_dir}/home" ]; then
        available_components+=("home")
        component_options+=("$i) 用户配置 (~/)")
        i=$((i + 1))
    else
        log "DEBUG" "备份中未找到 'home' 组件。"
    fi

    if [ -d "${backup_dir}/custom" ]; then
        available_components+=("custom")
        component_options+=("$i) 自定义路径")
        i=$((i + 1))
    else
        log "DEBUG" "备份中未找到 'custom' 组件。"
    fi

    if [ -d "${backup_dir}/packages" ] && [ -f "${backup_dir}/packages/manually-installed.txt" ]; then
        available_components+=("packages")
        component_options+=("$i) 软件包列表")
        i=$((i + 1))
    else
        log "DEBUG" "备份中未找到 'packages' 组件或列表文件。"
    fi

    if [ ${#available_components[@]} -eq 0 ]; then
        log "FATAL" "在备份源 '$backup_dir' 中未找到任何可恢复的组件。"
        exit 1
    fi

    log "INFO" "备份中包含以下可恢复组件:"
    # Print to screen first
    echo -e "${GREEN}备份中包含以下可恢复组件:${NC}"
    for option in "${component_options[@]}"; do
        echo "$option"
    done
    echo "$i) 全部恢复"
    # Log to file
    printf "%s\n" "${component_options[@]}" >> "$RESTORE_LOG_FILE"
    echo "$i) 全部恢复" >> "$RESTORE_LOG_FILE"

    component_options+=("$i) 全部恢复") # 添加“全部”选项

    local choice
    local valid_choice=false
    while ! $valid_choice; do
        # Add small delay before read
        sleep 0.5
        read -p "请选择要恢复的组件编号 (可多选，用空格分隔，或选 '$i' 恢复全部): " choice < /dev/tty # Read from tty
        
        # 清空上次选择
        SELECTED_COMPONENTS=""
        local temp_selected=()
        
        # 处理输入
        for c in $choice; do
            if [[ "$c" =~ ^[0-9]+$ ]]; then
                if [ "$c" -ge 1 ] && [ "$c" -lt $i ]; then # 单个组件选项
                    local selected_index=$((c-1))
                    # 避免重复添加
                    if [[ ! " ${temp_selected[@]} " =~ " ${available_components[$selected_index]} " ]]; then
                         temp_selected+=("${available_components[$selected_index]}")
                         valid_choice=true # 至少有一个有效选择
                    fi
                elif [ "$c" -eq $i ]; then # 全部恢复选项
                    temp_selected=("${available_components[@]}") # 选择所有可用组件
                    valid_choice=true
                    break # 如果选了全部，则忽略其他选项
                else
                    log "ERROR" "无效的编号: $c。请输入 1 到 $i 之间的数字。"
                    valid_choice=false
                    break # 有一个无效则重新输入
                fi
            else
                log "ERROR" "无效的输入: $c。请输入数字。"
                valid_choice=false
                break # 有一个无效则重新输入
            fi
        done
        
        if $valid_choice; then
             SELECTED_COMPONENTS=$(echo "${temp_selected[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ') # 去重并转换为空格分隔的字符串
             log "INFO" "已选择恢复组件: $SELECTED_COMPONENTS"
        fi
    done

    # 询问是否执行恢复前备份
    if [ "$BACKUP_BEFORE_RESTORE" == "true" ]; then
        local backup_confirm
        read -p "是否在恢复前备份当前将被覆盖的文件? (Y/n): " backup_confirm < /dev/tty # Read from tty
        if [[ "$backup_confirm" =~ ^[Nn]$ ]]; then
            DO_BACKUP_BEFORE_RESTORE=false
            log "INFO" "用户选择不在恢复前执行备份。"
        else
            DO_BACKUP_BEFORE_RESTORE=true
            log "INFO" "将在恢复前备份受影响的文件/目录。"
        fi
    else
        DO_BACKUP_BEFORE_RESTORE=false # 如果配置禁用，则不询问
    fi

    return 0
}

# 恢复前备份现有文件/目录
# $1: 目标路径 (文件或目录)
backup_before_restore() {
    local target_path=$1
    
    if [ ! -e "$target_path" ]; then
        log "DEBUG" "目标路径不存在，无需执行恢复前备份: $target_path"
        return 0
    fi

    local backup_path="${target_path}${BACKUP_SUFFIX}"
    log "INFO" "执行恢复前备份: 将 '$target_path' 移动到 '$backup_path'"

    # 尝试移动，如果失败（例如跨设备），则尝试复制和删除
    if sudo mv "$target_path" "$backup_path" >> "$RESTORE_LOG_FILE" 2>&1; then
        log "INFO" "恢复前备份成功 (移动): $backup_path"
        return 0
    else
        log "WARN" "移动失败，尝试复制和删除进行恢复前备份: $target_path"
        # 对于目录，使用 rsync 复制；对于文件，使用 cp
        if [ -d "$target_path" ]; then
             if sudo rsync -aAX "$target_path/" "$backup_path/" >> "$RESTORE_LOG_FILE" 2>&1; then
                 sudo rm -rf "$target_path"
                 log "INFO" "恢复前备份成功 (复制目录): $backup_path"
                 return 0
             fi
        elif [ -f "$target_path" ]; then
             if sudo cp -a "$target_path" "$backup_path" >> "$RESTORE_LOG_FILE" 2>&1; then
                 sudo rm -f "$target_path"
                 log "INFO" "恢复前备份成功 (复制文件): $backup_path"
                 return 0
             fi
        fi
        
        log "ERROR" "恢复前备份失败: $target_path"
        # 询问用户是否继续，因为无法备份原始文件
        read -p "无法备份原始路径 '$target_path'。是否继续恢复并覆盖? (y/N): " confirm_overwrite < /dev/tty # Read from tty
        if [[ ! "$confirm_overwrite" =~ ^[Yy]$ ]]; then
            log "FATAL" "用户选择中止恢复。"
            exit 1
        else
             log "WARN" "用户选择继续恢复，将直接覆盖 '$target_path'"
             return 1 # 表示备份失败但用户选择继续
        fi
    fi
}

# 执行恢复操作
# $1: 选定的备份目录路径
# $2: 要恢复的组件列表 (空格分隔)
# $3: 是否执行恢复前备份 (true/false)
execute_restore() {
    local backup_dir=$1
    local components_to_restore="$2"
    local do_backup=$3
    local restore_errors=0

    log "INFO" "开始执行恢复操作..."
    log "INFO" "将恢复以下组件: $components_to_restore"
    log "INFO" "是否执行恢复前备份: $do_backup"

    # 提示用户确认恢复操作
    echo -e "${YELLOW}警告：恢复操作将覆盖现有文件！${NC}"
    read -p "请确认是否继续执行恢复? (y/N): " confirm_restore < /dev/tty # Read from tty
    if [[ ! "$confirm_restore" =~ ^[Yy]$ ]]; then
        log "FATAL" "用户取消了恢复操作。"
        exit 1
    fi

    for component in $components_to_restore; do
        log "INFO" "--- 开始恢复组件: $component ---"
        case $component in
            "etc")
                local src="${backup_dir}/etc/"
                local dest="/"
                if [ -d "$src" ]; then
                    log "INFO" "恢复系统配置到 $dest"
                    if [ "$do_backup" == "true" ]; then
                        # 对 /etc 目录下的文件/子目录进行恢复前备份比较复杂，
                        # 这里选择备份整个 /etc 目录一次，如果用户选择恢复 etc
                        backup_before_restore "/etc"
                    fi
                    # 使用 rsync 恢复，需要 root 权限
                    # --delete 会删除目标目录中备份源不存在的文件
                    log "INFO" "使用 rsync 恢复 /etc ..."
                    if sudo rsync -aAX --delete "$src" "${dest}etc/" >> "$RESTORE_LOG_FILE" 2>&1; then
                        log "INFO" "系统配置恢复成功。"
                    else
                        log "ERROR" "系统配置恢复失败。"
                        restore_errors=$((restore_errors + 1))
                    fi
                else
                    log "WARN" "备份中未找到 'etc' 目录，跳过恢复。"
                fi
                ;;
            "home")
                local src="${backup_dir}/home/"
                local dest="$REAL_HOME/"
                if [ -d "$src" ]; then
                    log "INFO" "恢复用户配置到 $dest"
                    # 对用户家目录执行恢复前备份可能非常耗时且占用大量空间
                    # 更好的方法是在 rsync 恢复时处理单个文件/目录
                    # 这里简化处理：如果用户选择恢复前备份，提示风险
                    if [ "$do_backup" == "true" ]; then
                         log "WARN" "对整个家目录执行恢复前备份可能非常耗时且占用大量空间。"
                         log "WARN" "建议仅在恢复少量特定文件时启用此选项，或手动备份重要文件。"
                         read -p "是否仍要尝试对 '$dest' 中受影响的文件进行恢复前备份? (y/N): " confirm_home_backup < /dev/tty # Read from tty
                         if [[ "$confirm_home_backup" =~ ^[Yy]$ ]]; then
                             # 实际操作中，rsync 的 --backup 和 --backup-dir 选项更适合这种情况
                             # 但为了与 backup_before_restore 函数一致，这里可以尝试调用它
                             # 注意：这可能不是最优解
                             log "INFO" "尝试对 $dest 执行恢复前备份..."
                             # backup_before_restore "$dest" # 备份整个家目录风险高，暂不实现
                             log "WARN" "对家目录的恢复前备份功能暂未完全实现，建议手动备份。"
                             # 或者，可以在 rsync 中使用 --backup --suffix=$BACKUP_SUFFIX
                         else
                             log "INFO" "跳过对家目录的恢复前备份。"
                             do_backup=false # 临时禁用家目录的备份
                         fi
                    fi
                    
                    # 使用 rsync 恢复，确保目标目录存在
                    mkdir -p "$dest"
                    log "INFO" "使用 rsync 恢复 $REAL_USER 的家目录文件..."
                    # 使用当前用户的权限恢复，避免权限问题
                    # --delete 会删除目标目录中备份源不存在的文件
                    local rsync_opts="-aAX --delete"
                    if [ "$do_backup" == "true" ]; then
                        # 使用 rsync 的备份功能代替我们自己的函数可能更好
                        rsync_opts="$rsync_opts --backup --suffix=$BACKUP_SUFFIX"
                        log "INFO" "启用 rsync 的 --backup 功能进行恢复前备份。"
                    fi

                    if rsync $rsync_opts "$src" "$dest" >> "$RESTORE_LOG_FILE" 2>&1; then
                        log "INFO" "用户配置恢复成功。"
                        # 确保恢复后的文件属于用户
                        sudo chown -R $REAL_USER:$REAL_USER "$dest"
                    else
                        log "ERROR" "用户配置恢复失败。"
                        restore_errors=$((restore_errors + 1))
                    fi
                else
                    log "WARN" "备份中未找到 'home' 目录，跳过恢复。"
                fi
                ;;
            "custom")
                local src_base="${backup_dir}/custom/"
                if [ -d "$src_base" ] && [ -n "$CUSTOM_PATHS" ]; then
                    log "INFO" "恢复自定义路径..."
                    IFS=' ' read -r -a custom_paths_array <<< "$CUSTOM_PATHS"
                    for target_path in "${custom_paths_array[@]}"; do
                        local base_name=$(basename "$target_path")
                        local src_path="${src_base}${base_name}"
                        
                        if [ -e "$src_path" ]; then
                            log "INFO" "恢复自定义路径: '$src_path' 到 '$target_path'"
                            # 确保目标路径的父目录存在
                            sudo mkdir -p "$(dirname "$target_path")"
                            
                            if [ "$do_backup" == "true" ]; then
                                backup_before_restore "$target_path"
                            fi
                            
                            # 使用 rsync 恢复，需要 root 权限处理 /opt, /srv 等目录
                            log "INFO" "使用 rsync 恢复 $target_path ..."
                            if sudo rsync -aAX --delete "$src_path" "$target_path" >> "$RESTORE_LOG_FILE" 2>&1; then
                                log "INFO" "自定义路径 '$target_path' 恢复成功。"
                            else
                                log "ERROR" "自定义路径 '$target_path' 恢复失败。"
                                restore_errors=$((restore_errors + 1))
                            fi
                        else
                            log "WARN" "在备份的 custom 目录中未找到 '$base_name'，无法恢复 '$target_path'"
                        fi
                    done
                elif [ -z "$CUSTOM_PATHS" ]; then
                     log "WARN" "配置文件中未定义 CUSTOM_PATHS，跳过自定义路径恢复。"
                else
                    log "WARN" "备份中未找到 'custom' 目录，跳过恢复。"
                fi
                ;;
            "packages")
                local pkglist_file="${backup_dir}/packages/manually-installed.txt"
                if [ -f "$pkglist_file" ]; then
                    if command -v pacman >/dev/null 2>&1; then
                        log "INFO" "恢复软件包列表..."
                        log "INFO" "将从 $pkglist_file 安装软件包"
                        
                        # 读取软件包列表并过滤掉空行和注释
                        local packages_to_install=$(grep -vE '^\s*(#|$)' "$pkglist_file" | awk '{print $1}' | tr '\n' ' ')
                        
                        if [ -n "$packages_to_install" ]; then
                            log "INFO" "准备安装以下软件包: $packages_to_install"
                            # 提示用户确认安装
                            read -p "是否继续安装这些软件包? (y/N): " confirm_install < /dev/tty # Read from tty
                            if [[ "$confirm_install" =~ ^[Yy]$ ]]; then
                                # 使用 pacman 安装，--needed 避免重新安装已是最新版本的包
                                if sudo pacman -S --needed --noconfirm $packages_to_install >> "$RESTORE_LOG_FILE" 2>&1; then
                                    log "INFO" "软件包列表恢复成功。"
                                else
                                    log "ERROR" "软件包列表恢复过程中发生错误，部分软件包可能未安装。"
                                    log "ERROR" "请检查日志 $RESTORE_LOG_FILE 和 pacman 日志 (/var/log/pacman.log) 获取详细信息。"
                                    restore_errors=$((restore_errors + 1))
                                fi
                            else
                                log "INFO" "用户取消了软件包安装。"
                            fi
                        else
                            log "WARN" "软件包列表文件 '$pkglist_file' 为空或无效。"
                        fi
                    else
                        log "ERROR" "未找到 pacman 命令，无法恢复软件包列表。"
                        restore_errors=$((restore_errors + 1))
                    fi
                else
                    log "WARN" "备份中未找到软件包列表文件 '$pkglist_file'，跳过恢复。"
                fi
                ;;
            *)
                log "WARN" "未知的恢复组件: $component"
                ;;
        esac
        log "INFO" "--- 完成恢复组件: $component ---"
    done

    log "INFO" "恢复操作执行完毕。"
    if [ $restore_errors -gt 0 ]; then
        log "ERROR" "恢复过程中共发生 $restore_errors 个错误。"
        return 1
    else
        log "INFO" "所有选定组件均已成功恢复。"
        return 0
    fi
}

# 验证恢复结果
# $1: 选定的备份目录路径
# $2: 已恢复的组件列表 (空格分隔)
verify_restore() {
    local backup_dir=$1
    local restored_components="$2"
    local verify_errors=0

    log "INFO" "开始验证恢复结果..."

    # 询问用户是否执行验证
    read -p "是否执行恢复后验证? (可能会花费一些时间) (Y/n): " confirm_verify < /dev/tty # Read from tty
    if [[ "$confirm_verify" =~ ^[Nn]$ ]]; then
        log "INFO" "用户跳过了恢复后验证。"
        return 0
    fi

    for component in $restored_components; do
        log "INFO" "--- 开始验证组件: $component ---"
        case $component in
            "etc")
                local src="${backup_dir}/etc/"
                local dest="/etc/"
                log "INFO" "验证系统配置..."
                # 使用 diff 递归比较，忽略权限和所有者差异，只报告文件内容差异
                # 注意：这可能需要 root 权限读取 /etc
                if sudo diff -rq --no-dereference "$src" "$dest" >> "${RESTORE_LOG_FILE}.diff" 2>&1; then
                    log "INFO" "系统配置验证成功 (与备份源内容一致)。"
                else
                    log "WARN" "系统配置验证发现差异。详细差异已记录到 ${RESTORE_LOG_FILE}.diff"
                    # 不计为错误，因为某些文件（如 mtab, resolv.conf.tmp）可能在恢复后立即被系统修改
                    # verify_errors=$((verify_errors + 1))
                fi
                # 也可以选择性地比较几个关键文件
                local critical_files=("fstab" "passwd" "group" "hosts")
                for file in "${critical_files[@]}"; do
                     if [ -f "${src}${file}" ] && [ -f "${dest}${file}" ]; then
                         if sudo cmp -s "${src}${file}" "${dest}${file}"; then
                              log "INFO" "关键文件 ${dest}${file} 验证通过。"
                         else
                              log "ERROR" "关键文件 ${dest}${file} 验证失败 (内容与备份不符)。"
                              verify_errors=$((verify_errors + 1))
                         fi
                     fi
                done
                ;;
            "home")
                local src="${backup_dir}/home/"
                local dest="$REAL_HOME/"
                log "INFO" "验证用户配置..."
                # 比较用户家目录可能非常耗时
                # 选择性比较几个关键配置文件
                local critical_configs=(".bashrc" ".zshrc" ".gitconfig")
                 for cfg in "${critical_configs[@]}"; do
                     if [ -f "${src}${cfg}" ] && [ -f "${dest}${cfg}" ]; then
                         # 使用当前用户权限比较
                         if cmp -s "${src}${cfg}" "${dest}${cfg}"; then
                              log "INFO" "用户配置文件 ${dest}${cfg} 验证通过。"
                         else
                              log "ERROR" "用户配置文件 ${dest}${cfg} 验证失败 (内容与备份不符)。"
                              verify_errors=$((verify_errors + 1))
                         fi
                     elif [ -f "${src}${cfg}" ]; then
                         log "WARN" "用户配置文件 ${dest}${cfg} 未找到，但备份中存在。"
                     fi
                 done
                 # 可以添加对 .ssh 或 .config 等目录的抽样检查
                ;;
            "custom")
                local src_base="${backup_dir}/custom/"
                if [ -d "$src_base" ] && [ -n "$CUSTOM_PATHS" ]; then
                    log "INFO" "验证自定义路径..."
                    IFS=' ' read -r -a custom_paths_array <<< "$CUSTOM_PATHS"
                    for target_path in "${custom_paths_array[@]}"; do
                        local base_name=$(basename "$target_path")
                        local src_path="${src_base}${base_name}"
                        
                        if [ -e "$src_path" ] && [ -e "$target_path" ]; then
                            log "INFO" "验证自定义路径: $target_path"
                            # 使用 diff 递归比较
                            if sudo diff -rq --no-dereference "$src_path" "$target_path" >> "${RESTORE_LOG_FILE}.diff" 2>&1; then
                                log "INFO" "自定义路径 '$target_path' 验证成功。"
                            else
                                log "WARN" "自定义路径 '$target_path' 验证发现差异。详细差异已记录到 ${RESTORE_LOG_FILE}.diff"
                                # verify_errors=$((verify_errors + 1))
                            fi
                        elif [ -e "$src_path" ]; then
                             log "ERROR" "自定义路径 '$target_path' 未找到，但备份中存在。"
                             verify_errors=$((verify_errors + 1))
                        fi
                    done
                fi
                ;;
            "packages")
                local pkglist_file="${backup_dir}/packages/manually-installed.txt"
                if [ -f "$pkglist_file" ]; then
                     if command -v pacman >/dev/null 2>&1; then
                        log "INFO" "验证已安装的软件包..."
                        local missing_pkgs=0
                        # 读取备份列表中的包名
                        while IFS= read -r line || [[ -n "$line" ]]; do
                            # 跳过空行和注释
                            [[ "$line" =~ ^\s*(#|$) ]] && continue
                            local pkg_name=$(echo "$line" | awk '{print $1}')
                            # 检查包是否已安装
                            if ! pacman -Q "$pkg_name" >/dev/null 2>&1; then
                                log "ERROR" "软件包验证失败: '$pkg_name' 在备份列表中，但当前未安装。"
                                missing_pkgs=$((missing_pkgs + 1))
                            fi
                        done < "$pkglist_file"

                        if [ $missing_pkgs -eq 0 ]; then
                            log "INFO" "软件包验证成功 (备份列表中的所有包均已安装)。"
                        else
                            log "ERROR" "软件包验证失败: $missing_pkgs 个在备份列表中的软件包当前未安装。"
                            verify_errors=$((verify_errors + missing_pkgs))
                        fi
                    else
                        log "WARN" "未找到 pacman 命令，跳过软件包验证。"
                    fi
                fi
                ;;
            *)
                log "DEBUG" "无需验证组件: $component"
                ;;
        esac
        log "INFO" "--- 完成验证组件: $component ---"
    done

    log "INFO" "恢复后验证完成。"
    if [ $verify_errors -gt 0 ]; then
        log "ERROR" "验证过程中共发现 $verify_errors 个错误/不一致项。请检查上面的日志和 ${RESTORE_LOG_FILE}.diff 文件。"
        return 1
    else
        log "INFO" "恢复后验证成功完成，未发现严重不一致。"
        # 清理空的 diff 文件
        [ -f "${RESTORE_LOG_FILE}.diff" ] && [ ! -s "${RESTORE_LOG_FILE}.diff" ] && rm -f "${RESTORE_LOG_FILE}.diff"
        return 0
    fi
}


# 选择备份源
# 返回选定的备份目录路径，如果是压缩包则解压到临时目录并返回该路径
select_backup_source() {
    log "INFO" "查找可用的备份源..."
    local backups=()
    local backup_options=()
    local i=1

    # --- Find Directories ---
    local find_dirs_cmd="find \"$BACKUP_ROOT\" -maxdepth 1 -type d -name \"????-??-??\" -print0" # Corrected pattern
    log "DEBUG" "Running find for directories: $find_dirs_cmd"
    local dir_results=()
    # Use mapfile if available (Bash 4+) for robustness, otherwise fallback
    if command -v mapfile &> /dev/null; then
        mapfile -d $'\0' dir_results < <(eval $find_dirs_cmd)
    else
        log "DEBUG" "mapfile not found, using alternative find processing."
        # Alternative: Store find output in a variable (less safe with special chars but might work)
        local find_output_dirs # Renamed variable
        find_output_dirs=$(eval $find_dirs_cmd)
        # Process the output (assuming null separation worked)
        local old_ifs=$IFS
        IFS=$'\0'
        for dir in $find_output_dirs; do # Use renamed variable
            # Skip empty strings that might result from splitting
            [ -z "$dir" ] && continue
            dir_results+=("$dir")
        done
        IFS=$old_ifs
    fi
    log "DEBUG" "Found ${#dir_results[@]} potential directories."

    for dir in "${dir_results[@]}"; do
        # Skip empty results if any
        [ -z "$dir" ] && continue
        log "DEBUG" "Processing potential directory: $dir"
        local bname=$(basename "$dir")
        log "DEBUG" "Basename: $bname"
        # Use a more specific regex to avoid matching other date-like dirs if any
        if [[ "$bname" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
            log "DEBUG" "Directory matched pattern: $bname"
            backups+=("$dir")
            backup_options+=("$i) $bname (目录)")
            i=$((i + 1)) # Increment only when a match is found
        else
             log "DEBUG" "Directory did not match pattern: $bname"
        fi
    done

    # --- Find Files ---
    local find_files_cmd="find \"$BACKUP_ROOT\" -maxdepth 1 -type f -name \"????-??-??_backup.tar.*\" -print0" # Corrected pattern and type
    log "DEBUG" "Running find for files: $find_files_cmd"
    local file_results=()
    if command -v mapfile &> /dev/null; then
        mapfile -d $'\0' file_results < <(eval $find_files_cmd)
    else
         log "DEBUG" "mapfile not found, using alternative find processing."
        local find_output_files # Renamed variable
        find_output_files=$(eval $find_files_cmd)
        local old_ifs=$IFS
        IFS=$'\0'
        for file in $find_output_files; do # Use renamed variable
             [ -z "$file" ] && continue
            file_results+=("$file")
        done
        IFS=$old_ifs
    fi
     log "DEBUG" "Found ${#file_results[@]} potential files."

    for file in "${file_results[@]}"; do
        [ -z "$file" ] && continue
        log "DEBUG" "Processing potential file: $file"
        local bname=$(basename "$file")
        log "DEBUG" "Basename: $bname"
        # Use a more specific regex
        if [[ "$bname" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}_backup\.tar\.(gz|bz2|xz)$ ]]; then
            log "DEBUG" "File matched pattern: $bname"
            backups+=("$file")
            backup_options+=("$i) $bname (压缩包)")
            i=$((i + 1)) # Increment only when a match is found
        else
             log "DEBUG" "File did not match pattern: $bname"
        fi
    done

    log "DEBUG" "Finished searching. Found ${#backups[@]} total backup sources."
    log "DEBUG" "Backup options array size: ${#backup_options[@]}"

    if [ ${#backups[@]} -eq 0 ]; then
        log "FATAL" "在 $BACKUP_ROOT 中未找到任何有效的备份源。"
        exit 1
    fi

    # --- Print options ---
    echo -e "${GREEN}找到以下备份源:${NC}" # 直接输出到屏幕
    if [ ${#backup_options[@]} -gt 0 ]; then
        # Print to screen using a loop for better compatibility
        for option in "${backup_options[@]}"; do
            echo "$option"
        done
        # Log to file
        printf "%s\n" "${backup_options[@]}" >> "$RESTORE_LOG_FILE"
        log "INFO" "已列出 ${#backup_options[@]} 个可用备份源。"
    else
         log "ERROR" "Backup options array is empty, cannot print list."
    fi

    # Add a longer delay before prompting for input
    sleep 0.5

    # --- Get user choice ---
    local choice
    while true; do
        # Explicitly read from /dev/tty
        read -p "请选择要恢复的备份源编号: " choice < /dev/tty
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#backups[@]} ]; then
            local selected_source="${backups[$((choice-1))]}"
            log "INFO" "已选择备份源: $(basename "$selected_source")"

            # 如果是压缩文件，解压到临时目录
            if [ -f "$selected_source" ]; then
                local temp_extract_dir="${BACKUP_ROOT}/temp_restore_extract_$(date +%s)"
                log "INFO" "检测到压缩备份，将解压到临时目录: $temp_extract_dir"
                mkdir -p "$temp_extract_dir"

                local decompress_cmd=""
                local ext="${selected_source##*.}"
                local tar_opts=""

                case "$ext" in
                    "gz") tar_opts="-xzf" ;;
                    "bz2") tar_opts="-xjf" ;;
                    "xz") tar_opts="-xJf" ;;
                    *) log "FATAL" "不支持的压缩格式: $ext"; rm -rf "$temp_extract_dir"; exit 1 ;;
                esac

                log "INFO" "正在解压 $selected_source ..."
                if tar "$tar_opts" "$selected_source" -C "$temp_extract_dir" >> "$RESTORE_LOG_FILE" 2>&1; then
                    log "INFO" "解压成功。"
                    # 假设解压后根目录是日期名
                    local extracted_dir_name=$(basename "$selected_source" | cut -d'_' -f1)
                    local final_source_dir="$temp_extract_dir/$extracted_dir_name"
                    if [ -d "$final_source_dir" ]; then
                        # 将临时目录路径添加到清理列表
                        CLEANUP_DIRS+=("$temp_extract_dir")
                        echo "$final_source_dir" # 返回解压后的目录路径
                        return 0
                    else
                        log "FATAL" "解压后未找到预期的目录 '$extracted_dir_name' in '$temp_extract_dir'"
                        rm -rf "$temp_extract_dir"
                        exit 1
                    fi
                else
                    log "FATAL" "解压失败，请检查日志: $RESTORE_LOG_FILE"
                    rm -rf "$temp_extract_dir"
                    exit 1
                fi
            else
                # 如果是目录，直接返回路径
                echo "$selected_source"
                return 0
            fi
        else
            log "ERROR" "无效的选择，请输入 1 到 ${#backups[@]} 之间的数字。"
        fi
    done
}

# 全局变量存储需要清理的临时目录
CLEANUP_DIRS=()

# 清理临时文件和目录
cleanup() {
    log "INFO" "执行清理操作..."
    if [ ${#CLEANUP_DIRS[@]} -gt 0 ]; then
        for dir in "${CLEANUP_DIRS[@]}"; do
            if [ -d "$dir" ]; then
                log "INFO" "删除临时目录: $dir"
                rm -rf "$dir"
            fi
        done
    else
        log "INFO" "没有需要清理的临时目录。"
    fi
}

# 主函数
main() {
    log "INFO" "开始 Arch Linux 恢复脚本"

    # 检查是否为 root 用户
    if [ "$(id -u)" -ne 0 ]; then
        log "WARN" "脚本未以 root 用户运行，恢复系统文件可能失败"
        log "WARN" "建议使用 sudo 运行此脚本以获得完整的恢复权限"
        # 可以选择强制退出或让用户确认
        read -p "建议使用 sudo 运行，是否继续? (y/N): " confirm_non_root < /dev/tty # Read from tty
        if [[ ! "$confirm_non_root" =~ ^[Yy]$ ]]; then
            log "FATAL" "用户选择中止操作。"
            exit 1
        fi
    fi

    # 加载配置
    load_config

    # 检查依赖
    check_dependencies

    log "INFO" "恢复脚本初始化完成。"
    log "INFO" "日志文件: ${RESTORE_LOG_FILE}"

    # 设置退出时清理临时文件的陷阱
    trap cleanup EXIT

    # --- 调用恢复流程函数 ---
    local selected_backup_dir
    selected_backup_dir=$(select_backup_source) || exit 1 # 选择备份源

    if [ -z "$selected_backup_dir" ] || [ ! -d "$selected_backup_dir" ]; then
        log "FATAL" "未能确定有效的备份源目录。"
        exit 1
    fi
    log "INFO" "将从以下目录恢复: $selected_backup_dir"

    select_restore_options "$selected_backup_dir" || exit 1 # 选择恢复选项

    if [ -z "$SELECTED_COMPONENTS" ]; then
        log "FATAL" "未选择任何恢复组件。"
        exit 1
    fi

    execute_restore "$selected_backup_dir" "$SELECTED_COMPONENTS" "$DO_BACKUP_BEFORE_RESTORE"
    local restore_status=$? # 获取恢复操作的退出状态

    # 如果恢复成功，执行验证
    local verify_status=0
    if [ $restore_status -eq 0 ]; then
        verify_restore "$selected_backup_dir" "$SELECTED_COMPONENTS"
        verify_status=$?
    else
         log "WARN" "由于恢复过程中出现错误，跳过恢复后验证。"
    fi

    # 综合报告最终状态
    if [ $restore_status -eq 0 ] && [ $verify_status -eq 0 ]; then
        log "INFO" "恢复脚本成功执行完毕，并通过验证。"
    elif [ $restore_status -eq 0 ]; then
         log "WARN" "恢复脚本执行完毕，但验证过程中发现问题。"
    else
        log "ERROR" "恢复脚本执行完毕，但恢复过程中存在错误。"
    fi
    exit $restore_status
}

# 执行主函数
main

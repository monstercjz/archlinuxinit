#!/bin/bash

#############################################################
# 备份加密实现脚本
#
# 功能:
#   对备份文件进行加密，提高数据安全性
#   支持多种加密方式：GPG和OpenSSL
#   可以对整个备份目录或单个文件进行加密
#
# 参数:
#   $1 - 要加密的文件或目录路径
#   $2 - 加密后的输出路径
#   $3 - 加密密码或密钥文件路径
#   $4 - 加密方式 (gpg 或 openssl，默认为 openssl)
#
# 返回值:
#   0 - 加密成功
#   1 - 加密失败
#
# 依赖项:
#   - 外部命令: openssl, gpg, tar (用于目录加密)
#   - 核心脚本:
#     - core/loggings.sh (提供 log 函数)
#
# 使用示例:
#   $ encrypt_backup "/var/backups/2023-01-01" "/var/backups/2023-01-01.enc" "my_secure_password" "openssl"
#
#############################################################

# 加密备份主函数
encrypt_backup() {
    local src="$1"
    local dest="$2"
    local password="$3"
    local method="${4:-openssl}" # 默认使用 openssl
    local success=false
    local temp_dir=""
    
    # 检查参数
    if [ -z "$src" ]; then
        log "ERROR" "未提供源路径"
        return 1
    fi
    
    if [ -z "$dest" ]; then
        log "ERROR" "未提供目标路径"
        return 1
    fi
    
    if [ -z "$password" ]; then
        log "ERROR" "未提供加密密码或密钥"
        return 1
    fi
    
    # 检查源路径是否存在
    if [ ! -e "$src" ]; then
        log "ERROR" "源路径不存在: $src"
        return 1
    fi
    
    # 检查加密工具是否可用
    case "$method" in
        gpg)
            if ! command -v gpg > /dev/null 2>&1; then
                log "ERROR" "命令 'gpg' 未找到，请安装它 (例如: sudo pacman -S gnupg)"
                return 1
            fi
            ;;
        openssl)
            if ! command -v openssl > /dev/null 2>&1; then
                log "ERROR" "命令 'openssl' 未找到，请安装它 (例如: sudo pacman -S openssl)"
                return 1
            fi
            ;;
        *)
            log "ERROR" "不支持的加密方式: $method，请使用 'gpg' 或 'openssl'"
            return 1
            ;;
    esac
    
    # 如果源是目录，需要先打包
    if [ -d "$src" ]; then
        log "INFO" "源是目录，将先打包再加密"
        
        # 检查 tar 命令是否可用
        if ! command -v tar > /dev/null 2>&1; then
            log "ERROR" "命令 'tar' 未找到，请安装它 (例如: sudo pacman -S tar)"
            return 1
        fi
        
        # 创建临时目录用于存放打包文件
        temp_dir="$(mktemp -d)"
        local tar_file="$temp_dir/$(basename "$src").tar"
        
        log "INFO" "打包目录: $src -> $tar_file"
        if ! tar -cf "$tar_file" -C "$(dirname "$src")" "$(basename "$src")"; then
            log "ERROR" "打包目录失败: $src"
            rm -rf "$temp_dir"
            return 1
        fi
        
        # 更新源路径为打包后的文件
        src="$tar_file"
    fi
    
    # 执行加密
    log "INFO" "开始加密: $src -> $dest (使用 $method)"
    
    case "$method" in
        gpg)
            # 使用 GPG 加密
            if echo "$password" | gpg --batch --yes --passphrase-fd 0 -c -o "$dest" "$src"; then
                success=true
                log "INFO" "GPG 加密成功完成"
            else
                log "ERROR" "GPG 加密失败"
            fi
            ;;
        openssl)
            # 使用 OpenSSL 加密 (AES-256-CBC)
            if openssl enc -aes-256-cbc -salt -pbkdf2 -in "$src" -out "$dest" -pass "pass:$password"; then
                success=true
                log "INFO" "OpenSSL 加密成功完成"
            else
                log "ERROR" "OpenSSL 加密失败"
            fi
            ;;
    esac
    
    # 清理临时文件
    if [ -n "$temp_dir" ]; then
        log "DEBUG" "清理临时目录: $temp_dir"
        rm -rf "$temp_dir"
    fi
    
    # 返回结果
    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

# 解密备份函数
decrypt_backup() {
    local src="$1"
    local dest="$2"
    local password="$3"
    local method="${4:-openssl}" # 默认使用 openssl
    local success=false
    
    # 检查参数
    if [ -z "$src" ]; then
        log "ERROR" "未提供源加密文件路径"
        return 1
    fi
    
    if [ -z "$dest" ]; then
        log "ERROR" "未提供解密后的输出路径"
        return 1
    fi
    
    if [ -z "$password" ]; then
        log "ERROR" "未提供解密密码或密钥"
        return 1
    fi
    
    # 检查源文件是否存在
    if [ ! -f "$src" ]; then
        log "ERROR" "源加密文件不存在: $src"
        return 1
    fi
    
    # 检查解密工具是否可用
    case "$method" in
        gpg)
            if ! command -v gpg > /dev/null 2>&1; then
                log "ERROR" "命令 'gpg' 未找到，请安装它 (例如: sudo pacman -S gnupg)"
                return 1
            fi
            ;;
        openssl)
            if ! command -v openssl > /dev/null 2>&1; then
                log "ERROR" "命令 'openssl' 未找到，请安装它 (例如: sudo pacman -S openssl)"
                return 1
            fi
            ;;
        *)
            log "ERROR" "不支持的解密方式: $method，请使用 'gpg' 或 'openssl'"
            return 1
            ;;
    esac
    
    # 执行解密
    log "INFO" "开始解密: $src -> $dest (使用 $method)"
    
    case "$method" in
        gpg)
            # 使用 GPG 解密
            if echo "$password" | gpg --batch --yes --passphrase-fd 0 -d -o "$dest" "$src"; then
                success=true
                log "INFO" "GPG 解密成功完成"
            else
                log "ERROR" "GPG 解密失败"
            fi
            ;;
        openssl)
            # 使用 OpenSSL 解密
            if openssl enc -d -aes-256-cbc -pbkdf2 -in "$src" -out "$dest" -pass "pass:$password"; then
                success=true
                log "INFO" "OpenSSL 解密成功完成"
            else
                log "ERROR" "OpenSSL 解密失败"
            fi
            ;;
    esac
    
    # 如果解密成功且文件是 tar 归档，可以选择解压
    if [ "$success" = true ] && [[ "$dest" == *.tar ]]; then
        log "INFO" "检测到 tar 归档文件，是否需要解压？(y/n)"
        read -r answer
        if [[ "$answer" == [Yy]* ]]; then
            local extract_dir="$(dirname "$dest")/$(basename "$dest" .tar)"
            log "INFO" "解压归档: $dest -> $extract_dir"
            mkdir -p "$extract_dir"
            if tar -xf "$dest" -C "$extract_dir"; then
                log "INFO" "解压成功完成"
            else
                log "ERROR" "解压失败"
            fi
        fi
    fi
    
    # 返回结果
    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

# 如果直接运行此脚本（非被其他脚本source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # 获取脚本所在目录
    parent_dir="$(dirname "${BASH_SOURCE[0]}")/.."

    # 加载配置和日志脚本
    config_script="$parent_dir/core/config.sh"
    load_config_script="$parent_dir/core/load_config.sh"
    logging_script="$parent_dir/core/loggings.sh"

    _libs_loaded_encrypt=true
    # 加载依赖脚本
    if [ -f "$logging_script" ]; then . "$logging_script"; else echo "错误：无法加载 $logging_script" >&2; _libs_loaded_encrypt=false; fi
    if [ -f "$config_script" ]; then . "$config_script"; else echo "错误：无法加载 $config_script" >&2; _libs_loaded_encrypt=false; fi
    if [ -f "$load_config_script" ]; then . "$load_config_script"; else echo "错误：无法加载 $load_config_script" >&2; _libs_loaded_encrypt=false; fi

    if ! $_libs_loaded_encrypt; then
        exit 1 # 依赖加载失败
    fi

    # 加载配置文件并初始化日志
    load_config
    
    # 检查操作类型
    if [ "$1" == "encrypt" ]; then
        shift
        encrypt_backup "$1" "$2" "$3" "$4"
        exit $?
    elif [ "$1" == "decrypt" ]; then
        shift
        decrypt_backup "$1" "$2" "$3" "$4"
        exit $?
    else
        log "ERROR" "未知操作类型，请使用 'encrypt' 或 'decrypt'"
        echo "用法: $0 encrypt|decrypt <源路径> <目标路径> <密码> [加密方式]"
        exit 1
    fi
fi
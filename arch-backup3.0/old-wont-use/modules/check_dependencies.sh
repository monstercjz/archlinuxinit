# 检查必要的命令
# 功能：检查脚本运行所需的所有依赖项是否已安装
# 参数：无
# 返回值：
#   0 - 所有必要依赖都已安装
#   1 - 有必要依赖缺失
# 错误处理：
#   记录所有缺失的依赖项，但不会立即退出脚本
#   返回状态码表示是否有必要依赖缺失
# 检查内容：
#   - 核心依赖（rsync, pacman等）
#   - 压缩工具依赖（根据配置的压缩方法）
#   - 进度显示工具
#   - 并行处理工具（如果启用并行备份）
#   - 网络工具（如果启用网络备份）
#   - 加密工具（如果启用加密备份）
#   - 恢复测试工具（如果启用恢复测试）
# 使用示例：
#   check_dependencies || exit 1
check_dependencies() {
    log "INFO" "检查依赖..."
    local missing_deps=0
    local optional_missing=0
    
    # 核心依赖检查 - 这些是必须的
    log "INFO" "检查核心依赖..."
    local core_deps=("rsync" "pacman" "journalctl" "tar" "find" "grep" "awk" "sed")
    local core_desc=("远程同步工具" "包管理器" "日志查看工具" "归档工具" "文件查找工具" "文本搜索工具" "文本处理工具" "流编辑器")
    
    for i in "${!core_deps[@]}"; do
        if ! command -v "${core_deps[$i]}" >/dev/null 2>&1; then
            log "ERROR" "核心依赖 ${core_deps[$i]} (${core_desc[$i]}) 未安装"
            log "INFO" "请使用以下命令安装: sudo pacman -S ${core_deps[$i]}"
            missing_deps=$((missing_deps + 1))
        else
            log "INFO" "核心依赖 ${core_deps[$i]} 已安装"
            
            # 对特定工具进行版本检查
            case "${core_deps[$i]}" in
                "rsync")
                    check_command_version "rsync" "3.1.0"
                    ;;
                "tar")
                    check_command_version "tar" "1.30"
                    ;;
            esac
        fi
    done
    
    # 压缩工具依赖检查
    log "INFO" "检查压缩工具依赖..."
    local compression_tools=("gzip" "bzip2" "xz")
    local compression_desc=("gzip压缩工具" "bzip2压缩工具" "xz压缩工具")
    
    for i in "${!compression_tools[@]}"; do
        if ! command -v "${compression_tools[$i]}" >/dev/null 2>&1; then
            if [ "$COMPRESS_BACKUP" == "true" ] && [ "$COMPRESS_METHOD" == "${compression_tools[$i]}" ]; then
                log "ERROR" "所选压缩工具 ${compression_tools[$i]} (${compression_desc[$i]}) 未安装"
                log "INFO" "请使用以下命令安装: sudo pacman -S ${compression_tools[$i]}"
                missing_deps=$((missing_deps + 1))
            else
                log "WARN" "压缩工具 ${compression_tools[$i]} 未安装，如需使用该压缩方法请先安装"
                optional_missing=$((optional_missing + 1))
            fi
        else
            if [ "$COMPRESS_BACKUP" == "true" ] && [ "$COMPRESS_METHOD" == "${compression_tools[$i]}" ]; then
                log "INFO" "所选压缩工具 ${compression_tools[$i]} 已安装"
            else
                log "DEBUG" "压缩工具 ${compression_tools[$i]} 已安装"
            fi
        fi
    done
    
    # 进度显示工具检查
    log "INFO" "检查进度显示工具..."
    if command -v "pv" >/dev/null 2>&1; then
        log "INFO" "检测到 pv 工具，将启用备份进度显示"
        USE_PROGRESS_BAR=true
    else
        log "WARN" "未检测到 pv 工具，备份进度显示将使用 rsync 内置的进度功能"
        log "INFO" "提示：安装 pv 工具可获得更好的进度显示体验 (sudo pacman -S pv)"
        USE_PROGRESS_BAR=false
        optional_missing=$((optional_missing + 1))
    fi
    
    # 并行处理工具检查
    if [ "$PARALLEL_BACKUP" == "true" ]; then
        log "INFO" "检查并行处理工具..."
        if command -v "parallel" >/dev/null 2>&1; then
            log "INFO" "检测到 GNU Parallel 工具，将启用并行备份功能"
            HAS_PARALLEL=true
            # 检查 GNU Parallel 版本
            check_command_version "parallel" "20180222"
        else
            log "WARN" "未检测到 GNU Parallel 工具，将使用内置的后台进程实现并行备份"
            log "INFO" "提示：安装 GNU Parallel 工具可获得更好的并行备份体验 (sudo pacman -S parallel)"
            HAS_PARALLEL=false
            optional_missing=$((optional_missing + 1))
        fi
    fi
    
    # 网络工具检查（如果配置了网络备份）
    if [ "${NETWORK_BACKUP:-false}" == "true" ]; then
        log "INFO" "检查网络备份工具..."
        local network_tools=("ssh" "scp" "curl")
        local network_desc=("SSH客户端" "安全复制工具" "网络传输工具")
        
        for i in "${!network_tools[@]}"; do
            if ! command -v "${network_tools[$i]}" >/dev/null 2>&1; then
                log "ERROR" "网络工具 ${network_tools[$i]} (${network_desc[$i]}) 未安装，但网络备份功能已启用"
                log "INFO" "请使用以下命令安装: sudo pacman -S ${network_tools[$i]}"
                missing_deps=$((missing_deps + 1))
            else
                log "INFO" "网络工具 ${network_tools[$i]} 已安装"
            fi
        done
    fi
    
    # 加密工具检查（如果配置了加密备份）
    if [ "${ENCRYPT_BACKUP:-false}" == "true" ]; then
        log "INFO" "检查加密工具..."
        local crypto_tools=("gpg" "openssl")
        local crypto_desc=("GnuPG加密工具" "OpenSSL加密库")
        
        for i in "${!crypto_tools[@]}"; do
            if ! command -v "${crypto_tools[$i]}" >/dev/null 2>&1; then
                log "ERROR" "加密工具 ${crypto_tools[$i]} (${crypto_desc[$i]}) 未安装，但加密备份功能已启用"
                log "INFO" "请使用以下命令安装: sudo pacman -S ${crypto_tools[$i]}"
                missing_deps=$((missing_deps + 1))
            else
                log "INFO" "加密工具 ${crypto_tools[$i]} 已安装"
                
                # 对特定加密工具进行版本检查
                case "${crypto_tools[$i]}" in
                    "gpg")
                        check_command_version "gpg" "2.2.0"
                        ;;
                    "openssl")
                        check_command_version "openssl" "1.1.0" "version" "[0-9]+(\.[0-9]+)+[a-z]*"
                        ;;
                esac
            fi
        done
    fi
    
    # 恢复测试工具检查（如果配置了恢复测试）
    if [ "${TEST_RESTORE:-false}" == "true" ]; then
        log "INFO" "检查恢复测试工具..."
        local test_tools=("diff" "cmp")
        local test_desc=("文件比较工具" "字节比较工具")
        
        for i in "${!test_tools[@]}"; do
            if ! command -v "${test_tools[$i]}" >/dev/null 2>&1; then
                log "ERROR" "测试工具 ${test_tools[$i]} (${test_desc[$i]}) 未安装，但恢复测试功能已启用"
                log "INFO" "请使用以下命令安装: sudo pacman -S ${test_tools[$i]}"
                missing_deps=$((missing_deps + 1))
            else
                log "INFO" "测试工具 ${test_tools[$i]} 已安装"
            fi
        done
    fi
    
    # 依赖检查结果汇总
    if [ $missing_deps -gt 0 ]; then
        log "ERROR" "检测到 $missing_deps 个必要依赖缺失，请安装后再运行脚本"
        return 1
    else
        if [ $optional_missing -gt 0 ]; then
            log "WARN" "检测到 $optional_missing 个可选依赖缺失，某些功能可能受限"
        fi
        log "INFO" "所有必要依赖检查通过"
        return 0
    fi
}
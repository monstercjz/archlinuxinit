#!/bin/bash

#############################################################
# 校验备份项的校验和 (带重试和开关)
#
# 功能:
#   - 检查 VERIFY_CHECKSUM 开关。
#   - 计算正确的校验目标目录 (考虑 rsync -R)。
#   - 调用 verify_checksum_manifest (来自 check_file_integrity.sh) 并进行重试。
#
# 参数:
#   $1 - 源路径 (src)
#   $2 - 目标基础目录 (dest_base)
#   $3 - 清单文件路径 (manifest_file)
#
# 返回值:
#   0 - 校验成功或根据配置跳过
#   1 - 校验失败 (达到最大重试次数)
#
# 依赖:
#   - core/loggings.sh (log 函数)
#   - file-check/check_file_integrity.sh (verify_checksum_manifest 函数)
#   - 全局变量: VERIFY_CHECKSUM
#############################################################

verify_backup_checksum() {
    local src="$1"
    local dest_base="$2"
    local manifest_file="$3"

    # 检查依赖函数是否存在
    if ! command -v verify_checksum_manifest &>/dev/null; then
        log "ERROR" "依赖函数 'verify_checksum_manifest' 未找到 (可能未加载 check_file_integrity.sh)"
        return 1
    fi

    # --- 根据开关执行校验和验证 ---
    if [[ "$VERIFY_CHECKSUM" != "true" ]]; then
        log_info "根据配置跳过校验和验证: $src"
        return 0 # 跳过视为成功
    fi

    # --- 确定正确的验证目录 ---
    # 计算由 rsync -R 创建的相对路径
    local relative_path="${src#/}"
    # 确定校验时需要进入的目录
    local verify_target_dir
    if [ -d "$src" ]; then
        # 如果源是目录，校验目录是目标基础 + 相对路径
        verify_target_dir="$dest_base/$relative_path"
    elif [ -f "$src" ]; then
        # 如果源是文件，校验目录是目标基础 + 相对路径的父目录
        verify_target_dir="$dest_base/$(dirname "$relative_path")"
        # 处理根目录下的文件，dirname 可能返回 .
        if [[ "$verify_target_dir" == "$dest_base/." ]]; then
            verify_target_dir="$dest_base"
        fi
    else
        # 源既不是文件也不是目录
        log_error "无法确定 '$src' 的类型以计算校验目录。"
        return 1
    fi
    # 确保路径没有双斜杠
    verify_target_dir=$(echo "$verify_target_dir" | sed 's|//|/|g')


    # --- 执行校验和验证，带重试机制 ---
    local verify_success=false
    local verify_retry_count=5
    local verify_retry_delay=5
    for ((v_try=1; v_try<=verify_retry_count; v_try++)); do
        log_info "调用 verify_checksum_manifest \"$manifest_file\" \"$verify_target_dir\" (尝试 $v_try/$verify_retry_count)"
        if verify_checksum_manifest "$manifest_file" "$verify_target_dir"; then
            verify_success=true
            break # 验证成功，跳出重试循环
        else
            log_warn "校验和验证失败 (尝试 $v_try/$verify_retry_count): $src (清单: $manifest_file, 验证目录: $verify_target_dir)"
            if [ $v_try -lt $verify_retry_count ]; then
                log_info "将在 $verify_retry_delay 秒后重试校验..."
                sleep $verify_retry_delay
            fi
        fi
    done

    if [ "$verify_success" = true ]; then
        log_info "校验和验证成功: $src"
        return 0
    else
        log_error "校验和验证失败，已达到最大重试次数: $src"
        return 1
    fi
}

# --- 直接执行块 (用于测试或独立调用) ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    echo "错误：此脚本应被 source，而不是直接执行。" >&2
    echo "用法: source core/verify_backup_checksum.sh" >&2
    echo "       verify_backup_checksum <source_path> <dest_base> <manifest_file>" >&2
    exit 1
fi
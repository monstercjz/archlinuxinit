# 创建备份目录
# 功能：创建备份所需的目录结构
# 参数：无
# 返回值：无
# 错误处理：
#   如果目录创建失败，会记录在日志中，但不会中断脚本执行
# 创建的目录：
#   - 根据配置文件中的BACKUP_DIRS变量创建相应的子目录
#   - 创建日志文件所在的目录
# 使用示例：
#   create_backup_dirs
create_backup_dirs() {
    if check_and_create_directory "${BACKUP_DIR}"; then
        log "INFO" "备份文件夹目录 ${BACKUP_DIR} 检查完毕：正常"
    fi
    dir_conts=0
    # 使用配置文件中定义的备份目录结构
    for dir in ${BACKUP_DIRS}; do
        if check_and_create_directory "${BACKUP_DIR}/${dir}"; then
            dir_conts=$((dir_conts + 1))
            log "INFO" "第 ${dir_conts} 个备份文件夹 ${BACKUP_DIR}/${dir} 检查完毕：正常"
        fi
    done
    # 在循环结束后返回计数器的值
    # echo $dir_conts
    # 检查 dir_conts 是否等于 5
    if [ "$dir_conts" -ne 5 ]; then
        log "ERROR" "创建的备份文件夹数量不正确，预期 5 个，实际 $dir_conts 个"
        return 1
    else
        log "INFO" "一共成功创建了所有 5 个备份文件夹"
        return 0
    fi
}
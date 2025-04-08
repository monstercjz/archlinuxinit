# 流程
1. 检查备份项目的大小数量:calculate_size_and_count.sh items
2. 检查磁盘空间:check_disk_space.sh 
3. 备份项目:rsync_backup.sh src dest exclude
4. 验证备份之后的数量和大小
5. 备份完成

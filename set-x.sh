#!/bin/bash


# 设置目标目录

TARGET_DIR="archlinuxinit"


# 递归地为所有 .sh 文件赋予执行权限

find "$TARGET_DIR" -type f -name "*.sh" -exec chmod +x {} \;


echo "已为 $TARGET_DIR 目录下的所有 .sh 文件赋予执行权限"

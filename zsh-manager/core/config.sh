#!/bin/bash

# 全局配置


# 颜色定义

RED='\033[0;31m'; GREEN='\033[0;32m'

YELLOW='\033[0;33m'; BLUE='\033[0;34m'

CYAN='\033[0;36m'; NC='\033[0m'


# 路径配置

ZSHRC="$HOME/.zshrc"

P10K_CONFIG="$HOME/.p10k.zsh"

BACKUP_DIR="$HOME/.zsh_manager_backups"


# 模块操作类型

declare -A OPERATIONS=(

    ["install"]="安装"

    ["uninstall"]="卸载"

)

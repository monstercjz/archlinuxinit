#!/bin/bash

# 获取脚本所在目录的绝对路径
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SOURCE_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

source "$SOURCE_DIR/core/config.sh"


confirm_action() {

    local operation=$1

    local target=$2

    echo -ne "${YELLOW}确定要${OPERATIONS[$operation]} $target 吗？ [y/N] ${NC}"

    read -n 1 -r

    echo

    [[ $REPLY =~ ^[Yy]$ ]]

}


show_status() {

    local status=$1

    local message=$2

    case $status in

        "success") echo -e "${GREEN}✓ ${message}${NC}" ;;

        "error") echo -e "${RED}✗ ${message}${NC}" >&2 ;;

        "info") echo -e "${BLUE}➤ ${message}${NC}" ;;

    esac

}


backup_files() {

    mkdir -p "$BACKUP_DIR"

    cp -v "$ZSHRC" "$BACKUP_DIR" 2>/dev/null

    cp -v "$P10K_CONFIG" "$BACKUP_DIR" 2>/dev/null

}

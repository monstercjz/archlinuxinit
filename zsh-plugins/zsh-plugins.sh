#!/bin/bash

# 脚本选项：
# -e: 如果命令以非零状态退出，则立即退出。
# -o pipefail: 如果管道中的任何命令失败，则整个管道的退出状态为非零。
set -e
set -o pipefail

# --- 定义脚本目录和模块路径 ---
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
MODULES_DIR="$SCRIPT_DIR/modules"

# --- 加载模块 ---
# 首先加载工具函数，因为其他模块可能依赖它
UTILS_PATH="$MODULES_DIR/utils.sh"
if [ ! -f "$UTILS_PATH" ]; then
    echo "错误：核心工具模块 utils.sh 未找到！路径: $UTILS_PATH"
    exit 1
fi
# shellcheck source=./modules/utils.sh
source "$UTILS_PATH"

# 加载其他模块
MODULES=("check.sh" "install.sh" "fonts.sh" "config.sh" "post_install.sh")
for module in "${MODULES[@]}"; do
    MODULE_PATH="$MODULES_DIR/$module"
    if [ ! -f "$MODULE_PATH" ]; then
        log ERROR "模块 $module 未找到！路径: $MODULE_PATH"
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$MODULE_PATH"
done

# --- 主函数 ---
main() {
    # 定义总步骤数
    export TOTAL_STEPS=4
    export CURRENT_STEP=0 # 初始化

    log STEP "欢迎使用 Zsh 及插件增强安装脚本"
    echo "========================================"
    echo "本脚本将尝试安装和配置以下组件:"
    echo "  - Zsh (Shell)"
    echo "  - Oh My Zsh (Zsh 配置框架)"
    echo "  - fzf (命令行模糊查找器)"
    echo "  - bat (带语法高亮的 cat 替代品)"
    echo "  - eza (现代化的 ls 替代品)"
    echo "  - zsh-syntax-highlighting (命令语法高亮插件)"
    echo "  - zsh-autosuggestions (命令历史建议插件)"
    echo "  - fzf-tab (使用 fzf 的 Tab 补全插件)"
    echo "  - Powerlevel10k (强大的 Zsh 主题)"
    echo "  - MesloLGS NF (Powerlevel10k 推荐字体)"
    echo "========================================"
    echo ""

    # 捕获中断信号
    trap 'log ERROR "脚本被用户中断。"; exit 1' SIGINT SIGTERM

    # 1. 运行检查和依赖项处理 (check.sh)
    export CURRENT_STEP=1
    # run_checks 会进行检查、用户交互并导出必要的环境变量
    if ! run_checks; then
         # run_checks 内部应该已经处理了用户取消或依赖问题的退出逻辑
         # 如果它返回非零，通常意味着用户选择忽略依赖问题继续
         log WARN "检查阶段未完全成功，但用户选择继续。"
    fi

    # 检查 check.sh 是否设置了跳过安装的标志
    if [[ "$SKIP_INSTALLATION" == "true" ]]; then
        log INFO "[STEP ${CURRENT_STEP}/${TOTAL_STEPS}] 根据用户选择，跳过安装步骤。"
        # 如果跳过安装，我们仍然需要增加步骤计数器，或者调整总步骤数
        # 为了简单起见，我们继续计数，但配置步骤变为第 3 步
    else
        # 2. 运行安装 (install.sh)
        export CURRENT_STEP=2
        # run_installation 使用由 run_checks 导出的环境变量
        if ! run_installation; then
            log ERROR "安装过程中发生错误。请检查日志。"
            # 即使安装失败，也尝试进行配置和验证，因为部分可能已安装
            # exit 1 # 或者选择在这里退出
        fi
    fi

    # 3. 运行配置 (config.sh)
    export CURRENT_STEP=3
    # run_configuration 使用由 run_checks 导出的环境变量 (主要是 CHECK_RESULTS_EXPORT)
    if ! run_configuration; then
        log ERROR "配置过程中发生错误。请检查日志。"
        # 配置失败也继续进行最终检查和指导
    fi

    # 4. 运行安装后检查和提供指导 (post_install.sh)
    export CURRENT_STEP=4
    if ! run_post_install_checks; then
         log WARN "安装后验证发现一些问题。"
    fi

    # 完成所有步骤后，可以清除步骤计数器或记录完成信息
    unset CURRENT_STEP
    unset TOTAL_STEPS
    log INFO "所有步骤执行完毕！" # 使用 INFO 级别标记结束
    echo "========================================"
    echo "请仔细阅读上面的 '后续步骤和建议' 部分以完成最终设置。"
    echo "如果您遇到任何问题，请检查脚本输出的日志信息。"
    echo "========================================"

    # 提示用户切换到 Zsh (如果当前不是 Zsh)
    if [ -n "$SHELL" ] && [ ! "$(basename "$SHELL")" == "zsh" ]; then
        if command_exists zsh; then
            log INFO "您的默认 Shell 不是 Zsh。"
            if prompt_confirm "是否现在尝试将 Zsh 设置为默认 Shell (需要 sudo 权限)？"; then
                 if command_exists chsh; then
                     log INFO "尝试使用 'chsh -s $(command -v zsh)' 更改默认 Shell..."
                     if run_sudo_command chsh -s "$(command -v zsh)" "$(whoami)"; then
                         log INFO "默认 Shell 已更改为 Zsh。您需要重新登录才能生效。"
                     else
                         log ERROR "更改默认 Shell 失败。请尝试手动运行 'sudo chsh -s $(command -v zsh) $(whoami)'。"
                     fi
                 else
                     log WARN "未找到 'chsh' 命令，无法自动更改默认 Shell。"
                     log INFO "请参考您的系统文档手动更改默认 Shell 为: $(command -v zsh)"
                 fi
            else
                 log INFO "您可以稍后手动更改默认 Shell。"
                 log INFO "Zsh 的路径是: $(command -v zsh)"
            fi
        fi
    fi

}

# --- 执行主函数 ---
main "$@"

exit 0

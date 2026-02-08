#!/usr/bin/env bash
#
# Script Name: vim-setup
# Description: XServer向け vim 環境セットアップスクリプト
# Usage: bash <(curl -sL https://raw.githubusercontent.com/opipi406/linux-setup-tools/main/vim/install.sh)
#
# Requirements: Bash 4.0+, curl

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_NAME="vim-setup"
SCRIPT_VERSION="1.0.0"

REPO_BASE_URL="https://raw.githubusercontent.com/opipi406/linux-setup-tools/main/vim"
VIMRC_URL="${REPO_BASE_URL}/vimrc.template"
VIMRC_PATH="$HOME/.vimrc"

# =============================================================================
# Color and Icon Definitions
# =============================================================================

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    COLOR_ENABLED=true
else
    COLOR_ENABLED=false
fi

if $COLOR_ENABLED; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[0;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' NC=''
fi

ICON_CHECK="✓"
ICON_CROSS="✗"
ICON_WARN="⚠"
ICON_INFO="ℹ"
ICON_ARROW="→"

# =============================================================================
# Output Functions
# =============================================================================

info() {
    printf "${BLUE}[${ICON_INFO} INFO]${NC} %s\n" "$*"
}

success() {
    printf "${GREEN}[${ICON_CHECK} OK]${NC} %s\n" "$*"
}

warn() {
    printf "${YELLOW}[${ICON_WARN} WARN]${NC} %s\n" "$*" >&2
}

error() {
    printf "${RED}[${ICON_CROSS} ERROR]${NC} %s\n" "$*" >&2
}

step() {
    local current="$1"
    local total="$2"
    local message="$3"
    printf "${CYAN}[%d/%d]${NC} %s\n" "$current" "$total" "$message"
}

header() {
    local text="$1"
    local width=${2:-60}
    printf "\n${BOLD}%s${NC}\n" "$text"
    printf "${DIM}%s${NC}\n" "$(printf '─%.0s' $(seq 1 "$width"))"
}

# =============================================================================
# Interactive Functions
# =============================================================================

confirm() {
    local prompt="${1:-Continue?}"
    local default="${2:-n}"
    local reply

    if [[ "$default" =~ ^[Yy] ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi

    printf "${YELLOW}${prompt}${NC}"
    read -r reply

    if [[ -z "$reply" ]]; then
        reply="$default"
    fi

    [[ "$reply" =~ ^[Yy] ]]
}

# =============================================================================
# Spinner Functions
# =============================================================================

spinner() {
    local message="$1"
    shift
    local pid
    local spin_chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    local i=0

    "$@" &
    pid=$!

    printf '\033[?25l'

    while kill -0 "$pid" 2>/dev/null; do
        printf "\r${CYAN}[%s]${NC} %s" "${spin_chars:i++%${#spin_chars}:1}" "$message"
        sleep 0.1
    done

    wait "$pid"
    local exit_code=$?

    printf '\033[?25h'
    printf '\r\033[K'

    if [[ $exit_code -eq 0 ]]; then
        success "$message"
    else
        error "$message"
    fi

    return $exit_code
}

# =============================================================================
# Utility Functions
# =============================================================================

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        error "必要なコマンドが見つかりません: $cmd"
        exit 1
    fi
}

cleanup() {
    :
}

# =============================================================================
# Signal Handling
# =============================================================================

trap cleanup EXIT
trap 'echo; error "中断されました"; exit 130' INT
trap 'error "終了シグナルを受信しました"; exit 143' TERM

# =============================================================================
# Usage and Help
# =============================================================================

usage() {
    printf '%b\n' "
${BOLD}Usage:${NC} $SCRIPT_NAME [options]

${BOLD}Description:${NC}
    XServer向け vim 環境セットアップスクリプト
    GitHubリポジトリから .vimrc をダウンロードして配置します。

${BOLD}Options:${NC}
    -h, --help      ヘルプを表示
    -v, --version   バージョンを表示
    -f, --force     確認なしで上書き

${BOLD}Remote Usage:${NC}
    bash <(curl -sL ${REPO_BASE_URL}/install.sh)

${BOLD}Examples:${NC}
    $SCRIPT_NAME
    $SCRIPT_NAME --force
"
}

version() {
    echo "$SCRIPT_NAME version $SCRIPT_VERSION"
}

# =============================================================================
# Argument Parsing
# =============================================================================

FORCE=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                exit 0
                ;;
            -v|--version)
                version
                exit 0
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            --)
                shift
                break
                ;;
            -*)
                error "不明なオプション: $1"
                usage >&2
                exit 2
                ;;
            *)
                break
                ;;
        esac
    done
}

# =============================================================================
# Core Functions
# =============================================================================

download_vimrc() {
    curl -fsSL "$VIMRC_URL" -o "$VIMRC_PATH"
}

backup_vimrc() {
    local backup_path="${VIMRC_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$VIMRC_PATH" "$backup_path"
    echo "$backup_path"
}

# =============================================================================
# Main Logic
# =============================================================================

parse_args "$@"

header "Vim Setup - XServer"

TOTAL_STEPS=3

# Step 1: 環境チェック
step 1 $TOTAL_STEPS "環境をチェックしています..."
require_command vim
require_command curl
success "vim と curl が利用可能です"

# Step 2: 既存ファイルの確認
step 2 $TOTAL_STEPS "既存の .vimrc を確認しています..."

if [[ -f "$VIMRC_PATH" ]]; then
    warn ".vimrc が既に存在します: $VIMRC_PATH"

    if $FORCE; then
        backup_path=$(backup_vimrc)
        info "バックアップを作成しました ${ICON_ARROW} $backup_path"
    else
        if confirm "既存の .vimrc をバックアップして上書きしますか？"; then
            backup_path=$(backup_vimrc)
            info "バックアップを作成しました ${ICON_ARROW} $backup_path"
        else
            if confirm "バックアップなしで上書きしますか？"; then
                info "バックアップなしで続行します"
            else
                info "セットアップを中止しました"
                exit 0
            fi
        fi
    fi
else
    info ".vimrc は存在しません。新規作成します"
fi

# Step 3: .vimrc のダウンロードと配置
step 3 $TOTAL_STEPS ".vimrc をダウンロードしています..."
spinner ".vimrc をダウンロード中" download_vimrc

echo
success "vim 環境のセットアップが完了しました"
info "配置先: $VIMRC_PATH"
info "設定を確認するには: vim ~/.vimrc"
echo

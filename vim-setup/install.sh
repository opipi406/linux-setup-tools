#!/usr/bin/env bash
#
# Script Name: vim-setup
# Description: XServer向け vim 環境セットアップスクリプト
# Usage: bash <(curl -sL https://raw.githubusercontent.com/opipi406/linux-setup-tools/main/vim-setup/install.sh)
#
# Requirements: Bash 4.0+, curl, git, make, gcc(or cc)

set -euo pipefail

# =============================================================================
# Configuration
# =============================================================================

SCRIPT_NAME="vim-setup"

REPO_BASE_URL="https://raw.githubusercontent.com/opipi406/linux-setup-tools/main/vim-setup"
VIMRC_URL="${REPO_BASE_URL}/vimrc.template"
VIMRC_PATH="$HOME/.vimrc"

INSTALL_PREFIX="$HOME/local"
BUILD_DIR="$HOME/download"

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
    MAGENTA='\033[0;35m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' DIM='' NC=''
fi

ICON_CHECK="✓"
ICON_CROSS="✗"
ICON_WARN="⚠"
ICON_INFO="ℹ"
ICON_ARROW="→"
ICON_BULLET="•"

# =============================================================================
# Output Functions
# =============================================================================

info() {
    printf "${BLUE}${ICON_INFO}  %s${NC}\n" "$*"
}

success() {
    printf "${GREEN}${ICON_CHECK}  %s${NC}\n" "$*"
}

warn() {
    printf "${YELLOW}${ICON_WARN}  %s${NC}\n" "$*" >&2
}

error() {
    printf "${RED}${ICON_CROSS}  %s${NC}\n" "$*" >&2
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

    printf "${MAGENTA}${prompt}${NC}"
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
# Core Functions
# =============================================================================

build_ncurses_from_source() {
    local ncurses_url="https://invisible-island.net/datafiles/release/ncurses.tar.gz"

    mkdir -p "$BUILD_DIR"

    curl -fsSL "$ncurses_url" -o "$BUILD_DIR/ncurses.tar.gz"
    tar xzf "$BUILD_DIR/ncurses.tar.gz" -C "$BUILD_DIR"

    local ncurses_dir
    ncurses_dir=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "ncurses-*" | head -1)

    if [[ -z "$ncurses_dir" ]]; then
        error "ncurses のソース展開に失敗しました"
        return 1
    fi

    cd "$ncurses_dir"
    ./configure --prefix="$INSTALL_PREFIX"
    make
    make install
    cd -
}

build_vim_from_source() {
    mkdir -p "$BUILD_DIR"

    cd "$BUILD_DIR"
    git clone --depth 1 https://github.com/vim/vim.git
    cd vim

    ./configure --prefix="$INSTALL_PREFIX" --with-local-dir="$INSTALL_PREFIX"
    make
    make install
    cd -
}

setup_vim_environment() {
    local bashrc="$HOME/.bashrc"
    local path_entry="export PATH=\"$INSTALL_PREFIX/bin:\$PATH\""
    local alias_entry="alias vi='vim'"
    local changed=false

    # .bashrc がなければ作成
    if [[ ! -f "$bashrc" ]]; then
        touch "$bashrc"
    fi

    # PATH 追加（重複チェック）
    if ! grep -qF "$INSTALL_PREFIX/bin" "$bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# vim (source build)"
            echo "$path_entry"
        } >>"$bashrc"
        changed=true
    fi

    # alias vi='vim' 追加（重複チェック）
    if ! grep -qF "alias vi='vim'" "$bashrc" 2>/dev/null; then
        if ! $changed; then
            echo "" >>"$bashrc"
        fi
        echo "$alias_entry" >>"$bashrc"
        changed=true
    fi

    if $changed; then
        success ".bashrc に PATH と alias を追加しました"
    else
        info ".bashrc の設定は既に存在します"
    fi

    # 現在のセッションにも反映
    export PATH="$INSTALL_PREFIX/bin:$PATH"
}

download_vimrc() {
    curl -fsSL "$VIMRC_URL" -o "$VIMRC_PATH"
}

backup_vimrc() {
    local backup_path="${VIMRC_PATH}.bak.$(date +%Y%m%d%H%M%S)"
    cp "$VIMRC_PATH" "$backup_path"
    echo "$backup_path"
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
${BOLD}Usage:${NC} install.sh [options]

${BOLD}Description:${NC}
    XServer向け vim 環境セットアップスクリプト
    ncurses・vim をソースビルドし、.vimrc を配置します。

${BOLD}Options:${NC}
    -h, --help      ヘルプを表示
    -f, --force     確認なしで実行

${BOLD}Remote Usage:${NC}
    bash <(curl -sL ${REPO_BASE_URL}/install.sh)

${BOLD}Examples:${NC}
    install.sh
    install.sh --force
"
}

# =============================================================================
# Argument Parsing
# =============================================================================

FORCE=false

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
        -h | --help)
            usage
            exit 0
            ;;
        -f | --force)
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
# Main Logic
# =============================================================================

parse_args "$@"

header "Vim Setup - XServer"

TOTAL_STEPS=5

# Step 1: 環境チェック
step 1 $TOTAL_STEPS "環境をチェックしています..."

require_command git
require_command make
require_command curl

if ! command -v gcc &>/dev/null && ! command -v cc &>/dev/null; then
    error "必要なコマンドが見つかりません: gcc (or cc)"
    exit 1
fi

if command -v vim &>/dev/null; then
    warn "vim は既にインストールされています: $(command -v vim)"
    if ! $FORCE; then
        if ! confirm "vim を再インストールしますか？"; then
            warn "vim のインストールをスキップしました"
            # Step 4, 5 のみ実行するためフラグを設定
            SKIP_BUILD=true
        fi
    fi
fi

SKIP_BUILD="${SKIP_BUILD:-false}"
success "環境チェック完了"

# Step 2: ncurses のインストール
step 2 $TOTAL_STEPS "ncurses をインストールしています..."

if $SKIP_BUILD; then
    warn "ncurses のインストールをスキップしました"
else
    if ! $FORCE; then
        if ! confirm "ncurses をインストールしますか？"; then
            warn "ncurses のインストールをスキップしました"
            SKIP_BUILD=true
        fi
    fi

    if ! $SKIP_BUILD; then
        info "ncurses をビルド中"
        if build_ncurses_from_source; then
            success "ncurses をビルド中"
        else
            error "ncurses をビルド中"
        fi
        info "インストール先: $INSTALL_PREFIX"
    fi
fi

# Step 3: Vim のインストール
step 3 $TOTAL_STEPS "Vim をインストールしています..."

if $SKIP_BUILD; then
    warn "Vim のインストールをスキップしました"
else
    if ! $FORCE; then
        if ! confirm "Vim をインストールしますか？"; then
            warn "Vim のインストールをスキップしました"
            SKIP_BUILD=true
        fi
    fi

    if ! $SKIP_BUILD; then
        info "Vim をビルド中"
        if build_vim_from_source; then
            success "Vim をビルド中"
        else
            error "Vim をビルド中"
        fi

        if [[ -x "$INSTALL_PREFIX/bin/vim" ]]; then
            success "Vim のインストールが完了しました ${ICON_ARROW} $INSTALL_PREFIX/bin/vim"
        else
            error "Vim のインストールに失敗しました"
            exit 1
        fi
    fi
fi

# Step 4: 環境設定 (PATH・alias)
step 4 $TOTAL_STEPS "環境設定を確認しています..."

if ! $FORCE; then
    if ! confirm ".bashrc に PATH と alias を追加しますか？"; then
        warn "環境設定をスキップしました"
    else
        setup_vim_environment
    fi
else
    setup_vim_environment
fi

# Step 5: .vimrc の設定
step 5 $TOTAL_STEPS ".vimrc を設定しています..."

SKIP_VIMRC=false

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
            SKIP_VIMRC=true
        fi
    fi
else
    info ".vimrc は存在しません。新規作成します"
    if ! $FORCE; then
        if ! confirm ".vimrc をダウンロードして配置しますか？"; then
            SKIP_VIMRC=true
        fi
    fi
fi

if $SKIP_VIMRC; then
    warn ".vimrc の設定をスキップしました"
else
    info ".vimrc をダウンロード中"
    if download_vimrc; then
        success ".vimrc をダウンロード中"
    else
        error ".vimrc をダウンロード中"
    fi
fi

echo
success "vim 環境のセットアップが完了しました"
info "配置先: $INSTALL_PREFIX/bin/vim"
info "設定ファイル: $VIMRC_PATH"
info "設定を反映するには: source ~/.bashrc"
echo

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

NCURSES_URL="https://invisible-island.net/datafiles/release/ncurses.tar.gz"
VIM_REPO_URL="https://github.com/vim/vim.git"

# =============================================================================
# Color Definitions
# =============================================================================

if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[0;33m'
    BLUE='\033[0;34m' MAGENTA='\033[0;35m' CYAN='\033[0;36m'
    BOLD='\033[1m' DIM='\033[2m' NC='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' MAGENTA='' CYAN='' BOLD='' DIM='' NC=''
fi

# =============================================================================
# Output Functions
# =============================================================================

info()    { printf "${BLUE}[INFO]${NC}  %s\n" "$*"; }
success() { printf "${GREEN}[OK]${NC}    %s\n" "$*"; }
warn()    { printf "${YELLOW}[WARN]${NC}  %s\n" "$*" >&2; }
error()   { printf "${RED}[ERROR]${NC} %s\n" "$*" >&2; }

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

cleanup() {
    :
}

# =============================================================================
# Core Functions
# =============================================================================

require_command() {
    local cmd="$1"
    if ! command -v "$cmd" &>/dev/null; then
        error "必要なコマンドが見つかりません: $cmd"
        exit 1
    fi
}

build_ncurses_from_source() {
    local log_file="$BUILD_DIR/ncurses-build.log"

    mkdir -p "$BUILD_DIR"

    curl -fsSL "$NCURSES_URL" -o "$BUILD_DIR/ncurses.tar.gz"
    tar xzf "$BUILD_DIR/ncurses.tar.gz" -C "$BUILD_DIR"

    local ncurses_dir
    ncurses_dir=$(find "$BUILD_DIR" -maxdepth 1 -type d -name "ncurses-*" | head -1)

    if [[ -z "$ncurses_dir" ]]; then
        error "ncurses のソース展開に失敗しました"
        return 1
    fi

    (
        set -euo pipefail
        cd "$ncurses_dir"
        ./configure --prefix="$INSTALL_PREFIX" \
            --without-debug \
            --without-tests \
            >>"$log_file" 2>&1
        make >>"$log_file" 2>&1
        make install >>"$log_file" 2>&1
    )
}

build_vim_from_source() {
    local log_file="$BUILD_DIR/vim-build.log"
    local vim_src="$BUILD_DIR/vim"

    mkdir -p "$BUILD_DIR"

    # 既存のソースがあれば削除
    if [[ -d "$vim_src" ]]; then
        rm -rf "$vim_src"
    fi

    (
        set -euo pipefail
        cd "$BUILD_DIR"
        git clone --depth 1 "$VIM_REPO_URL" >>"$log_file" 2>&1
        cd vim

        CPPFLAGS="-I$INSTALL_PREFIX/include" \
        LDFLAGS="-L$INSTALL_PREFIX/lib" \
        ./configure --prefix="$INSTALL_PREFIX" \
            --with-local-dir="$INSTALL_PREFIX" \
            --with-tlib=ncurses \
            --enable-multibyte \
            >>"$log_file" 2>&1

        make >>"$log_file" 2>&1
        make install >>"$log_file" 2>&1
    )
}

setup_vim_environment() {
    local bashrc="$HOME/.bashrc"
    local changed=false

    if [[ ! -f "$bashrc" ]]; then
        touch "$bashrc"
    fi

    # PATH 追加（重複チェック）
    if ! grep -qF "$INSTALL_PREFIX/bin" "$bashrc" 2>/dev/null; then
        {
            echo ""
            echo "# vim (source build)"
            echo "export PATH=\"$INSTALL_PREFIX/bin:\$PATH\""
        } >>"$bashrc"
        changed=true
    fi

    # alias vi='vim' 追加（重複チェック）
    if ! grep -qF "alias vi='vim'" "$bashrc" 2>/dev/null; then
        if ! $changed; then
            echo "" >>"$bashrc"
        fi
        echo "alias vi='vim'" >>"$bashrc"
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

clean_build_artifacts() {
    if [[ -d "$BUILD_DIR" ]]; then
        rm -rf "$BUILD_DIR/ncurses-"* "$BUILD_DIR/ncurses.tar.gz" "$BUILD_DIR/vim"
        success "ビルドファイルを削除しました"
    fi
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

TOTAL_STEPS=6

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
        if ! confirm "ncurses をソースからビルドしますか？"; then
            warn "ncurses のインストールをスキップしました"
            SKIP_BUILD=true
        fi
    fi

    if ! $SKIP_BUILD; then
        info "ncurses をビルド中..."
        if build_ncurses_from_source; then
            success "ncurses のインストールが完了しました"
            info "インストール先: $INSTALL_PREFIX"
        else
            error "ncurses のビルドに失敗しました"
            info "ログファイル: $BUILD_DIR/ncurses-build.log"
            exit 1
        fi
    fi
fi

# Step 3: Vim のインストール
step 3 $TOTAL_STEPS "Vim をインストールしています..."

if $SKIP_BUILD; then
    warn "Vim のインストールをスキップしました"
else
    if ! $FORCE; then
        if ! confirm "Vim をソースからビルドしますか？"; then
            warn "Vim のインストールをスキップしました"
            SKIP_BUILD=true
        fi
    fi

    if ! $SKIP_BUILD; then
        info "Vim をビルド中..."
        if build_vim_from_source; then
            success "Vim のインストールが完了しました"
            info "配置先: $INSTALL_PREFIX/bin/vim"
        else
            error "Vim のビルドに失敗しました"
            info "ログファイル: $BUILD_DIR/vim-build.log"
            exit 1
        fi

        if [[ ! -x "$INSTALL_PREFIX/bin/vim" ]]; then
            error "Vim のバイナリが見つかりません: $INSTALL_PREFIX/bin/vim"
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
        info "バックアップを作成しました: $backup_path"
    else
        if confirm "既存の .vimrc をバックアップして上書きしますか？"; then
            backup_path=$(backup_vimrc)
            info "バックアップを作成しました: $backup_path"
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
    if curl -fsSL "$VIMRC_URL" -o "$VIMRC_PATH"; then
        success ".vimrc を配置しました: $VIMRC_PATH"
    else
        error ".vimrc のダウンロードに失敗しました"
    fi
fi

# Step 6: ビルドファイルのクリーンアップ
step 6 $TOTAL_STEPS "ビルドファイルをクリーンアップしています..."

if ! $SKIP_BUILD; then
    if $FORCE; then
        clean_build_artifacts
    else
        if confirm "ビルドに使用したファイルを削除しますか？" "y"; then
            clean_build_artifacts
        else
            warn "ビルドファイルを保持しました: $BUILD_DIR"
        fi
    fi
else
    info "ビルドファイルのクリーンアップは不要です"
fi

echo
success "vim 環境のセットアップが完了しました"
info "配置先: $INSTALL_PREFIX/bin/vim"
info "設定ファイル: $VIMRC_PATH"
info "設定を反映するには: source ~/.bashrc"
echo

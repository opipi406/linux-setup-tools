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

VIM_INSTALL_PREFIX="$HOME/local"
VIM_BUILD_DIR="$HOME/.vim_build_tmp"

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
    cleanup_build_artifacts
}

check_sudo_available() {
    sudo -n true 2>/dev/null
}

cleanup_build_artifacts() {
    if [[ -d "$VIM_BUILD_DIR" ]]; then
        rm -rf "$VIM_BUILD_DIR"
    fi
}

fetch_latest_vim_version() {
    local latest_tag
    latest_tag=$(curl -fsSL "https://api.github.com/repos/vim/vim/tags?per_page=1" \
        | grep -o '"name": *"v[^"]*"' | head -1 | grep -o 'v[^"]*')
    if [[ -z "$latest_tag" ]]; then
        error "vim の最新バージョンを取得できませんでした"
        exit 1
    fi
    echo "${latest_tag#v}"
}

build_vim_from_source() {
    # 最新バージョンの取得
    info "vim の最新バージョンを確認しています..."
    local vim_version
    vim_version=$(fetch_latest_vim_version)
    local vim_source_url="https://github.com/vim/vim/archive/refs/tags/v${vim_version}.tar.gz"

    # ビルドツールの確認
    local missing_tools=()
    for tool in make tar; do
        if ! command -v "$tool" &>/dev/null; then
            missing_tools+=("$tool")
        fi
    done
    if ! command -v gcc &>/dev/null && ! command -v cc &>/dev/null; then
        missing_tools+=("gcc")
    fi
    if [[ ${#missing_tools[@]} -gt 0 ]]; then
        error "ソースビルドに必要なツールが不足しています: ${missing_tools[*]}"
        error "システム管理者にインストールを依頼してください"
        exit 1
    fi

    # ビルドディレクトリの準備
    cleanup_build_artifacts
    mkdir -p "$VIM_BUILD_DIR"

    # ソースのダウンロードと展開
    info "vim ${vim_version} のソースをダウンロードしています..."
    if ! curl -fsSL "$vim_source_url" -o "$VIM_BUILD_DIR/vim.tar.gz"; then
        error "vim のソースコードのダウンロードに失敗しました"
        exit 1
    fi
    tar xzf "$VIM_BUILD_DIR/vim.tar.gz" -C "$VIM_BUILD_DIR" --strip-components=1

    # configure & make
    info "vim をビルドしています（数分かかる場合があります）..."
    cd "$VIM_BUILD_DIR"
    ./configure \
        --prefix="$VIM_INSTALL_PREFIX" \
        --enable-gui=no \
        --without-x \
        --with-tlib=ncurses \
        --with-features=normal \
        &>/dev/null

    local nproc_val
    nproc_val=$(nproc 2>/dev/null || getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
    make -j"$nproc_val" &>/dev/null

    # インストール
    mkdir -p "$VIM_INSTALL_PREFIX"
    make install &>/dev/null
    cd - &>/dev/null

    # ビルドアーティファクトの削除
    cleanup_build_artifacts

    if [[ -x "$VIM_INSTALL_PREFIX/bin/vim" ]]; then
        success "vim のソースビルドが完了しました → $VIM_INSTALL_PREFIX/bin/vim"
    else
        error "vim のソースビルドに失敗しました"
        exit 1
    fi
}

setup_vim_path() {
    local path_entry="export PATH=\"$VIM_INSTALL_PREFIX/bin:\$PATH\""

    # 既にPATHに含まれている場合はスキップ
    if [[ ":$PATH:" == *":$VIM_INSTALL_PREFIX/bin:"* ]]; then
        return 0
    fi

    # .bashrc に PATH を追加
    local bashrc="$HOME/.bashrc"
    if [[ -f "$bashrc" ]] && grep -qF "$VIM_INSTALL_PREFIX/bin" "$bashrc"; then
        return 0
    fi

    echo "" >> "$bashrc"
    echo "# vim (source build)" >> "$bashrc"
    echo "$path_entry" >> "$bashrc"
    info "PATH設定を .bashrc に追加しました"
    info "反映するには: source ~/.bashrc"

    # 現在のセッションにも反映
    export PATH="$VIM_INSTALL_PREFIX/bin:$PATH"
}

install_vim_auto() {
    if check_sudo_available; then
        # sudo が使える場合: パッケージマネージャーでインストール
        info "パッケージマネージャーで vim をインストールします..."
        if command -v apt-get &>/dev/null; then
            sudo apt-get update -qq && sudo apt-get install -y -qq vim
        elif command -v yum &>/dev/null; then
            sudo yum install -y vim
        elif command -v dnf &>/dev/null; then
            sudo dnf install -y vim
        elif command -v pacman &>/dev/null; then
            sudo pacman -S --noconfirm vim
        elif command -v apk &>/dev/null; then
            sudo apk add vim
        else
            warn "パッケージマネージャーを検出できません。ソースからビルドします..."
            build_vim_from_source
            setup_vim_path
            return
        fi

        if command -v vim &>/dev/null; then
            success "vim のインストールが完了しました"
        else
            error "vim のインストールに失敗しました"
            exit 1
        fi
    else
        # sudo が使えない場合: ソースビルド
        warn "sudo が利用できません。ソースから vim をビルドします..."
        build_vim_from_source
        setup_vim_path
    fi
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
    GitHubリポジトリから .vimrc をダウンロードして配置します。

${BOLD}Options:${NC}
    -h, --help      ヘルプを表示
    -v, --version   バージョンを表示
    -f, --force     確認なしで上書き

${BOLD}Remote Usage:${NC}
    bash <(curl -sL ${REPO_BASE_URL}/install.sh)

${BOLD}Examples:${NC}
    install.sh
    install.sh --force
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
        -h | --help)
            usage
            exit 0
            ;;
        -v | --version)
            version
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

# Step 1: 環境チェック & vimインストール
step 1 $TOTAL_STEPS "環境をチェックしています..."
require_command curl

if ! command -v vim &>/dev/null; then
    warn "vim がインストールされていません"
    install_vim_auto
fi

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

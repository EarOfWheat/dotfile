#!/usr/bin/env bash
# dotfiles —— $HOME 配置备份/恢复脚本
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"   # 裸 git 目录（不是工作副本）
WORK_TREE="${WORK_TREE:-$HOME}"
DOTFILES_REMOTE="${DOTFILES_REMOTE:-}"
DOTFILES_BRANCH="${DOTFILES_BRANCH:-main}"
GIT=(git --git-dir="$DOTFILES_DIR" --work-tree="$WORK_TREE")

msg()  { printf '\033[1;34m[*]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; exit 1; }

need_gitdir() { [[ -d "$DOTFILES_DIR" ]] || die "未初始化，先运行: $0 init"; }

cmd_init() {
  if [[ -d "$DOTFILES_DIR" ]]; then msg "已存在 $DOTFILES_DIR"; return; fi
  msg "初始化裸仓库 $DOTFILES_DIR"
  git init --bare "$DOTFILES_DIR"
  # 关键：否则 status/add 会遍历整个 $HOME，非常慢
  "${GIT[@]}" config --local status.showUntrackedFiles no
  "${GIT[@]}" config --local core.worktree "$WORK_TREE"
  if [[ -n $DOTFILES_REMOTE ]]; then
    "${GIT[@]}" remote add origin "$DOTFILES_REMOTE"
    msg "远程: $DOTFILES_REMOTE"
  fi
  [[ -f "$WORK_TREE/.gitignore" ]] || warn "缺少 $WORK_TREE/.gitignore（白名单模式必需）"
  msg "完成。编辑 .gitignore 后运行: $0 backup"
}

cmd_backup() {
  need_gitdir
  "${GIT[@]}" add -A
  if "${GIT[@]}" diff --cached --quiet; then
    msg "没有变更"
  else
    "${GIT[@]}" commit -m "backup: $(hostname) $(date '+%F %T')"
    "${GIT[@]}" branch -M "$DOTFILES_BRANCH" 2>/dev/null || true
    msg "已提交"
  fi
  if "${GIT[@]}" remote get-url origin >/dev/null 2>&1; then
    if ! "${GIT[@]}" push -u origin "$DOTFILES_BRANCH"; then
      warn "push 失败，尝试 pull --rebase"
      "${GIT[@]}" pull --rebase origin "$DOTFILES_BRANCH"
      "${GIT[@]}" push -u origin "$DOTFILES_BRANCH"
    fi
    msg "已推送"
  else
    warn "未配置远程，跳过推送（DOTFILES_REMOTE=git@... 重新 init 可配）"
  fi
}

cmd_status() { need_gitdir; "${GIT[@]}" status; }
cmd_diff()   { need_gitdir; "${GIT[@]}" diff --stat; "${GIT[@]}" diff --cached --stat; }
cmd_list()   { need_gitdir; "${GIT[@]}" ls-files; }

cmd_check() {
  need_gitdir
  local n; n=$("${GIT[@]}" ls-files | wc -l)
  msg "跟踪文件数: $n"

  msg "大文件(>1MB):"
  "${GIT[@]}" ls-files -z | while IFS= read -r -d '' f; do
    [[ -f "$WORK_TREE/$f" ]] || continue
    local sz; sz=$(wc -c < "$WORK_TREE/$f")
    (( sz > 1048576 )) && printf '  %10d  %s\n' "$sz" "$f"
  done

  msg "疑似密钥:"
  "${GIT[@]}" grep -InE 'BEGIN (RSA|OPENSSH|EC|DSA|PGP) PRIVATE KEY|ghp_[A-Za-z0-9]{36}|github_pat_|AKIA[0-9A-Z]{16}|xox[baprs]-|sk-[A-Za-z0-9]{20,}' -- . || true
}

cmd_restore() {
  [[ -d "$DOTFILES_DIR" ]] && die "已存在 $DOTFILES_DIR，请先移走"
  [[ -n $DOTFILES_REMOTE ]] || die "请先设置 DOTFILES_REMOTE 环境变量"
  msg "克隆 $DOTFILES_REMOTE"
  git clone --bare "$DOTFILES_REMOTE" "$DOTFILES_DIR"
  "${GIT[@]}" config --local status.showUntrackedFiles no
  "${GIT[@]}" config --local core.worktree "$WORK_TREE"
  warn "checkout 会覆盖 $WORK_TREE 下同名文件"
  read -rp "继续？[y/N] " ans
  [[ $ans == [yY] ]] || exit 1
  "${GIT[@]}" checkout -f
  msg "恢复完成"
}

case "${1:-}" in
  init)      cmd_init ;;
  backup|b)  cmd_backup ;;
  status|s)  cmd_status ;;
  diff)      cmd_diff ;;
  list)      cmd_list ;;
  check)     cmd_check ;;
  restore)   cmd_restore ;;
  *)
    cat <<EOF
用法: $0 <命令>
  init     初始化裸仓库
  backup   提交并推送
  status   查看状态
  diff     查看变更统计
  list     列出被跟踪的文件
  check    检查大文件与疑似密钥
  restore  新机器恢复（需 DOTFILES_REMOTE）
环境变量:
  DOTFILES_DIR     默认 ~/.dotfiles
  DOTFILES_REMOTE  远程地址，如 git@github.com:you/dotfiles.git
  DOTFILES_BRANCH  默认 main
EOF
    ;;
esac

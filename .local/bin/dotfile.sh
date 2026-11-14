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

is_conflict() {
  # 本地存在且内容 != HEAD 版本 → 冲突
  local f=$1
  [[ -e "$WORK_TREE/$f" ]] || return 1
  if "${GIT[@]}" cat-file -e "HEAD:$f" 2>/dev/null; then
    if cmp -s <("${GIT[@]}" show "HEAD:$f") "$WORK_TREE/$f"; then
      return 1   # 内容一致，不算冲突
    fi
    return 0     # 内容不同，冲突
  fi
  return 0       # HEAD 里没有本地却有，也当冲突（保险）
}

cmd_restore() {
  [[ -d "$DOTFILES_DIR" ]] && die "已存在 $DOTFILES_DIR，请先移走（例如: mv $DOTFILES_DIR ${DOTFILES_DIR}.bak）"
  [[ -n $DOTFILES_REMOTE ]] || die "请先设置 DOTFILES_REMOTE 环境变量"
  [[ -t 0 ]] || die "restore 需要在交互终端中运行"

  msg "克隆 $DOTFILES_REMOTE → $DOTFILES_DIR"
  git clone --bare "$DOTFILES_REMOTE" "$DOTFILES_DIR"
  "${GIT[@]}" config --local status.showUntrackedFiles no
  "${GIT[@]}" config --local core.worktree "$WORK_TREE"

  local detected
  detected=$("${GIT[@]}" symbolic-ref --short HEAD 2>/dev/null || true)
  [[ -n $detected ]] && DOTFILES_BRANCH=$detected
  msg "分支: $DOTFILES_BRANCH"

  # ---------- 扫描冲突 ----------
  local -a all_files=() conflicts=() non_conflicts=()
  mapfile -t all_files < <("${GIT[@]}" ls-tree -r --name-only HEAD)
  local f
  for f in "${all_files[@]}"; do
    if is_conflict "$f"; then
      conflicts+=("$f")
    else
      non_conflicts+=("$f")
    fi
  done

  if (( ${#conflicts[@]} == 0 )); then
    msg "无冲突，全部恢复"
    "${GIT[@]}" checkout -f HEAD
    msg "完成。裸仓库位于: $DOTFILES_DIR"
    return
  fi

  warn "以下 ${#conflicts[@]} 个文件本地已存在且与仓库不同："
  printf '  %s\n' "${conflicts[@]}"
  cat <<EOF

请选择处理方式：
  [s] 跳过（默认）—— 只恢复其余文件，冲突留给你手动合并
  [b] 备份原文件后全部覆盖
  [i] 逐个交互处理
  [o] 全部强制覆盖
  [a] 中止

EOF
  local ans
  read -rp "选择 [s]: " ans
  ans=${ans:-s}

  case $ans in
    a|A)
      warn "已中止。裸仓库保留在 $DOTFILES_DIR（确认不需要可 rm -rf）"
      exit 1
      ;;
    o|O)
      "${GIT[@]}" checkout -f HEAD
      msg "已全部覆盖"
      ;;
    b|B)
      local backup_dir="$WORK_TREE/.dotfiles-restore-backup-$(date +%Y%m%d-%H%M%S)"
      mkdir -p "$backup_dir"
      for f in "${conflicts[@]}"; do
        mkdir -p "$backup_dir/$(dirname -- "$f")"
        cp -a -- "$WORK_TREE/$f" "$backup_dir/$f"
      done
      "${GIT[@]}" checkout -f HEAD
      msg "原文件已备份到: $backup_dir"
      ;;
    i|I)
      local a=""
      for f in "${conflicts[@]}"; do
        while :; do
          printf '\n--- %s ---\n' "$f"
          read -rp "[d]iff [o]verwrite [s]kip [b]ackup+overwrite [q]uit: " a
          case $a in
            d|D)
              if "${GIT[@]}" cat-file -e "HEAD:$f" 2>/dev/null; then
                diff -u --color=auto <("${GIT[@]}" show "HEAD:$f") "$WORK_TREE/$f" || true
              else
                diff -u --color=auto /dev/null "$WORK_TREE/$f" || true
              fi
              ;;
            o|O) "${GIT[@]}" checkout HEAD -- "$f"; msg "已覆盖: $f"; break ;;
            s|S) msg "已跳过: $f"; break ;;
            b|B)
              local bd="$WORK_TREE/.dotfiles-restore-backup-$(date +%Y%m%d-%H%M%S)"
              mkdir -p "$bd/$(dirname -- "$f")"
              cp -a -- "$WORK_TREE/$f" "$bd/$f"
              "${GIT[@]}" checkout HEAD -- "$f"
              msg "已备份到 $bd/$f 并覆盖"
              break
              ;;
            q|Q) warn "退出交互，未处理文件保留本地版本"; return ;;
          esac
        done
      done
      msg "逐个处理完成"
      ;;
    *)
      # ---- 默认 skip：只恢复非冲突文件 ----
      if (( ${#non_conflicts[@]} > 0 )); then
        printf '%s\0' "${non_conflicts[@]}" \
          | xargs -0 -n 50 "${GIT[@]}" checkout HEAD --
      fi
      # 冲突文件在 index 里指向 HEAD，status 就能显示为 modified
      if (( ${#conflicts[@]} > 0 )); then
        printf '%s\0' "${conflicts[@]}" \
          | xargs -0 -n 50 "${GIT[@]}" reset -q HEAD --
      fi
      warn "冲突文件已保留本地版本，未覆盖。请手动处理："
      printf '  %s\n' "${conflicts[@]}"
      cat <<EOF

后续流程：
  1. 查看差异:  dotfiles diff
  2. 逐个打开合并（或覆盖仓库版本）
  3. 提交:      dotfiles backup
EOF
      ;;
  esac

  msg "恢复完成。裸仓库位于: $DOTFILES_DIR"
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

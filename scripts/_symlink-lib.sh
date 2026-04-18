#!/usr/bin/env bash
# scripts/_symlink-lib.sh — Shared helpers for per-host mind-vault symlink setup.
#
# Source this from setup-<host>-symlinks.sh. Exports:
#   MV                             mind-vault root (resolved from MIND_VAULT env or default)
#   mv_resolve_root                populate MV, exit if missing
#   mv_link_skills_per_dir <dir>   per-skill symlinks under <dir>
#   mv_link_tree <subdir> <target> whole-directory symlink
#   mv_link_files_renamed <subdir> <target> <suffix>
#                                  per-file symlinks with filename suffix rewrite
#                                  (e.g. mind-vault/commands/foo.md -> target/foo<suffix>.md)
#
# The per-skill approach (mv_link_skills_per_dir) avoids a historical
# discovery bug in some hosts where a parent-directory symlink caused
# individual skill dirs not to be picked up. Linking each skill directly
# is safer across Cursor, Claude Code, OpenCode.

set -e

mv_resolve_root() {
  MV="${MIND_VAULT:-$HOME/projects/mind-vault}"
  if [[ ! -d "$MV" ]]; then
    echo "Error: mind-vault not found at $MV" >&2
    echo "Set MIND_VAULT env var or clone to ~/projects/mind-vault" >&2
    exit 1
  fi
  export MV
}

mv_link_skills_per_dir() {
  local target_dir="$1"
  mkdir -p "$target_dir"
  local d name target
  for d in "$MV"/skills/*/; do
    [[ -d "$d" ]] || continue
    name=$(basename "$d")
    target="$target_dir/$name"
    if [[ -L "$target" ]]; then
      # `ln -sfn` (not `-sf`): when target is an existing symlink to a directory,
      # `-sf` follows the dereference and creates a nested symlink *inside* that
      # directory instead of replacing the symlink. `-n` treats the target as a
      # regular file even if it's a symlink, so the replacement works correctly.
      ln -sfn "$(cd "$d" && pwd)" "$target"
      echo "  Updated skills/$name"
    elif [[ -e "$target" ]]; then
      # Real (non-symlink) file or directory — refuse to clobber user content.
      # `ln -sfn` cannot replace a real directory anyway (kernel rejects unlink
      # on a directory), and under `set -e` would abort the whole setup script.
      echo "  Skipped skills/$name (non-symlink exists at $target — leave intact)"
    else
      ln -s "$(cd "$d" && pwd)" "$target"
      echo "  Linked skills/$name"
    fi
  done
  echo "Skills: $target_dir/* -> mind-vault/skills/*"
}

mv_link_tree() {
  local subdir="$1"
  local target="$2"
  if [[ ! -d "$MV/$subdir" ]]; then
    echo "$subdir: source $MV/$subdir does not exist (skip)"
    return 0
  fi
  if [[ -L "$target" ]]; then
    rm "$target"
  fi
  if [[ ! -e "$target" ]]; then
    ln -s "$(cd "$MV/$subdir" && pwd)" "$target"
    echo "$subdir: $target -> mind-vault/$subdir"
  else
    echo "$subdir: $target exists as non-symlink (skip)"
  fi
}

mv_link_files_renamed() {
  local src_subdir="$1"
  local target_dir="$2"
  local suffix="$3"
  if [[ ! -d "$MV/$src_subdir" ]]; then
    echo "$src_subdir: source $MV/$src_subdir does not exist (skip)"
    return 0
  fi
  mkdir -p "$target_dir"
  local f base target
  for f in "$MV/$src_subdir"/*.md; do
    [[ -f "$f" ]] || continue
    base=$(basename "$f" .md)
    target="$target_dir/${base}${suffix}.md"
    if [[ -L "$target" ]]; then
      ln -sf "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" "$target"
      echo "  Updated $src_subdir/$base -> $(basename "$target")"
    elif [[ -e "$target" ]]; then
      # Real (non-symlink) file — refuse to clobber user-authored content like
      # custom .prompt.md / .instructions.md files in the VS Code user dir.
      echo "  Skipped $src_subdir/$base -> $(basename "$target") (non-symlink exists — leave intact)"
    else
      ln -s "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")" "$target"
      echo "  Linked $src_subdir/$base -> $(basename "$target")"
    fi
  done
  echo "$src_subdir: $target_dir/*${suffix}.md -> mind-vault/$src_subdir/*.md"
}

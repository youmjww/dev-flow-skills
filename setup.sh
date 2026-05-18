#!/bin/bash
set -e

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_DIR="$HOME/.claude/skills"

mkdir -p "$SKILLS_DIR"

for dir in "$REPO_DIR"/dev-flow*/; do
  name="$(basename "$dir")"
  target="$SKILLS_DIR/$name"

  if [ -e "$target" ] && [ ! -L "$target" ]; then
    echo "バックアップ: $target -> $target.bak"
    mv "$target" "$target.bak"
  fi

  ln -sf "$dir" "$target"
  echo "リンク作成: $target -> $dir"
done

echo ""
echo "セットアップ完了"

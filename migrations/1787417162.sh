echo "Point the Omarchy checkout at its new home on GitHub"

# The project moved from codeberg.org/malik-na/omarchy-mac to the omarchy-mac
# GitHub org. Updates fetch this checkout's tracking remote, so machines still
# pointing at the old home follow the move. Only the old canonical URLs are
# touched: forks and dev checkouts keep the origin they were given.

checkout="${OMARCHY_PATH:-$HOME/.local/share/omarchy}"
git -C "$checkout" rev-parse --is-inside-work-tree &>/dev/null || exit 0

origin=$(git -C "$checkout" remote get-url origin 2>/dev/null || true)
case "$origin" in
  https://codeberg.org/malik-na/omarchy-mac | \
  https://codeberg.org/malik-na/omarchy-mac.git | \
  git@codeberg.org:malik-na/omarchy-mac.git)
    git -C "$checkout" remote set-url origin https://github.com/omarchy-mac/omarchy-mac.git
    ;;
esac

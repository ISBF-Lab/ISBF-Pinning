#!/usr/bin/env bash
set -euo pipefail
commit="${1:?merged commit required}"
[[ "$commit" =~ ^[0-9a-f]{40}$ ]] || exit 2
source="/shared/isbf-pinning-releases/$commit/isbf-pinning"
target="/var/www/discourse/plugins/isbf-pinning"
[[ -f "$source/plugin.rb" ]] || exit 3
[[ ! -e "$target" || -L "$target" ]] || exit 4
ln -sfn "$source" "$target"

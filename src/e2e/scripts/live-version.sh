#!/usr/bin/env bash
# Prints the commit SHA the `:live` image was built from. Reads the JSON of
# `aws ecr describe-images --image-ids imageTag=live` on stdin: every deploy
# pushes one image as `:<sha>` and `:live`, so the one 40-character SHA tag
# among that image's tags is what is deployed. Fails, saying which case it
# found, when there is no SHA tag or more than one.
set -euo pipefail

shas=$(jq -r '.imageDetails[].imageTags[]?' | grep -E '^[0-9a-f]{40}$' || true)
count=$(printf '%s' "$shas" | grep -c . || true)

case "$count" in
  1)
    echo "$shas"
    ;;
  0)
    echo "live-version: the :live image has no SHA tag" >&2
    exit 1
    ;;
  *)
    echo "live-version: the :live image has $count SHA tags:" >&2
    echo "$shas" >&2
    exit 1
    ;;
esac

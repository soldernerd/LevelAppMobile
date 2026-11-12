#!/usr/bin/env bash
# Prints the release version of HEAD as GITHUB_OUTPUT lines (name=, tag=).
#
# Version = <major>.<minor>.<patch>
#   major.minor  from the `version:` line of pubspec.yaml
#   patch        commits since the commit that set that major.minor, so it
#                restarts at 0 whenever major or minor is bumped (a change to
#                the +build part or to the patch part of pubspec.yaml does not
#                restart it)
#
# The Android build number (versionCode) is a different thing: CI passes the
# total commit count for it, which must only ever grow (Google Play).
#
# Needs full history (actions/checkout with fetch-depth: 0).
set -euo pipefail

major_minor() { sed -n 's/^version: *\([0-9][0-9]*\.[0-9][0-9]*\)\..*/\1/p' | head -n 1; }

current=$(major_minor < pubspec.yaml)
if [ -z "$current" ]; then
  echo "cannot read major.minor from pubspec.yaml" >&2
  exit 1
fi

# Walk the commits that touched the version line, newest first, back to the
# first one of the unbroken run that has the current major.minor.
start=$(git rev-parse HEAD)
for c in $(git log --format=%H -G'^version:' -- pubspec.yaml); do
  v=$(git show "$c:pubspec.yaml" | major_minor)
  if [ "$v" = "$current" ]; then start=$c; else break; fi
done

patch=$(git rev-list --count "$start..HEAD")
echo "name=${current}.${patch}"
echo "tag=v${current}.${patch}"

#!/bin/bash
# Sourced by build/test scripts. Keep all compiler and SwiftPM caches local.
project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
build_root="${RESOLUTIONBAR_BUILD_ROOT:-$project_root/.build/local}"
mkdir -p "$build_root/module-cache" "$build_root/cache" "$build_root/config" "$build_root/security"
export CLANG_MODULE_CACHE_PATH="$build_root/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$build_root/module-cache"
swift_options=(--package-path "$project_root" --scratch-path "$build_root/swiftpm"
  --cache-path "$build_root/cache" --config-path "$build_root/config"
  --security-path "$build_root/security" --disable-sandbox)

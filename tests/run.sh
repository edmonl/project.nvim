#!/usr/bin/env bash

set -euo pipefail

project_root=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
test_root=$(mktemp -d "${TMPDIR:-/tmp}/project-nvim-tests.XXXXXX")
trap 'rm -rf -- "$test_root"' EXIT

normal_dir="$test_root/normal"
command_prefix_dir="$test_root/safe"
special_dir="$command_prefix_dir | let g:project_nvim_test_injected = 1"
mkdir "$normal_dir" "$command_prefix_dir" "$special_dir"

run_nvim() {
  local test_case=$1
  local scope=$2
  local target_dir=$3

  (
    cd "$project_root"
    PROJECT_NVIM_TEST_CASE="$test_case" \
      PROJECT_NVIM_TEST_SCOPE="$scope" \
      PROJECT_NVIM_TEST_DIR="$target_dir" \
      XDG_STATE_HOME="$test_root/state-$test_case-$scope" \
      nvim --headless -u NONE -i NONE \
        --cmd 'set shada=' \
        --cmd 'set runtimepath+=.' \
        "+lua dofile('tests/set_pwd_spec.lua')" \
        '+qa!'
  )
}

for scope in global tab win; do
  run_nvim valid_scope "$scope" "$normal_dir"
done
printf '%s\n' 'ok - changes the working directory for every valid scope'

for scope in tab win; do
  run_nvim special_path "$scope" "$special_dir"
done
printf '%s\n' 'ok - treats special characters in scoped paths as filename characters'

run_nvim invalid_scope invalid "$normal_dir"
printf '%s\n' 'ok - rejects an invalid scope without changing project state'

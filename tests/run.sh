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
  local test_spec=${4:-tests/set_pwd_spec.lua}

  (
    cd "$project_root"
    PROJECT_NVIM_TEST_CASE="$test_case" \
      PROJECT_NVIM_TEST_SCOPE="$scope" \
      PROJECT_NVIM_TEST_DIR="$target_dir" \
      PROJECT_NVIM_TEST_SPEC="$test_spec" \
      XDG_STATE_HOME="$test_root/state-$test_case-$scope" \
      nvim --headless -u NONE -i NONE \
        --cmd 'set shada=' \
        --cmd 'set runtimepath+=.' \
        "+lua dofile('tests/init.lua')"
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

for scope in global tab win; do
  run_nvim readd_project "$scope" "$normal_dir"
done
printf '%s\n' 'ok - restores deleted projects on a visit or explicit addition'

for test_case in delete_entries delete_during_load save_before_load; do
  history_dir="$test_root/history-$test_case"
  mkdir "$history_dir"
  run_nvim "$test_case" global "$history_dir" tests/history_spec.lua
  printf 'ok - history: %s\n' "$test_case"
done

for test_case in root_selection attach_lifecycle reconfigure; do
  lsp_dir="$test_root/lsp-$test_case"
  mkdir "$lsp_dir"
  run_nvim "$test_case" global "$lsp_dir" tests/lsp_spec.lua
  printf 'ok - LSP: %s\n' "$test_case"
done

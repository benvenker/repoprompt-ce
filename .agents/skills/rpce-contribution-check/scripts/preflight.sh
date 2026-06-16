#!/usr/bin/env bash
set -euo pipefail

mode="${1:-commit}"
case "$mode" in
  commit|push) ;;
  *)
    echo "usage: $0 [commit|push]" >&2
    exit 2
    ;;
esac

repo_root="$(git rev-parse --show-toplevel)"
cd "$repo_root"

tmp_root=""
cleanup() {
  if [[ -n "${tmp_root:-}" ]]; then
    rm -rf -- "$tmp_root"
  fi
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

log() { printf '\n==> %s\n' "$*"; }
fail() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
warn() { printf 'WARNING: %s\n' "$*" >&2; }

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "missing required tool '$1'. Install it before committing or pushing."
}

ensure_tmp_root() {
  if [[ -z "$tmp_root" ]]; then
    tmp_root="$(mktemp -d "${TMPDIR:-/tmp}/rpce-preflight.XXXXXX")"
  fi
}

docker_swift_image="${RPCE_PREFLIGHT_SWIFT_DOCKER_IMAGE:-swift:6.2.4-noble}"

docker_image_available() {
  command -v docker >/dev/null 2>&1 && docker image inspect "$1" >/dev/null 2>&1
}

install_docker_swift_wrapper_if_needed() {
  command -v swift >/dev/null 2>&1 && return 0
  [[ "$(uname -s)" == "Linux" ]] || return 0
  if ! docker_image_available "$docker_swift_image"; then
    return 0
  fi

  ensure_tmp_root
  mkdir -p "$tmp_root/bin"
  cat > "$tmp_root/bin/swift" <<EOF
#!/usr/bin/env bash
docker run --rm -v "\$PWD":/src -w /src "$docker_swift_image" swift "\$@"
EOF
  chmod +x "$tmp_root/bin/swift"
  export PATH="$tmp_root/bin:$PATH"
  warn "native swift not found; using Docker Swift image '$docker_swift_image' for preflight Swift commands"
}

scan_staged_index_blobs() {
  local files snapshot
  ensure_tmp_root
  files="$tmp_root/staged-files.z"
  snapshot="$tmp_root/staged-index"
  git diff --cached --name-only --diff-filter=d -z -- > "$files"
  if [[ ! -s "$files" ]]; then
    echo "No non-deleted staged index blobs to scan."
    return
  fi
  mkdir -p "$snapshot"
  git checkout-index --stdin -z --prefix="$snapshot/" < "$files"
  gitleaks dir --no-banner --redact "$snapshot"
}

require_clean_worktree() {
  local status_file
  ensure_tmp_root
  status_file="$tmp_root/status.z"
  git status --porcelain=v1 -z --untracked-files=all > "$status_file"
  if [[ -s "$status_file" ]]; then
    git status --short
    fail "working tree is not clean; commit, stash, or discard changes before pushing"
  fi
}

resolve_outgoing_base() {
  current_branch="$(git symbolic-ref --quiet --short HEAD)" \
    || fail "push mode requires a current branch; detached HEAD is not supported"
  if upstream_ref="$(git rev-parse --abbrev-ref --symbolic-full-name '@{upstream}' 2>/dev/null)" \
    && git rev-parse --verify --quiet "${upstream_ref}^{commit}" >/dev/null; then
    base_ref="$upstream_ref"
    base_reason="configured upstream"
  elif [[ "$current_branch" != "main" ]] \
    && git rev-parse --verify --quiet 'refs/remotes/origin/main^{commit}' >/dev/null; then
    base_ref="refs/remotes/origin/main"
    base_reason="origin/main fallback for a current branch without configured upstream"
  else
    fail "cannot determine outgoing base for '$current_branch'; configure its upstream or fetch origin/main for a non-main topic branch"
  fi
  range_spec="$base_ref..HEAD"
}

write_range_files() {
  local output="$1"
  git diff --name-only -z "$base_ref"...HEAD -- > "$output"
}

range_contains() {
  local files="$1"
  local pattern="$2"
  local file
  while IFS= read -r -d '' file; do
    if [[ "$file" =~ $pattern ]]; then
      return 0
    fi
  done < "$files"
  return 1
}

swift_changes_are_headless_only() {
  local files="$1"
  local file saw_swift=0
  while IFS= read -r -d '' file; do
    [[ "$file" == *.swift ]] || continue
    saw_swift=1
    case "$file" in
      Sources/RepoPromptHeadlessServer/*) ;;
      *) return 1 ;;
    esac
  done < "$files"
  [[ "$saw_swift" == "1" ]]
}

run_headless_linux_validation_fallback() {
  local files="$1"

  [[ "$(uname -s)" == "Linux" ]] || return 1
  swift_changes_are_headless_only "$files" || return 1
  docker_image_available "$docker_swift_image" || return 1

  warn "SwiftFormat/SwiftLint unavailable; running Linux headless fallback for Sources/RepoPromptHeadlessServer-only Swift changes"

  log "Build rpce-headless in Docker"
  docker run --rm -v "$repo_root":/src -w /src "$docker_swift_image" \
    swift build --product rpce-headless --scratch-path .build-linux

  log "Run rpce-headless Docker smokes"
  docker run --rm -v "$repo_root":/src -w /src "$docker_swift_image" \
    bash -lc 'apt-get update >/dev/null && apt-get install -y python3 >/dev/null && \
      python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_smoke.py .build-linux/debug/rpce-headless "$PWD" && \
      python3 Sources/RepoPromptHeadlessServer/Scripts/socket_auth_smoke.py .build-linux/debug/rpce-headless "$PWD" && \
      python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_smoke.py .build-linux/debug/rpce-headless "$PWD" && \
      python3 Sources/RepoPromptHeadlessServer/Scripts/mcp_agent_lifecycle_smoke.py .build-linux/debug/rpce-headless "$PWD" && \
      python3 Sources/RepoPromptHeadlessServer/Scripts/context_build_fake_agent_test.py .build-linux/debug/rpce-headless "$PWD" && \
      python3 Sources/RepoPromptHeadlessServer/Scripts/context_builder_mcp_fake_agent_test.py .build-linux/debug/rpce-headless "$PWD"'
}

run_swift_lint_or_fallback() {
  local files="$1"

  if command -v swiftformat >/dev/null 2>&1 && command -v swiftlint >/dev/null 2>&1; then
    make dev-lint
    return
  fi

  if run_headless_linux_validation_fallback "$files"; then
    return
  fi

  make dev-lint
}

push_success() {
  cat <<'EOF'

Scripted push checks passed.
Any validation-matrix evidence is still required before push; read `.agents/skills/rpce-contribution-check/references/validation-matrix.md`.
Push mode validated only the current branch against the computed range above. It does not validate tags, `--all`, `--mirror`, or arbitrary refspecs.
EOF
}

require_tool git
require_tool gitleaks
install_docker_swift_wrapper_if_needed

log "Check whitespace"
git diff --check
git diff --cached --check

log "Scan staged index blobs for secrets"
scan_staged_index_blobs

log "Run repository guardrails"
make guardrails

if [[ "$mode" == "commit" ]]; then
  cat <<'EOF'

Commit preflight passed.
Before committing, review `git status --short`, `git diff --cached --stat`, and `git diff --cached`.
Rerun commit preflight after any staging change. Use `push` mode before pushing committed work.
EOF
  exit 0
fi

log "Require a clean working tree before push"
require_clean_worktree

resolve_outgoing_base
log "Review current-branch outgoing range"
printf 'Current branch: %s\nComparison base (%s): %s\nComputed outgoing range: %s\n' \
  "$current_branch" "$base_reason" "$base_ref" "$range_spec"
git log --oneline "$range_spec"

outgoing_count="$(git rev-list --count "$range_spec")"
if [[ "$outgoing_count" == "0" ]]; then
  echo "No outgoing commits in $range_spec."
  push_success
  exit 0
fi

log "Scan outgoing commit range for secrets"
gitleaks git --no-banner --redact --log-opts="$range_spec" .

ensure_tmp_root
files="$tmp_root/range-files.z"
write_range_files "$files"

if range_contains "$files" '^(Scripts/conductor\.py|Scripts/test_conductor_(lifecycle|output)\.py|Makefile)$'; then
  log "Run conductor self-tests"
  make conductor-selftest
fi

if range_contains "$files" '\.swift$'; then
  log "Run coordinated Swift lint"
  run_swift_lint_or_fallback "$files"
fi

if range_contains "$files" '^(Sources/RepoPrompt/|Tests/RepoPromptTests/)'; then
  log "Run coordinated root tests"
  make dev-test
fi

if range_contains "$files" '^Packages/RepoPromptAgentProviders/'; then
  log "Run coordinated provider tests"
  make dev-provider-test
fi

if range_contains "$files" '^Sources/RepoPrompt/'; then
  log "Build RepoPrompt product"
  make dev-swift-build PRODUCT=RepoPrompt
fi

if range_contains "$files" '^(Sources/RepoPromptMCP/|Sources/RepoPromptShared/)'; then
  log "Build repoprompt-mcp product"
  make dev-swift-build PRODUCT=repoprompt-mcp
fi

push_success

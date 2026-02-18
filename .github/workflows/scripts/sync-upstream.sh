#!/usr/bin/env bash
# sync-upstream.sh — Syncs fork's main branch with upstream and merges into worktrunk.
#
# Outputs (via $GITHUB_OUTPUT):
#   main_updated    — "true" if main was advanced, "false" if already current
#   worktrunk_synced — "true" if worktrunk merge succeeded, "false" if conflicts
#   pr_created      — "true" if a conflict-resolution PR was opened
#   pr_url          — URL of the created PR (empty if none)
#
# Environment variables (required):
#   GITHUB_TOKEN    — PAT with contents:write and pull-requests:write
#   UPSTREAM_REPO   — upstream repo URL (e.g., https://github.com/github/spec-kit.git)
#   TARGET_BRANCH   — customization branch to merge into (e.g., worktrunk)
#
# Environment variables (optional):
#   GITHUB_OUTPUT   — path to write step outputs (set by Actions runner)

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults & setup
# ---------------------------------------------------------------------------
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/github/spec-kit.git}"
TARGET_BRANCH="${TARGET_BRANCH:-worktrunk}"
DATE_STAMP="$(date -u +%Y-%m-%d)"
SYNC_BRANCH="sync/upstream-${DATE_STAMP}"

output() {
  local key="$1" value="$2"
  echo "${key}=${value}"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${value}" >> "$GITHUB_OUTPUT"
  fi
}

# ---------------------------------------------------------------------------
# Step 1: Configure upstream remote
# ---------------------------------------------------------------------------
echo "::group::Configure upstream remote"
if git remote get-url upstream &>/dev/null; then
  echo "upstream remote already configured"
else
  echo "Adding upstream remote: ${UPSTREAM_REPO}"
  git remote add upstream "${UPSTREAM_REPO}"
fi
git fetch upstream --quiet
echo "::endgroup::"

# ---------------------------------------------------------------------------
# Step 2: Fast-forward main to upstream/main
# ---------------------------------------------------------------------------
echo "::group::Sync main → upstream/main"
git checkout main

LOCAL_SHA="$(git rev-parse main)"
UPSTREAM_SHA="$(git rev-parse upstream/main)"

if [[ "${LOCAL_SHA}" == "${UPSTREAM_SHA}" ]]; then
  echo "main is already up to date with upstream/main (${LOCAL_SHA:0:8})"
  output "main_updated" "false"
  output "worktrunk_synced" "false"
  output "pr_created" "false"
  output "pr_url" ""
  echo "::endgroup::"
  exit 0
fi

echo "Advancing main: ${LOCAL_SHA:0:8} → ${UPSTREAM_SHA:0:8}"
if ! git merge --ff-only upstream/main; then
  echo "::error::main branch has diverged from upstream/main. Cannot fast-forward."
  echo "::error::This means commits were pushed directly to main. Fix manually:"
  echo "::error::  git checkout main && git reset --hard upstream/main && git push --force-with-lease origin main"
  output "main_updated" "false"
  output "worktrunk_synced" "false"
  output "pr_created" "false"
  output "pr_url" ""
  exit 1
fi

git push origin main
echo "main synced to upstream/main (${UPSTREAM_SHA:0:8})"
output "main_updated" "true"
echo "::endgroup::"

# ---------------------------------------------------------------------------
# Step 3: Merge main into TARGET_BRANCH
# ---------------------------------------------------------------------------
echo "::group::Merge main → ${TARGET_BRANCH}"
git checkout "${TARGET_BRANCH}"

# Check if there's anything to merge (maybe worktrunk already includes main)
if git merge-base --is-ancestor main "${TARGET_BRANCH}"; then
  echo "${TARGET_BRANCH} already contains all commits from main"
  output "worktrunk_synced" "true"
  output "pr_created" "false"
  output "pr_url" ""
  echo "::endgroup::"
  exit 0
fi

# Attempt the merge
if git merge main --no-edit -m "chore(sync): merge upstream changes (${DATE_STAMP})"; then
  git push origin "${TARGET_BRANCH}"
  echo "Successfully merged main into ${TARGET_BRANCH}"
  output "worktrunk_synced" "true"
  output "pr_created" "false"
  output "pr_url" ""
  echo "::endgroup::"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 4: Handle merge conflicts — create a PR
# ---------------------------------------------------------------------------
echo "::warning::Merge conflicts detected merging main into ${TARGET_BRANCH}"

# Collect conflict info before aborting
CONFLICTING_FILES="$(git diff --name-only --diff-filter=U 2>/dev/null || true)"
git merge --abort

# Check for existing open sync PR to avoid duplicates
EXISTING_PR="$(gh pr list \
  --base "${TARGET_BRANCH}" \
  --head "sync/upstream-" \
  --state open \
  --json number,url \
  --jq '.[0].url // empty' 2>/dev/null || true)"

if [[ -n "${EXISTING_PR}" ]]; then
  echo "An open sync PR already exists: ${EXISTING_PR}"
  echo "Skipping new PR creation — resolve the existing PR first."
  output "worktrunk_synced" "false"
  output "pr_created" "false"
  output "pr_url" "${EXISTING_PR}"
  echo "::endgroup::"
  exit 0
fi

# Create a temporary branch from TARGET_BRANCH and merge with conflicts committed
git checkout -b "${SYNC_BRANCH}" "${TARGET_BRANCH}"

# Merge allowing conflicts — commit whatever state results
git merge main --no-edit -m "chore(sync): merge upstream changes (${DATE_STAMP})" || true

# Stage all files (including conflict markers) and commit
git add -A
git commit --no-edit --allow-empty -m "chore(sync): merge upstream changes with conflicts (${DATE_STAMP})" || true

git push origin "${SYNC_BRANCH}"

# Build PR body
PR_BODY="## Upstream Sync — ${DATE_STAMP}

Automated merge of \`upstream/main\` into \`${TARGET_BRANCH}\` encountered conflicts that require manual resolution.

### Conflicting Files

\`\`\`
${CONFLICTING_FILES}
\`\`\`

### Resolution Steps

1. Check out this branch locally:
   \`\`\`bash
   git fetch origin ${SYNC_BRANCH}
   git checkout ${SYNC_BRANCH}
   \`\`\`
2. Search for conflict markers (\`<<<<<<<\`) and resolve each file
3. Stage resolved files: \`git add <file>\`
4. Commit: \`git commit\`
5. Push and merge this PR into \`${TARGET_BRANCH}\`

### Context

- Upstream SHA: \`${UPSTREAM_SHA:0:12}\`
- Sync date: ${DATE_STAMP}
"

# Write PR body to a temp file to avoid shell escaping issues
PR_BODY_FILE="$(mktemp)"
echo "${PR_BODY}" > "${PR_BODY_FILE}"

PR_URL="$(gh pr create \
  --base "${TARGET_BRANCH}" \
  --head "${SYNC_BRANCH}" \
  --title "chore(sync): merge upstream changes (${DATE_STAMP})" \
  --body-file "${PR_BODY_FILE}" \
  --label "sync" 2>&1 || true)"

rm -f "${PR_BODY_FILE}"

# Extract URL from gh output (it prints the URL on success)
if [[ "${PR_URL}" == http* ]]; then
  echo "Created sync PR: ${PR_URL}"
  output "worktrunk_synced" "false"
  output "pr_created" "true"
  output "pr_url" "${PR_URL}"
else
  echo "::warning::Failed to create PR. gh output: ${PR_URL}"
  # Try without the label in case it doesn't exist
  PR_URL="$(gh pr create \
    --base "${TARGET_BRANCH}" \
    --head "${SYNC_BRANCH}" \
    --title "chore(sync): merge upstream changes (${DATE_STAMP})" \
    --body-file /dev/stdin <<< "${PR_BODY}" 2>&1 || true)"

  if [[ "${PR_URL}" == http* ]]; then
    echo "Created sync PR (without label): ${PR_URL}"
    output "worktrunk_synced" "false"
    output "pr_created" "true"
    output "pr_url" "${PR_URL}"
  else
    echo "::error::Failed to create sync PR. Output: ${PR_URL}"
    output "worktrunk_synced" "false"
    output "pr_created" "false"
    output "pr_url" ""
    exit 1
  fi
fi

echo "::endgroup::"

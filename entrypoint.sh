#!/usr/bin/env bash
set -euo pipefail

: "${GITHUB_URL:=https://github.com}"
: "${RUNNER_SCOPE:=org}"      # "org" or "repo"
: "${RUNNER_OWNER:?RUNNER_OWNER must be set (org or owner)}"
: "${RUNNER_TOKEN:?RUNNER_TOKEN registration token must be set}"
: "${RUNNER_NAME:=$(hostname)}"
: "${RUNNER_LABELS:=arm64,linux}"
: "${RUNNER_WORKDIR:=/actions-runner/_work}"

GITHUB_PAT="${GITHUB_PAT:-}"

cd /actions-runner

api_base() {
  if [ "$RUNNER_SCOPE" = "repo" ]; then
    if [ -z "${RUNNER_REPO:-}" ]; then
      echo "RUNNER_REPO must be set for repo-scoped runner (owner/repo)" >&2
      exit 1
    fi
    echo "repos/${RUNNER_OWNER}/${RUNNER_REPO}"
  else
    echo "orgs/${RUNNER_OWNER}"
  fi
}

register_runner() {
  if [ -z "${RUNNER_TOKEN:-}" ]; then
    echo "RUNNER_TOKEN is empty" >&2
    exit 1
  fi

  echo "Configuring runner for $GITHUB_URL (scope=$RUNNER_SCOPE)..."
  ./config.sh --unattended \
              --url "${GITHUB_URL}/${RUNNER_OWNER}${ [ "$RUNNER_SCOPE" = "repo" ] && echo "/${RUNNER_REPO}" || echo "" }" \
              --token "${RUNNER_TOKEN}" \
              --name "${RUNNER_NAME}" \
              --labels "${RUNNER_LABELS}" \
              --work "${RUNNER_WORKDIR}"
}

build_target_url() {
  if [ "$RUNNER_SCOPE" = "repo" ]; then
    echo "${GITHUB_URL}/${RUNNER_OWNER}/${RUNNER_REPO}"
  else
    echo "${GITHUB_URL}/orgs/${RUNNER_OWNER}"
  fi
}

cleanup() {
  echo "Shutdown signal received. Attempting to remove runner from GitHub..."

  if ./config.sh remove --unattended --token "${RUNNER_TOKEN:-}" 2>/dev/null; then
    echo "Runner removed using config.sh remove"
  else
    echo "config.sh remove failed (token likely expired). Attempting API removal using GITHUB_PAT..."
    if [ -z "${GITHUB_PAT:-}" ]; then
      echo "No GITHUB_PAT provided; cannot remove runner via API. Exiting." >&2
      exit 0
    fi

    API_BASE=$(api_base)
    if [ "$RUNNER_SCOPE" = "repo" ]; then
      LIST_URL="https://api.github.com/repos/${RUNNER_OWNER}/${RUNNER_REPO}/actions/runners"
      DELETE_URL_TEMPLATE="https://api.github.com/repos/${RUNNER_OWNER}/${RUNNER_REPO}/actions/runners"
    else
      LIST_URL="https://api.github.com/orgs/${RUNNER_OWNER}/actions/runners"
      DELETE_URL_TEMPLATE="https://api.github.com/orgs/${RUNNER_OWNER}/actions/runners"
    fi

    runner_id=$(curl -sS -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github+json" "$LIST_URL" \
      | jq -r --arg NAME "$RUNNER_NAME" '.runners[] | select(.name == $NAME) | .id' | head -n1)

    if [ -z "$runner_id" ] || [ "$runner_id" = "null" ]; then
      echo "Runner id not found via API; nothing to delete."
    else
      echo "Deleting runner id $runner_id via API..."
      curl -sS -X DELETE -H "Authorization: token ${GITHUB_PAT}" -H "Accept: application/vnd.github+json" \
        "${DELETE_URL_TEMPLATE}/${runner_id}" || echo "API deletion call failed (non-zero exit)"
      echo "API deletion attempted."
    fi
  fi
  exit 0
}

trap 'cleanup' SIGINT SIGTERM

TARGET_URL="$(build_target_url)"

echo "Registering runner at $TARGET_URL"
./config.sh --unattended --url "${TARGET_URL}" --token "${RUNNER_TOKEN}" --name "${RUNNER_NAME}" --labels "${RUNNER_LABELS}" --work "${RUNNER_WORKDIR}"

./run.sh &
RUN_PID=$!

wait $RUN_PID
cleanup

#!/bin/bash
# Set up a self-hosted GitHub Actions runner for YOUR copy of swiftdc, one
# step at a time. Nothing happens without a "y".
#
# Usage: Tools/ci/setup-runner.sh [--service] [--dir <path>] [--remove]
#   --service   also install the runner as a login service (always on)
#   --dir       where the runner lives (default: ~/actions-runner-swiftdc)
#   --remove    unregister the runner, clear the repository variable, and
#               say what is left on disk
#
# Why self-hosted: GitHub's hosted macOS images carry an older Swift than
# the fixtures need (see Tools/ci/environment.sh), so the enforcing suite
# cannot run there. Your own Mac has the right toolchain.
#
# What this does, in order:
#   1. checks this machine (Tools/ci/environment.sh);
#   2. checks who can make the runner execute code (see docs/CI.md);
#   3. downloads GitHub's runner and verifies its SHA-256 against the
#      one GitHub publishes for that release;
#   4. registers it to the repository with the label `swiftdc`;
#   5. sets the repository variable SWIFTDC_SELF_HOSTED=true, which is
#      what makes .github/workflows/ci.yml use it;
#   6. starts it (or installs the service).
set -euo pipefail

runner_dir="$HOME/actions-runner-swiftdc"
service=0
remove=0
while [ $# -gt 0 ]; do
    case "$1" in
        --service) service=1 ;;
        --remove) remove=1 ;;
        --dir) runner_dir="$2"; shift ;;
        -h|--help) sed -n '2,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift
done

here=$(cd "$(dirname "$0")" && pwd)
say() { printf '\n== %s\n' "$1"; }
confirm() {
    printf '%s [y/N] ' "$1"
    read -r answer </dev/tty || answer=""
    [ "$answer" = "y" ] || [ "$answer" = "Y" ]
}

command -v gh >/dev/null || { echo "The GitHub CLI is required: brew install gh, then gh auth login." >&2; exit 1; }
gh auth status >/dev/null 2>&1 || { echo "Not signed in to GitHub: run gh auth login." >&2; exit 1; }
repo=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
visibility=$(gh repo view --json visibility --jq .visibility)
echo "Repository: $repo ($visibility)"

if [ "$remove" -eq 1 ]; then
    say "Remove the runner"
    if [ -x "$runner_dir/config.sh" ]; then
        (cd "$runner_dir" && ./svc.sh stop 2>/dev/null; ./svc.sh uninstall 2>/dev/null; true)
        token=$(gh api -X POST "repos/$repo/actions/runners/remove-token" --jq .token)
        (cd "$runner_dir" && ./config.sh remove --token "$token")
    else
        echo "No runner in $runner_dir."
    fi
    gh variable delete SWIFTDC_SELF_HOSTED --repo "$repo" 2>/dev/null || true
    echo "The repository no longer asks for a self-hosted runner."
    echo "Left on disk, yours to delete: $runner_dir"
    exit 0
fi

say "1. This machine"
"$here/environment.sh" || {
    echo "Fix the problems above first. Nothing was changed." >&2
    exit 1
}

say "2. Who can run code on this machine"
cat <<TEXT
A self-hosted runner executes whatever a workflow run tells it to, as your
user, with your files in reach.
  - A push to this repository runs without asking. Only people with write
    access can push.
  - A pull request from a fork can change the workflow it runs. GitHub
    holds such a run until someone with write access approves it, for the
    contributors the repository's approval policy covers.
TEXT
if [ "$visibility" = "PUBLIC" ]; then
    policy=$(gh api "repos/$repo/actions/permissions/fork-pr-contributor-approval" --jq .approval_policy 2>/dev/null || echo unknown)
    echo "This repository is public. Its approval policy is: $policy"
    if [ "$policy" != "all_external_contributors" ]; then
        cat <<TEXT
With that policy, someone whose pull request was merged before can run
code here without approval. "all_external_contributors" holds every fork
pull request until you approve it, and never asks about your own pushes.
TEXT
        if confirm "Set the policy to all_external_contributors?"; then
            gh api -X PUT "repos/$repo/actions/permissions/fork-pr-contributor-approval" \
                -f approval_policy=all_external_contributors >/dev/null
            echo "Set."
        else
            confirm "Continue with the policy as it is?" || { echo "Stopped. Nothing was installed."; exit 1; }
        fi
    fi
    echo "Read a fork's changes to .github/ and Tools/ before you approve its run."
fi

say "3. Download GitHub's runner"
release=$(gh api repos/actions/runner/releases/latest)
tag=$(printf '%s' "$release" | python3 -c 'import json,sys; print(json.load(sys.stdin)["tag_name"])')
version=${tag#v}
asset="actions-runner-osx-arm64-$version.tar.gz"
expected=$(printf '%s' "$release" | python3 -c '
import json, re, sys
body = json.load(sys.stdin)["body"]
found = re.search(r"osx-arm64 -->([0-9a-f]{64})", body)
print(found.group(1) if found else "")')
[ -n "$expected" ] || { echo "GitHub's release notes for $tag carry no SHA-256 for $asset; not downloading." >&2; exit 1; }
echo "Release $tag, file $asset (about 200 MB), from github.com/actions/runner"
echo "Published SHA-256: $expected"
if [ -x "$runner_dir/config.sh" ]; then
    echo "A runner is already unpacked in $runner_dir; keeping it."
else
    confirm "Download and unpack it into $runner_dir?" || { echo "Stopped. Nothing was installed."; exit 1; }
    mkdir -p "$runner_dir"
    gh release download "$tag" --repo actions/runner --pattern "$asset" --dir "$runner_dir" --clobber
    actual=$(shasum -a 256 "$runner_dir/$asset" | awk '{print $1}')
    if [ "$actual" != "$expected" ]; then
        rm -f "$runner_dir/$asset"
        echo "SHA-256 mismatch: got $actual. The download was removed." >&2
        exit 1
    fi
    echo "SHA-256 matches."
    tar -xzf "$runner_dir/$asset" -C "$runner_dir"
    rm -f "$runner_dir/$asset"
fi

say "4. Register it to $repo"
if [ -f "$runner_dir/.runner" ]; then
    echo "Already registered."
else
    confirm "Register this Mac as a runner for $repo, labelled swiftdc?" || { echo "Stopped. The runner is unpacked but not registered."; exit 1; }
    token=$(gh api -X POST "repos/$repo/actions/runners/registration-token" --jq .token)
    (cd "$runner_dir" && ./config.sh --unattended --url "https://github.com/$repo" --token "$token" \
        --name "$(scutil --get LocalHostName 2>/dev/null || hostname -s)" --labels swiftdc --replace)
fi

say "5. Tell the workflow to use it"
if confirm "Set the repository variable SWIFTDC_SELF_HOSTED=true?"; then
    gh variable set SWIFTDC_SELF_HOSTED --body true --repo "$repo"
    echo "Set. Delete it (or run this script with --remove) to go back to the hosted runner."
else
    echo "Not set: the workflow will keep using GitHub's hosted runner."
fi

say "6. Start it"
if [ "$service" -eq 1 ]; then
    if confirm "Install it as a login service, running whenever you are logged in?"; then
        (cd "$runner_dir" && ./svc.sh install && ./svc.sh start)
        echo "Running as a service. Stop it with: (cd $runner_dir && ./svc.sh stop)"
    fi
else
    cat <<TEXT
Start it when you want CI to run, and stop it with Ctrl-C:

    (cd $runner_dir && ./run.sh)

A push made while it is stopped waits in the queue until it starts.
For an always-on runner, run this script again with --service.
TEXT
fi
echo
echo "Done. Each run prints its toolchain first (Tools/ci/environment.sh), so two runs can be compared."

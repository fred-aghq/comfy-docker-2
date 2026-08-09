#!/bin/bash

# custom_nodes is bind-mounted from the host, so its dependencies can't be
# baked into the image and get installed here instead.

cd /ComfyUI/custom_nodes || exit 0

for dir in */ ; do
    [ -d "$dir" ] || continue

    # Opt-in: set UPDATE_CUSTOM_NODES=1 (e.g. in an instance's instance.env)
    # to git pull every custom node before installing its requirements. Off
    # by default so a node pinned to a specific commit, or one with local
    # edits, isn't touched without asking.
    if [ "${UPDATE_CUSTOM_NODES:-0}" = "1" ] && [ -d "$dir/.git" ]; then
        echo "Updating $dir"
        # --ff-only so a node with local commits or a diverged history fails
        # loudly instead of merging or rebasing on the user's behalf.
        ( cd "$dir" && git pull --ff-only ) || echo "Update failed for $dir, leaving it as-is."
    fi

    if [ -f "$dir/requirements.txt" ]; then
        echo "Installing requirements in $dir"
        # Subshell so a failure here can't leave the loop in the wrong
        # directory. If a node's requirements.txt trips uv's stricter parsing,
        # plain `pip install` is still available in the venv as a fallback.
        ( cd "$dir" && uv pip install -r requirements.txt )
    else
        echo "No requirements.txt in $dir, skipping."
    fi
done

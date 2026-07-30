#!/bin/bash

# custom_nodes is bind-mounted from the host, so its dependencies can't be
# baked into the image and get installed here instead.

cd /ComfyUI/custom_nodes || exit 0

for dir in */ ; do
    [ -d "$dir" ] || continue

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

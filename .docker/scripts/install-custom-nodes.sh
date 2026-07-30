#!/bin/bash

cd /ComfyUI/custom_nodes

for dir in */ ; do
    # Check if it's a directory
    if [ -d "$dir" ]; then
        echo "Entering directory: $dir"
        cd "$dir" || continue

        # Check if requirements.txt exists
        if [ -f "requirements.txt" ]; then
            echo "Installing requirements in $dir"
            # If a node's requirements.txt trips uv's stricter parsing, plain
            # `pip install` is still available in the venv as a fallback.
            uv pip install -r requirements.txt
        else
            echo "No requirements.txt in $dir, skipping."
        fi

        # Go back to the parent directory
        cd ..
    fi
done

#!/bin/bash
set -uo pipefail

# Everything ComfyUI needs is baked into the image, so this only has to
# reconcile the bind-mounted directories and start the app.

# Bind mounts hide whatever the image shipped at that path, so restore any
# missing defaults from the pristine copy. Existing files are never clobbered.
seed_defaults() {
    local src="$1" dst="$2"
    [ -d "$src" ] || return 0
    mkdir -p "$dst"
    cp -rn "$src/." "$dst/" 2>/dev/null || true
}

seed_defaults /opt/comfyui-defaults/custom_nodes /ComfyUI/custom_nodes
seed_defaults /opt/comfyui-defaults/input /ComfyUI/input

# Only lay down the models directory structure when there's nothing there, so
# an existing models library doesn't collect ComfyUI's placeholder files.
if [ -z "$(ls -A /ComfyUI/models 2>/dev/null)" ]; then
    seed_defaults /opt/comfyui-defaults/models /ComfyUI/models
fi

# Custom nodes come from the host, so their dependencies can't be baked in.
# uv makes this cheap when everything is already satisfied; set
# SKIP_CUSTOM_NODE_INSTALL=1 for a faster start once you're settled.
if [ "${SKIP_CUSTOM_NODE_INSTALL:-0}" != "1" ]; then
    /install-custom-nodes.sh
fi

# onnx / onnxruntime-gpu: not declared by any custom node's own requirements.txt,
# but several depend on them anyway — comfyui_controlnet_aux's DWPose falls back
# to a slow CPU path without onnxruntime's GPU providers, and WanVideoWrapper's
# FantasyPortrait nodes (fantasyportrait/pd_fgc/face_utils.py) import both
# directly without listing either as a dependency. Installed here rather than
# in the Dockerfile because /opt/venv is a named volume that survives image
# rebuilds — baking it into the image only helps on a fresh volume. It also
# has to run after install-custom-nodes.sh above: comfyui-easy-use's
# requirements.txt pulls in plain (CPU-only) onnxruntime, which installs its
# files over onnxruntime-gpu's if it runs second. Reinstalling here every
# start guarantees the GPU build's files are the ones left on disk.
uv pip install onnx onnxruntime-gpu --reinstall-package onnxruntime-gpu

# Asking for SageAttention when the image was built without it produces a
# confusing traceback from deep inside ComfyUI, so say what's actually wrong.
if [[ "${COMFY_COMMANDLINE_SWITCHES:-}" == *--use-sage-attention* ]] \
   && ! python -c "import sageattention" 2>/dev/null; then
    echo "ERROR: --use-sage-attention is set, but SageAttention isn't installed." >&2
    echo "       This image was built without it, which happens when" >&2
    echo "       TORCH_CUDA_ARCH_LIST is empty. Set it in .env for your GPU (see" >&2
    echo "       the GPU architecture table in the README) and rebuild:" >&2
    echo "         docker compose up -d --build" >&2
    echo "       Or remove --use-sage-attention from this instance's instance.env." >&2
    exit 1
fi

cd /ComfyUI || exit 1

# Deliberately unquoted: COMFY_COMMANDLINE_SWITCHES holds several
# space-separated flags, and quoting it would hand ComfyUI one long argument
# instead of separate switches.
# shellcheck disable=SC2086
exec python main.py --listen 0.0.0.0 ${COMFY_COMMANDLINE_SWITCHES:-}

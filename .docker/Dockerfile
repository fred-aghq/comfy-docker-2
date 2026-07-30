ARG CUDA_BASE_IMAGE
FROM ${CUDA_BASE_IMAGE} AS cuda

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USERNAME=ubuntu
ARG PYTHON_VERSION=3.12.3


# Create or reuse group and user.
# Ubuntu-based images ship with an 'ubuntu' user at 1000:1000, so a naive
# groupadd/useradd fails when the host UID/GID matches. This handles all cases:
#   - UID/GID 1000 + USERNAME=ubuntu  → no-op (already exists)
#   - UID/GID 1000 + different name   → renames the existing user/group
#   - Non-1000 UID/GID               → creates fresh user/group
RUN if getent group ${GROUP_ID} > /dev/null 2>&1; then \
        EXISTING_GROUP=$(getent group ${GROUP_ID} | cut -d: -f1); \
        { [ "$EXISTING_GROUP" != "${USERNAME}" ] && groupmod -n ${USERNAME} "$EXISTING_GROUP" || true; }; \
    else \
        groupadd --gid ${GROUP_ID} ${USERNAME}; \
    fi && \
    if getent passwd ${USER_ID} > /dev/null 2>&1; then \
        EXISTING_USER=$(getent passwd ${USER_ID} | cut -d: -f1); \
        { [ "$EXISTING_USER" != "${USERNAME}" ] && usermod -l ${USERNAME} -d /home/${USERNAME} -m "$EXISTING_USER" || true; }; \
    else \
        useradd --uid ${USER_ID} --gid ${GROUP_ID} --create-home ${USERNAME}; \
    fi && \
    usermod -aG sudo ${USERNAME}



# Python itself comes from uv as a prebuilt binary, so none of the CPython
# build dependencies are needed here. What's left: a toolchain for compiling
# SageAttention and custom nodes, git for cloning them, and ffmpeg for
# ComfyUI's video nodes.
RUN export DEBIAN_FRONTEND=noninteractive &&\
    apt update && apt install --no-install-recommends -y \
    build-essential curl wget git \
    ffmpeg && \
    rm -rf /var/lib/apt/lists/*

ARG UV_VERSION=latest
COPY --from=ghcr.io/astral-sh/uv:${UV_VERSION} /uv /uvx /usr/local/bin/

# Python and the virtualenv live outside /home so no bind mount or named
# volume can shadow them — the image is the environment.
ENV UV_PYTHON_INSTALL_DIR=/opt/uv/python
ENV VIRTUAL_ENV=/opt/venv
ENV PATH="${VIRTUAL_ENV}/bin:/home/${USERNAME}/.local/bin:$PATH"
ENV COMFYUI_PATH=/ComfyUI

# --seed puts a real pip in the venv, so anything expecting `pip` still works.
# setuptools is explicit because Python 3.12+ venvs no longer seed it, and
# SageAttention's build needs it.
RUN uv python install ${PYTHON_VERSION} && \
    uv venv --python ${PYTHON_VERSION} --seed ${VIRTUAL_ENV} && \
    uv pip install setuptools wheel

# ComfyUI itself, pinned. Bump COMFYUI_REF and rebuild to upgrade.
ARG COMFYUI_REF=master
RUN git clone https://github.com/comfyanonymous/ComfyUI.git /ComfyUI && \
    git -C /ComfyUI checkout --detach ${COMFYUI_REF}

ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu130
RUN uv pip install torch torchvision torchaudio --extra-index-url ${PYTORCH_INDEX_URL}

RUN uv pip install -r /ComfyUI/requirements.txt && \
    uv pip install ninja

# SageAttention, compiled here rather than on first boot. TORCH_CUDA_ARCH_LIST
# is required because there's no GPU to detect during a build — see the GPU
# architecture table in the README. Leave it empty to skip SageAttention
# entirely (and drop --use-sage-attention from that instance's switches).
ARG TORCH_CUDA_ARCH_LIST
ARG SAGEATTENTION_REF=main
RUN if [ -n "${TORCH_CUDA_ARCH_LIST}" ]; then \
        git clone https://github.com/thu-ml/SageAttention.git /tmp/sageattention && \
        git -C /tmp/sageattention checkout --detach ${SAGEATTENTION_REF} && \
        cd /tmp/sageattention && \
        TORCH_CUDA_ARCH_LIST="${TORCH_CUDA_ARCH_LIST}" uv pip install --no-build-isolation . && \
        rm -rf /tmp/sageattention; \
    else \
        echo "TORCH_CUDA_ARCH_LIST is empty — skipping SageAttention build."; \
    fi

# The mutable ComfyUI directories get bind-mounted over at runtime, which hides
# whatever shipped in them. Keep a pristine copy so the entrypoint can restore
# anything the mount hides (ComfyUI's own custom nodes, example input, the
# models directory layout).
RUN mkdir -p /opt/comfyui-defaults && \
    cp -r /ComfyUI/custom_nodes /ComfyUI/input /ComfyUI/models /opt/comfyui-defaults/ 2>/dev/null || true

COPY ./.docker/scripts/postinstall.sh /postinstall.sh
COPY ./.docker/scripts/install-custom-nodes.sh /install-custom-nodes.sh
RUN chmod +x /postinstall.sh /install-custom-nodes.sh && \
    chown -R ${USER_ID}:${GROUP_ID} /ComfyUI /opt/venv /opt/comfyui-defaults

USER ${USERNAME}

ARG PORT=8188
EXPOSE ${PORT}
CMD ["/postinstall.sh"]

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

ENV UV_PYTHON_INSTALL_DIR=/home/${USERNAME}/.local/share/uv/python
ENV VIRTUAL_ENV=/home/${USERNAME}/.venv
ENV PATH="${VIRTUAL_ENV}/bin:/home/${USERNAME}/.local/bin:$PATH"
ENV COMFYUI_PATH=/ComfyUI

# --seed puts a real pip in the venv, so anything expecting `pip` still works.
# setuptools is explicit because Python 3.12+ venvs no longer seed it, and
# SageAttention's setup.py needs it.
RUN uv python install ${PYTHON_VERSION} && \
    uv venv --python ${PYTHON_VERSION} --seed ${VIRTUAL_ENV} && \
    uv pip install setuptools wheel

RUN mkdir -p /temp-data && chown -R ${USERNAME} /temp-data
RUN chown -R ${USERNAME} /home/${USERNAME}

ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu130

COPY ./.docker/scripts/postinstall.sh /postinstall.sh
COPY ./.docker/scripts/install-custom-nodes.sh /install-custom-nodes.sh
RUN chmod +x /postinstall.sh && chown ${USER_ID}:${GROUP_ID} /postinstall.sh
RUN chmod +x /install-custom-nodes.sh && chown ${USER_ID}:${GROUP_ID} /install-custom-nodes.sh
RUN chown -R ${USER_ID}:${GROUP_ID} /temp-data
USER ${USERNAME}
RUN uv pip install --target=/tmp/builtime-pip-install torch torchvision torchaudio --extra-index-url ${PYTORCH_INDEX_URL}

ARG PORT=8188
EXPOSE ${PORT}
CMD ["/postinstall.sh"]

ARG CUDA_BASE_IMAGE=nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04
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



RUN export DEBIAN_FRONTEND=noninteractive &&\
    apt update && apt install -y \
    software-properties-common build-essential curl \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget \
    llvm libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
    libffi-dev liblzma-dev git

RUN export DEBIAN_FRONTEND=noninteractive &&\
    apt update && apt install -y ffmpeg

RUN git clone https://github.com/pyenv/pyenv.git /home/${USERNAME}/.pyenv && \
    export PYENV_ROOT="/home/${USERNAME}/.pyenv" && \
    export PATH="$PYENV_ROOT/bin:$PATH" && \
    eval "$(pyenv init --path)" && \
    pyenv install ${PYTHON_VERSION} && \
    pyenv global ${PYTHON_VERSION}

ENV PYENV_ROOT="/home/${USERNAME}/.pyenv"
ENV PATH="$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH"
ENV PATH="/home/${USERNAME}/.local/bin:$PATH"
ENV COMFYUI_PATH=/ComfyUI

RUN mkdir -p /temp-data && chown -R ${USERNAME} /temp-data
RUN chown -R ${USERNAME} /home/${USERNAME}

FROM cuda AS comfy-install

# Switch to the new user
USER ${USERNAME}

FROM comfy-install AS final-steps

ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USERNAME=ubuntu
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu128

USER root
COPY ./.docker/scripts/postinstall.sh /postinstall.sh
COPY ./.docker/scripts/install-custom-nodes.sh /install-custom-nodes.sh
RUN chmod +x /postinstall.sh && chown ${USER_ID}:${GROUP_ID} /postinstall.sh
RUN chmod +x /install-custom-nodes.sh && chown ${USER_ID}:${GROUP_ID} /install-custom-nodes.sh
RUN chown -R ${USER_ID}:${GROUP_ID} /temp-data
USER ${USERNAME}
RUN pip install --target=/tmp/builtime-pip-install torch torchvision torchaudio --extra-index-url ${PYTORCH_INDEX_URL}

ARG PORT=8188
EXPOSE ${PORT}
CMD ["/postinstall.sh"]

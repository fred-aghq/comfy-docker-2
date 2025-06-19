FROM nvidia/cuda:12.8.1-cudnn-devel-ubuntu22.04
ARG USER_ID=1000
ARG GROUP_ID=1000
ARG USERNAME=ubuntu


# Create group and user
RUN groupadd --gid ${GROUP_ID} ${USERNAME} && \
    useradd --uid ${USER_ID} --gid ${GROUP_ID} --create-home ${USERNAME} && \
    usermod -aG sudo ${USERNAME}



RUN export DEBIAN_FRONTEND=noninteractive &&\
    apt update && apt install -y \
    software-properties-common build-essential curl \
    libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev wget \
    llvm libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev \
    libffi-dev liblzma-dev git
RUN git clone https://github.com/pyenv/pyenv.git /home/${USERNAME}/.pyenv && \
    export PYENV_ROOT="/home/${USERNAME}/.pyenv" && \
    export PATH="$PYENV_ROOT/bin:$PATH" && \
    eval "$(pyenv init --path)" && \
    pyenv install 3.12.3 && \
    pyenv global 3.12.3
RUN apt remove --purge -y build-essential git && apt autoremove -y && apt clean

ENV PYENV_ROOT="/home/${USERNAME}/.pyenv"
ENV PATH="$PYENV_ROOT/shims:$PYENV_ROOT/bin:$PATH"

COPY ./postinstall.sh /postinstall.sh
RUN chmod +x /postinstall.sh

# Switch to the new user
USER ${USERNAME}

CMD ["/postinstall.sh"]

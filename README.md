## Why Yet Another ComfyUI Docker Setup?
I wanted to roll my own, mostly to try and build SageAttention.

You may not find this useful. It's also not the most space-efficient.

## Requirements
1. Docker / Docker Desktop - https://www.docker.com/
2. Nvidia Container Toolkit - https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html

## Architecture

This repository supports running multiple, independent ComfyUI instances — each with its own CUDA, Python, and PyTorch versions — while sharing a single AI models directory on the host.

```
comfy-docker-2/
├── instances/
│   └── default/                          # One directory per ComfyUI instance
│       ├── Dockerfile                    # Instance-specific build (CUDA, Python, PyTorch)
│       └── instance.env                  # Instance-specific runtime config
├── .docker/
│   ├── scripts/
│   │   ├── postinstall.sh                # Shared entrypoint script
│   │   └── install-custom-nodes.sh       # Shared custom-node installer
│   ├── Dockerfile.comfyui-mini           # Optional ComfyUI Mini UI
│   └── ngrok/                            # Optional ngrok tunnel config
├── docker-compose.yml                    # Service definitions (one per instance)
├── docker-compose.ngrok.yml              # Optional ngrok overlay
├── .env.dist                             # Global config template (UID, GID, models path)
└── README.md
```

**Key concepts:**
- **Global config** (`.env`): User identity (`UID`, `GID`, `USERNAME`) and the shared `MODELS_HOST_PATH`. Applies to all instances.
- **Instance config** (`instances/<name>/instance.env`): Per-instance runtime container settings (e.g., `COMFY_COMMANDLINE_SWITCHES`). Host-side settings like ports and paths go in `.env` — see below.
- **Instance Dockerfile** (`instances/<name>/Dockerfile`): Each instance defines its own CUDA base image, Python version, and PyTorch build. Build args at the top of the Dockerfile control these versions.
- **Namespaced volumes**: Each instance gets its own `<name>-home-data` and `<name>-temp-data` Docker volumes, keeping pip caches, pyenv installations, and sentinel files completely isolated.
- **Shared models**: All instances bind-mount the same `MODELS_HOST_PATH` to `/ComfyUI/models`.

## Setup
1. `cp .env.dist .env`
2. Set values in `.env` (UID, GID, USERNAME, MODELS_HOST_PATH, and per-instance host settings like `DEFAULT_COMFY_HOST_PATH` and `DEFAULT_HOST_PORT`)
3. Review/edit `instances/default/instance.env` for instance-specific runtime settings (e.g., `COMFY_COMMANDLINE_SWITCHES`)
4. `git clone https://github.com/comfyanonymous/ComfyUI.git`
5. `docker compose up -d`

> By default the container will install all of comfy's dependencies, torch etc., and compile SageAttention once its up and running.
>
> It's gonna take a while.

## Reinstall Everything (per instance)
1. `docker compose down -v` — this destroys all instance volumes. When you bring the container up again, all of its dependencies will be gone and freshly installed.

> Note: try restarting and/or rebuilding the container first — the `<name>-temp-data` and `<name>-home-data` named volumes store installed pip packages so it might save you some time if that fixes it first.

## Adding a New Instance

To add a second (or third, etc.) ComfyUI instance with its own independent environment:

### 1. Create the instance directory

```sh
cp -r instances/default instances/my-new-instance
```

### 2. Customise the Dockerfile

Edit `instances/my-new-instance/Dockerfile`. The build args at the top control the core dependencies:

```dockerfile
ARG CUDA_BASE_IMAGE=nvidia/cuda:12.6.0-cudnn-devel-ubuntu22.04   # Change CUDA version
# ...
ARG PYTHON_VERSION=3.11.9                                         # Change Python version
# ...
ARG PYTORCH_INDEX_URL=https://download.pytorch.org/whl/cu126      # Match CUDA version
```

You can also make deeper changes (add/remove system packages, change the build flow entirely) — the Dockerfile is fully self-contained per instance.

### 3. Customise instance.env

Edit `instances/my-new-instance/instance.env` for runtime container settings:

```env
# Different CLI switches
COMFY_COMMANDLINE_SWITCHES=
```

Then add the host-side settings to your `.env` file:

```env
# ── Instance: my-new-instance ────────────────────────────────────────
MY_NEW_INSTANCE_COMFY_HOST_PATH=./ComfyUI-nightly
MY_NEW_INSTANCE_HOST_PORT=8189
```

> **Why `.env` and not `instance.env`?** Docker Compose only reads `.env` (and shell environment) when resolving variables in the compose file itself (volume mounts, port mappings, build args). The `env_file` directive only sets variables inside the running container.

### 4. Add the service to docker-compose.yml

Add a new service block to `docker-compose.yml`. Copy the `comfyui-default` block and adjust:

```yaml
services:
  # ... existing comfyui-default block ...

  comfyui-my-new-instance:
    build:
      context: .
      dockerfile: ./instances/my-new-instance/Dockerfile
      args:
        USER_ID: ${UID}
        GROUP_ID: ${GID}
        USERNAME: ${USERNAME}
    env_file:
      - ./instances/my-new-instance/instance.env
    user: "${UID}:${GID}"
    working_dir: /ComfyUI
    volumes:
      - ${MY_NEW_INSTANCE_COMFY_HOST_PATH:-./ComfyUI}:/ComfyUI
      - my-new-instance-home-data:/home/${USERNAME}
      - my-new-instance-temp-data:/temp-data
      - ${MODELS_HOST_PATH:-./ComfyUI/models}:/ComfyUI/models
    deploy:
      resources:
        reservations:
          devices:
            - capabilities: [gpu]
    ports:
      - ${MY_NEW_INSTANCE_HOST_PORT:-8189}:8188
    restart: unless-stopped
    networks:
      internal:

volumes:
  # ... existing volumes ...
  my-new-instance-temp-data:
  my-new-instance-home-data:
```

**Important things to note:**
- The volume names **must** be unique per instance (e.g., `my-new-instance-home-data`).
- The `HOST_PORT` variable in the `ports` mapping must use an instance-specific name (e.g., `MY_NEW_INSTANCE_HOST_PORT`) defined in `.env`.
- All instances share the same `MODELS_HOST_PATH` bind mount and `internal` network.

### 5. Clone ComfyUI (if using a separate app directory)

If your new instance uses a different `COMFY_HOST_PATH`:

```sh
git clone https://github.com/comfyanonymous/ComfyUI.git ComfyUI-nightly
```

### 6. Build and run

```sh
# Build and start only the new instance
docker compose up -d comfyui-my-new-instance

# Or build and start everything
docker compose up -d
```

## Future Enhancements
### ngrok (WIP)
I've added an ngrok container definition to suit my needs; at present, you'll need to comment out the traffic policy stuff in docker-compose.ngrok.yml, or add your own traffic policy yml file.

`docker-compose -f docker-compose.yml -f docker-compose.ngrok.yml up -d`

> Note: The ngrok overlay currently proxies `comfyui-default`. To tunnel a different instance, update the target URL in `docker-compose.ngrok.yml`.

### Slim down the image
- can we throw away the CUDA development image and switch it for the runtime image once sage is built?

### Specify the CUDA/Torch (i forget) Arch Env Var
- I want to try this in docker to see if sageattention can be compiled at build time

### QoL/Misc.
- bit more customisation over directories/custom directories:
- ✅ configurable models/ path bind mount - point docker to an existing ComfyUI/models dir
- ✅ multiple independent ComfyUI instances with decoupled dependencies
- different "modes"
- idk, open to suggestions - open an issue <3

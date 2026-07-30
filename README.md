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
│   ├── default/                          # One directory per ComfyUI instance
│   │   └── instance.env                  # Instance-specific runtime config
│   └── legacy/
│       └── instance.env
├── .docker/
│   ├── Dockerfile                        # Shared image build (parameterised per instance)
│   ├── scripts/
│   │   ├── postinstall.sh                # Shared entrypoint script
│   │   └── install-custom-nodes.sh       # Shared custom-node installer
│   └── Dockerfile.comfyui-mini           # Optional ComfyUI Mini UI
├── docker-compose.yml                    # Service definitions (one per instance)
├── docker-compose.ngrok.yml              # Optional ngrok overlay
├── .env.dist                             # Global config template (UID, GID, models path)
└── README.md
```

**Key concepts:**
- **Global config** (`.env`): User identity (`UID`, `GID`, `USERNAME`) and the shared `MODELS_HOST_PATH`. Applies to all instances.
- **Instance config** (`instances/<name>/instance.env`): All per-instance settings live here — both host-side settings (paths, ports) and runtime container settings (e.g., `COMFY_COMMANDLINE_SWITCHES`). Host-side variable names are instance-prefixed (e.g., `DEFAULT_COMFY_HOST_PATH`) so they don't collide when all instance files are merged into `.env`.
- **Shared Dockerfile** (`.docker/Dockerfile`): All instances build from the same Dockerfile. Each instance picks its own CUDA base image, Python version, and PyTorch build via the `build.args` on its service in `docker-compose.yml`. An instance that needs a genuinely different build flow can still point its service's `build.dockerfile` at its own file.
- **Namespaced volumes**: Each instance gets its own `<name>-home-data` and `<name>-temp-data` Docker volumes, keeping pip caches, pyenv installations, and sentinel files completely isolated.
- **Shared models**: All instances bind-mount the same `MODELS_HOST_PATH` to `/ComfyUI/models`.
- **Profiles**: Each instance declares a Compose profile matching its name, so `docker compose up` starts only the instance(s) you've selected rather than everything defined in the file. See [Switching between instances](#switching-between-instances).

## Setup
1. Edit `.env.dist` with your global settings (UID, GID, USERNAME, `COMPOSE_PROFILES`, and optionally MODELS_HOST_PATH)
2. Review/edit `instances/default/instance.env` for instance-specific settings (host path, port, CLI switches)
3. Generate `.env` by concatenating global + instance configs:
   ```sh
   cat .env.dist instances/*/instance.env > .env
   ```
4. `git clone https://github.com/comfyanonymous/ComfyUI.git`
5. `docker compose up -d`

> **Re-run step 3** any time you edit `.env.dist` or any `instance.env` file.

> By default the container will install all of comfy's dependencies, torch etc., and compile SageAttention once its up and running.
>
> It's gonna take a while.

## Switching between instances

Every instance declares a Compose profile named after it, so nothing starts unless you ask for it by name. This is what makes `docker compose up -d` mean "start what I'm actually using" instead of "start everything I've ever defined".

**Pick your daily driver** in `.env`:

```env
COMPOSE_PROFILES=default
```

```sh
docker compose up -d          # starts comfyui-default only
```

**Run several side-by-side** — they get different ports (8188, 8189) and separate volumes, but share the same models directory:

```env
COMPOSE_PROFILES=default,legacy
```

```sh
docker compose up -d          # starts both
```

**Switch for one command** without editing `.env` — a `--profile` flag replaces the `.env` selection for that invocation:

```sh
docker compose --profile legacy up -d
docker compose --profile legacy down
```

Commands that target a service by name (`logs`, `exec`, `build`) work regardless of the active profile:

```sh
docker compose logs -f comfyui-legacy
docker compose build comfyui-legacy
```

> Watch your VRAM when running side-by-side — each instance loads its own models into the GPU.

## Reinstall Everything (per instance)
1. `docker compose down -v` — this destroys all instance volumes. When you bring the container up again, all of its dependencies will be gone and freshly installed.

> Note: try restarting and/or rebuilding the container first — the `<name>-temp-data` and `<name>-home-data` named volumes store installed pip packages so it might save you some time if that fixes it first.

## Adding a New Instance

To add a second (or third, etc.) ComfyUI instance with its own independent environment:

### 1. Create the instance directory

```sh
cp -r instances/default instances/my-new-instance
```

### 2. Choose the CUDA / Python / PyTorch versions

All instances build from the shared `.docker/Dockerfile`; the versions are controlled by the `build.args` on the instance's service in `docker-compose.yml` (set in step 4):

```yaml
      args:
        CUDA_BASE_IMAGE: nvidia/cuda:12.6.0-cudnn-devel-ubuntu22.04   # CUDA version
        PYTHON_VERSION: 3.11.9                                        # Python version
        PYTORCH_INDEX_URL: https://download.pytorch.org/whl/cu126     # Match CUDA version
```

If an instance needs deeper changes (different system packages, a different build flow entirely), copy `.docker/Dockerfile` into the instance directory and point the service's `build.dockerfile` at it — everything else keeps working the same way.

### 3. Customise instance.env

Edit `instances/my-new-instance/instance.env` to set the host-side path, port, and any runtime settings:

```env
# ── Host-side settings (used by Docker Compose for interpolation) ────
MY_NEW_INSTANCE_COMFY_HOST_PATH=./ComfyUI-nightly
MY_NEW_INSTANCE_HOST_PORT=8189

# ── Container runtime settings ───────────────────────────────────────
COMFY_COMMANDLINE_SWITCHES=
```

The host-side variable names must be instance-prefixed (matching what you reference in `docker-compose.yml`) because all instance env files are merged into a single `.env`.

### 4. Add the service to docker-compose.yml

Add a new service block to `docker-compose.yml`. Shared settings come from the `*comfyui-base` and `*common-build-args` anchors, so the block only has to state what's specific to this instance:

```yaml
services:
  # ... existing comfyui-default block ...

  comfyui-my-new-instance:
    <<: *comfyui-base
    profiles: ["my-new-instance"]
    build:
      context: .
      dockerfile: ./.docker/Dockerfile
      args:
        <<: *common-build-args
        CUDA_BASE_IMAGE: nvidia/cuda:12.6.0-cudnn-devel-ubuntu22.04
        PYTHON_VERSION: 3.11.9
        PYTORCH_INDEX_URL: https://download.pytorch.org/whl/cu126
    env_file:
      - ./instances/my-new-instance/instance.env
    volumes:
      - ${MY_NEW_INSTANCE_COMFY_HOST_PATH:-./ComfyUI-nightly}:/ComfyUI
      - my-new-instance-home-data:/home/${USERNAME}
      - my-new-instance-temp-data:/temp-data
      - ${MODELS_HOST_PATH:-./ComfyUI/models}:/ComfyUI/models
    ports:
      - ${MY_NEW_INSTANCE_HOST_PORT:-8190}:8188

volumes:
  # ... existing volumes ...
  my-new-instance-temp-data:
  my-new-instance-home-data:
```

`<<: *comfyui-base` supplies `user`, `working_dir`, the GPU reservation, `restart` and `networks`. It deliberately doesn't supply `build`, `volumes` or `ports` — YAML merge keys replace a key outright rather than deep-merging, so anything an instance customises has to be written out in full.

**Important things to note:**
- The **profile name** is how you start this instance: `docker compose --profile my-new-instance up -d`, or add it to `COMPOSE_PROFILES` in `.env`.
- The volume names **must** be unique per instance (e.g., `my-new-instance-home-data`).
- The **host port** must not collide with another instance's (8188 and 8189 are taken by `default` and `legacy`).
- Host-side variable names (`COMFY_HOST_PATH`, `HOST_PORT`) must be instance-prefixed to avoid collisions when merged into `.env`.
- All instances share the same `MODELS_HOST_PATH` bind mount and `internal` network.

### 5. Clone ComfyUI (if using a separate app directory)

If your new instance uses a different `COMFY_HOST_PATH`:

```sh
git clone https://github.com/comfyanonymous/ComfyUI.git ComfyUI-nightly
```

### 6. Regenerate `.env` and build

```sh
# Regenerate .env to pick up the new instance's variables
cat .env.dist instances/*/instance.env > .env

# Build and start only the new instance
docker compose --profile my-new-instance up -d

# Or add it to COMPOSE_PROFILES in .env to start it alongside the others
docker compose up -d
```

## Future Enhancements
### ngrok (WIP)
I've added an ngrok container definition to suit my needs; at present, you'll need to comment out the traffic policy stuff in docker-compose.ngrok.yml, or add your own traffic policy yml file.

`docker-compose -f docker-compose.yml -f docker-compose.ngrok.yml up -d`

> Note: The ngrok overlay currently proxies `comfyui-default`. To tunnel a different instance, update the target URL in `docker-compose.ngrok.yml` — and make sure that instance's profile is active, or there'll be nothing listening at the other end of the tunnel.

### Slim down the image
- can we throw away the CUDA development image and switch it for the runtime image once sage is built?

### Specify the CUDA/Torch (i forget) Arch Env Var
- I want to try this in docker to see if sageattention can be compiled at build time

### QoL/Misc.
- bit more customisation over directories/custom directories:
- ✅ configurable models/ path bind mount - point docker to an existing ComfyUI/models dir
- ✅ multiple independent ComfyUI instances with decoupled dependencies
- ✅ switch between instances / run them side-by-side via Compose profiles
- different "modes"
- idk, open to suggestions - open an issue <3

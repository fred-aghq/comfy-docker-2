## Why Yet Another ComfyUI Docker Setup?
I wanted to roll my own, mostly to try and build SageAttention.

You may not find this useful.

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
│   └── ngrok/
│       └── policy.yaml                   # Optional ngrok traffic policy
├── data/                                 # Your stuff (gitignored)
│   ├── models/                           # Shared across instances
│   └── <instance>/                       # Per-instance mutable dirs
│       ├── custom_nodes/
│       ├── input/
│       ├── output/
│       └── user/                         # Workflows and settings
├── docker-compose.yml                    # Service definitions (one per instance)
├── docker-compose.ngrok.yml              # Optional ngrok overlay
├── .env.dist                             # Global config template (UID, GID, models path)
└── README.md
```

**Key concepts:**
- **Global config** (`.env`): Settings that apply to every instance — user identity (`UID`, `GID`, `USERNAME`), the shared `MODELS_HOST_PATH`, `TORCH_CUDA_ARCH_LIST`, and `COMPOSE_PROFILES`. Create it with `cp .env.dist .env`.
- **Instance runtime config** (`instances/<name>/instance.env`): Per-instance settings passed into the running container (e.g. `COMFY_COMMANDLINE_SWITCHES`). Loaded directly by the service's `env_file`, so no prefixing and no merge step — edit and restart.
- **Instance host-side config**: The host port and data directories are set directly on the instance's service in `docker-compose.yml`, where you can see them next to everything else about that instance.
- **Shared Dockerfile** (`.docker/Dockerfile`): All instances build from the same Dockerfile. Each instance picks its own CUDA images, Python version, PyTorch build and ComfyUI revision via the `build.args` on its service in `docker-compose.yml`. An instance that needs a genuinely different build flow can still point its service's `build.dockerfile` at its own file.
- **Two-stage build**: Compiling happens on the CUDA *devel* image; the image you actually run is built on the matching CUDA *runtime* image with the virtualenv copied across, so the CUDA toolkit and headers don't ship. Each instance sets both `CUDA_BASE_IMAGE` and `CUDA_RUNTIME_IMAGE`, and they must be the same CUDA and Ubuntu version.
- **The image is the environment**: ComfyUI, Python, PyTorch and SageAttention are all built into the image at a pinned `COMFYUI_REF`. Containers start in seconds and every rebuild is reproducible. Upgrading ComfyUI means bumping `COMFYUI_REF` and rebuilding — not `git pull` in a directory Docker happens to be watching.
- **Python via uv**: [uv](https://docs.astral.sh/uv/) installs the requested Python as a prebuilt binary and manages the virtualenv at `/opt/venv`, so `PYTHON_VERSION` can be any version uv publishes without a source build.
- **Only your data is mounted**: `custom_nodes`, `input`, `output` and `user` are bind-mounted per instance from `./data/<instance>/`; `models` is shared. Everything else lives in the image.
- **Profiles**: Each instance declares a Compose profile matching its name, so `docker compose up` starts only the instance(s) you've selected rather than everything defined in the file. See [Switching between instances](#switching-between-instances).

## Setup

1. Create your global config and edit it — UID, GID, USERNAME, `TORCH_CUDA_ARCH_LIST` (see [GPU architecture](#gpu-architecture)), `COMPOSE_PROFILES`, and optionally `MODELS_HOST_PATH`:
   ```sh
   cp .env.dist .env
   ```
2. Create the data directories, so they belong to you rather than to root:
   ```sh
   mkdir -p data/models data/default/{custom_nodes,input,output,user}
   ```
3. Review/edit `instances/default/instance.env` for that instance's runtime settings (CLI switches)
4. Build and start:
   ```sh
   docker compose up -d --build
   ```

> The first build compiles SageAttention, so it's gonna take a while. Every build after that is cached, and containers start in seconds — the long wait no longer happens on every fresh container, only when you change what's in the image.

## GPU architecture

SageAttention is compiled during the image build, and a build has no GPU to detect, so you have to say which architecture to target. Set `TORCH_CUDA_ARCH_LIST` in `.env`:

| GPU generation | Architecture | `TORCH_CUDA_ARCH_LIST` |
|---|---|---|
| RTX 30xx (3060–3090 Ti) | Ampere | `8.6` |
| RTX 40xx (4060–4090) | Ada Lovelace | `8.9` |
| RTX 50xx (5060–5090) | Blackwell | `12.0` |

Also useful: A100 is `8.0`, H100 is `9.0`.

You can target several at once by separating them with semicolons — `8.6;8.9` produces an image that works on both a 3090 and a 4090, at the cost of a longer build and a bigger image.

> Leave `TORCH_CUDA_ARCH_LIST` empty to skip building SageAttention entirely. If you do, also remove `--use-sage-attention` from your instances' `COMFY_COMMANDLINE_SWITCHES`, or ComfyUI won't start.

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

## Pinning ComfyUI versions

`COMFYUI_REF` accepts a tag, a branch name, or a commit SHA — the clone isn't shallow, so any of them work. Both shipped instances are pinned to release tags:

| Instance | `COMFYUI_REF` |
|---|---|
| `default` | `v0.29.0` |
| `legacy` | `v0.19.2` |

> **Prefer tags and SHAs over branch names.** Docker caches the clone layer against the *literal* value of `COMFYUI_REF`, not against what that ref currently points at. Changing `v0.29.0` → `v0.29.1` changes the layer's cache key and re-clones correctly. But leaving it at `master` means the cache key never changes, so rebuilds keep resurrecting whatever master was the last time something invalidated the cache — you get a stale ComfyUI with no indication that's what happened. If you do want to track a branch, force it with `docker compose build --no-cache <service>`.

The same applies to `SAGEATTENTION_REF`, which is pinned to `v2.2.0` in `.docker/Dockerfile`.

## Upgrading and reinstalling

The environment lives in the image, so both are rebuilds rather than volume surgery. Your models, workflows, outputs and custom nodes are in `./data/` and aren't touched by any of this.

**Upgrade ComfyUI** — bump `COMFYUI_REF` on the instance's service in `docker-compose.yml` to a newer tag, then:

```sh
docker compose up -d --build comfyui-default
```

**Rebuild from scratch** (the equivalent of the old `down -v`):

```sh
docker compose build --no-cache comfyui-default
docker compose up -d comfyui-default
```

**Reset a custom node's dependencies** — the one thing still installed at runtime. Remove the node from `./data/<instance>/custom_nodes/` and restart.

> Startup reinstalls custom-node requirements every time, which is quick with uv but not free. Once you're settled, set `SKIP_CUSTOM_NODE_INSTALL=1` in the instance's `instance.env` for faster restarts.

## Migrating from the bind-mounted layout

Earlier versions bind-mounted a whole ComfyUI checkout from the host (`./ComfyUI`, `./ComfyUI-legacy`) and installed dependencies into named volumes at runtime. ComfyUI now lives in the image and only your data is mounted.

**1. Find out what version you're currently on**, so you can pin the instance to it rather than silently jumping forward:

```sh
git -C ComfyUI describe --tags
```

Set that tag as the instance's `COMFYUI_REF` in `docker-compose.yml`. The `legacy` instance ships pinned to `v0.19.2` for exactly this purpose — an existing install moved across unchanged. Upgrade later by bumping the tag, once you know the move itself worked.

**2. Move your data out of the old checkout.** Custom nodes come across as-is, including their `.git` directories, so ComfyUI-Manager keeps working:

```sh
mkdir -p data/models data/legacy/{custom_nodes,input,output,user}

mv ComfyUI/custom_nodes/*  data/legacy/custom_nodes/   2>/dev/null
mv ComfyUI/input/*         data/legacy/input/          2>/dev/null
mv ComfyUI/output/*        data/legacy/output/         2>/dev/null
mv ComfyUI/user/*          data/legacy/user/           2>/dev/null
```

`user/` is the one people forget — it holds your saved workflows and UI settings.

For models, either move them into `data/models/` or leave them where they are and point `MODELS_HOST_PATH` at the existing directory — no need to shuffle a few hundred gigabytes.

**3. Build and start.** Your custom nodes' Python dependencies are installed on first start, so this boot is slower than subsequent ones:

```sh
docker compose up -d --build comfyui-legacy
docker compose logs -f comfyui-legacy
```

**4. Clean up** once you're happy it works:

```sh
docker compose down -v          # removes the now-unused *-home-data / *-temp-data volumes
```

Keep the old `ComfyUI/` checkout around until you've confirmed everything loads — it costs nothing but disk, and it's your rollback.

> **A custom node that used to work may now fail to import.** Previously every dependency landed in one shared site-packages that had accumulated over time; now the image starts from ComfyUI's own requirements plus whatever your nodes declare. A node that quietly relied on a package it never declared will surface that. The fix is normally to add the missing package to that node's `requirements.txt`, or `docker compose exec comfyui-legacy uv pip install <package>` to confirm the diagnosis before making it permanent.

## Adding a New Instance

To add a second (or third, etc.) ComfyUI instance with its own independent environment:

### 1. Create the instance directory

```sh
cp -r instances/default instances/my-new-instance
```

### 2. Choose the CUDA / Python / PyTorch / ComfyUI versions

All instances build from the shared `.docker/Dockerfile`; the versions are controlled by the `build.args` on the instance's service in `docker-compose.yml` (set in step 4):

```yaml
      args:
        CUDA_BASE_IMAGE: nvidia/cuda:12.6.0-cudnn-devel-ubuntu22.04     # builds on this
        CUDA_RUNTIME_IMAGE: nvidia/cuda:12.6.0-cudnn-runtime-ubuntu22.04 # runs on this
        PYTHON_VERSION: 3.11.9                                          # Python version
        PYTORCH_INDEX_URL: https://download.pytorch.org/whl/cu126       # Match CUDA version
        COMFYUI_REF: v0.3.40                                            # Tag, branch or SHA
```

The two CUDA images must be the same CUDA and Ubuntu version — only `devel` vs `runtime` differs. The devel image supplies `nvcc` for compiling SageAttention; the runtime image is what you actually run.

`COMFYUI_REF` is what makes instances genuinely independent — one can sit on the latest release while another stays pinned to an older one your workflows are known to work on. Use a tag or SHA rather than a branch name; see [Pinning ComfyUI versions](#pinning-comfyui-versions).

If an instance needs deeper changes (different system packages, a different build flow entirely), copy `.docker/Dockerfile` into the instance directory and point the service's `build.dockerfile` at it — everything else keeps working the same way.

### 3. Customise instance.env

Edit `instances/my-new-instance/instance.env` with the settings this instance's container should run with:

```env
COMFY_COMMANDLINE_SWITCHES=
```

The app directory and host port aren't set here — they go on the service itself in the next step.

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
        CUDA_RUNTIME_IMAGE: nvidia/cuda:12.6.0-cudnn-runtime-ubuntu22.04
        PYTHON_VERSION: 3.11.9
        PYTORCH_INDEX_URL: https://download.pytorch.org/whl/cu126
        COMFYUI_REF: v0.3.40
    env_file:
      - ./instances/my-new-instance/instance.env
    volumes:
      - ${MODELS_HOST_PATH:-./data/models}:/ComfyUI/models
      - ./data/my-new-instance/custom_nodes:/ComfyUI/custom_nodes
      - ./data/my-new-instance/input:/ComfyUI/input
      - ./data/my-new-instance/output:/ComfyUI/output
      - ./data/my-new-instance/user:/ComfyUI/user
    ports:
      - "8190:8188"
```

`<<: *comfyui-base` supplies `user`, `working_dir`, the GPU reservation, `restart` and `networks`. It deliberately doesn't supply `build`, `volumes` or `ports` — YAML merge keys replace a key outright rather than deep-merging, so anything an instance customises has to be written out in full.

**Important things to note:**
- The **profile name** is how you start this instance: `docker compose --profile my-new-instance up -d`, or add it to `COMPOSE_PROFILES` in `.env`.
- The **host port** must not collide with another instance's (8188 and 8189 are taken by `default` and `legacy`). The container side is always 8188.
- The **data directories** must be this instance's own, so its custom nodes stay independent of the others'.
- All instances share the same `MODELS_HOST_PATH` bind mount and `internal` network.

### 5. Create the instance's data directories

```sh
mkdir -p data/my-new-instance/{custom_nodes,input,output,user}
```

### 6. Build and start

```sh
# Build and start only the new instance
docker compose --profile my-new-instance up -d

# Or add it to COMPOSE_PROFILES in .env to start it alongside the others
docker compose up -d
```

## Remote access via ngrok (optional)

An ngrok overlay exposes one instance through a tunnel:

```sh
docker compose -f docker-compose.yml -f docker-compose.ngrok.yml up -d
```

Set these in `.env`:

```env
NGROK_AUTHTOKEN=your-token-here
NGROK_TARGET_URL=http://comfyui-default:8188   # which instance to tunnel
```

The target instance's profile has to be active, or there'll be nothing listening at the other end of the tunnel.

> **ComfyUI has no authentication of its own** — anything you tunnel is open to whoever finds the URL. `.docker/ngrok/policy.yaml` adds HTTP basic auth as a minimum bar; change the credentials in it before you expose anything. See the [ngrok traffic policy docs](https://ngrok.com/docs/traffic-policy/) for more.

The ngrok inspection UI is on http://localhost:4040.

## CI

`.github/workflows/ci.yml` runs on every pull request:

- **Lint and validate config** (seconds) — compose files resolve, each instance's profile selects exactly its own service, `COMFYUI_REF` is a tag or SHA rather than a branch, `instance.env` files haven't regrown host-side settings, plus shellcheck and hadolint.
- **Build each instance** (~30–60 min) with `TORCH_CUDA_ARCH_LIST` empty, which skips the SageAttention compile but still exercises the base images, apt, uv, the pinned ComfyUI clone, torch, ComfyUI's requirements and the multi-stage copy. Then smoke-tests the image: the interpreter survives the copy into the runtime stage, torch imports, ComfyUI is at the pinned ref and its own imports resolve.

The **full build including SageAttention** is manual — run it from the Actions tab before merging anything that touches the build. It's slow (the compile dominates) and needs most of the runner's disk, so it isn't worth it per-PR. There's a commented-out weekly schedule if you'd rather it ran on its own.

> **CI proves the images build, never that they run.** Every runtime question — whether CUDA is actually available, whether a workflow executes, whether SageAttention is fast — needs a real GPU, and GitHub's free runners don't have one. Treat CI as a regression net for build breakage, and keep testing on your own machine.

## Future Enhancements

### QoL/Misc.
- bit more customisation over directories/custom directories:
- ✅ configurable models/ path bind mount - point docker to an existing ComfyUI/models dir
- ✅ multiple independent ComfyUI instances with decoupled dependencies
- ✅ switch between instances / run them side-by-side via Compose profiles
- ✅ SageAttention compiled at build time via `TORCH_CUDA_ARCH_LIST`
- ✅ ship the CUDA runtime image instead of the devel image
- different "modes"
- idk, open to suggestions - open an issue <3

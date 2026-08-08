# comfy-docker-2

> Note: Original design was mine/written by "hand" but I have done a lot of (planned and supervised) refactoring using Claude. Feel free to call me out on AI slop.

Run multiple ComfyUI instances in Docker — different CUDA, Python, PyTorch and ComfyUI versions side by side, sharing one models directory.

**TL;DR:**

- 🖥️ **Multiple instances** — each with its own CUDA / Python / PyTorch / ComfyUI version, fully isolated
- 🔀 **Switch with one env var**, or run several at once on different ports
- 📦 **One shared models directory** — no duplicating hundreds of GB per instance
- ⚡ **SageAttention compiled at build time** — not on first boot
- 🚀 **Containers start in seconds** — everything is baked into the image; rebuilds are cached and reproducible
- 💾 **Only your data is mounted** — models, custom nodes, workflows and outputs live on the host; the environment lives in the image

> I wanted to roll my own, mostly to try and build SageAttention. It grew a bit. You may still not find this useful <3

## Requirements

1. [Docker / Docker Desktop](https://www.docker.com/)
2. [NVIDIA Container Toolkit](https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html)

## Quickstart

```sh
# 1. Create your config
cp .env.dist .env
```

Edit `.env`: set `UID`/`GID`/`USERNAME` (per the comments), and set `TORCH_CUDA_ARCH_LIST` for your GPU:

| GPU | `TORCH_CUDA_ARCH_LIST` |
|---|---|
| RTX 30xx | `8.6` |
| RTX 40xx | `8.9` |
| RTX 50xx | `12.0` |

(Other cards, multiple architectures, or skipping SageAttention: see [GPU Architecture](https://github.com/fred-aghq/comfy-docker-2/wiki/GPU-Architecture).)

```sh
# 2. Create the data directories (so they belong to you, not root — Docker
#    creates missing bind-mount sources itself, as root, the first time an
#    instance starts)
mkdir -p data/models data/default/{custom_nodes,input,output,user} data/legacy/{custom_nodes,input,output,user}

# 3. Build and start
docker compose up -d --build
```

ComfyUI is on [http://localhost:8188](http://localhost:8188). The first build compiles SageAttention so it takes a while — after that, builds are cached and containers start in seconds.

Already have a ComfyUI install full of models and custom nodes? See [Migrating](https://github.com/fred-aghq/comfy-docker-2/wiki/Migrating-From-the-Bind-Mounted-Layout).

## Switching instances

Each instance has a Compose profile named after it. Pick your daily driver in `.env` with `COMPOSE_PROFILES=default`, then:

```sh
docker compose up -d                        # starts your selected instance(s)
docker compose --profile legacy up -d       # one-off: start a different one
COMPOSE_PROFILES=default,legacy             # in .env: run both side by side
```

More in [Switching Between Instances](https://github.com/fred-aghq/comfy-docker-2/wiki/Switching-Between-Instances).

## Documentation

The in-depth docs live in the [wiki](https://github.com/fred-aghq/comfy-docker-2/wiki):

- [Architecture](https://github.com/fred-aghq/comfy-docker-2/wiki/Architecture) — repo layout and the ideas behind it
- [GPU Architecture](https://github.com/fred-aghq/comfy-docker-2/wiki/GPU-Architecture) — `TORCH_CUDA_ARCH_LIST` in full
- [Switching Between Instances](https://github.com/fred-aghq/comfy-docker-2/wiki/Switching-Between-Instances) — profiles, side-by-side, VRAM notes
- [Adding a New Instance](https://github.com/fred-aghq/comfy-docker-2/wiki/Adding-a-New-Instance) — your own CUDA/Python/PyTorch/ComfyUI combo
- [Upgrading and Pinning](https://github.com/fred-aghq/comfy-docker-2/wiki/Upgrading-and-Pinning) — version pins, rebuilds, why not `master`
- [Migrating From the Bind-Mounted Layout](https://github.com/fred-aghq/comfy-docker-2/wiki/Migrating-From-the-Bind-Mounted-Layout) — moving an existing install in
- [Remote Access with ngrok](https://github.com/fred-aghq/comfy-docker-2/wiki/Remote-Access-with-ngrok) — tunnels, with auth
- [CI](https://github.com/fred-aghq/comfy-docker-2/wiki/CI) — what the checks prove (and what they can't)

## What's next

- ✅ configurable models/ path — point at an existing models dir
- ✅ multiple independent instances with decoupled dependencies
- ✅ switch between instances / run side-by-side via Compose profiles
- ✅ SageAttention compiled at build time
- ✅ ship the CUDA runtime image instead of the devel image
- different "modes"
- more customisation over directories
- idk, open to suggestions - open an issue <3

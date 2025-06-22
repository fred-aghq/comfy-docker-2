## Why Yet Another ComfyUI Docker Setup?
I wanted to roll my own, mostly to try and build SageAttention.

You may not find this useful. It's also not the most space-efficient.

## Requirements
1. Docker / Docker Desktop - https://www.docker.com/
2. Nvidia Container Toolkit - https://docs.nvidia.com/datacenter/cloud-native/container-toolkit/latest/install-guide.html

## Setup
1. `cp .env.dist .env`
2. set values in `.env`
3. `git clone https://github.com/comfyanonymous/ComfyUI.git`
4. `docker compose up -d`

> By default the container will install all of comfy's dependencies, torch etc., and compile SageAttention once its up and running.
> 
> It's gonna take a while.

## Reinstall Everything
1. `docker compose down -v` - this should trash everything except your ComfyUI dir. When you bring the container up again, all of its dependencies will be gone and freshly installed.

> Note: try restarting and/or rebuilding the container first - the temp-data and home-data named volumes store installed pip packages so it might save you some time if that fixes it first.

## Future Enhancements
### Slim down the image
- can we throw away the CUDA development image and switch it for the runtime image once sage is built?

### Specify the CUDA/Torch (i forget) Arch Env Var
- I want to try this in docker to see if sageattention can be compiled at build time

### QoL/Misc.
- bit more customisation over directories/custom directories:
- ✅ configurable models/ path bind mount
- different "modes"
- idk, open to suggestions - open an issue <3
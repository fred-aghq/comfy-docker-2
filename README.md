## Why Yet Another ComfyUI Docker Setup?
I wanted to roll my own, mostly to try and build SageAttention.

You may not find this useful. It's also not the most space-efficient.

## Setup
1. `cp .env.dist .env`
2. set values in `.env`
3. `git clone https://github.com/comfyanonymous/ComfyUI.git`
4. `docker compose up -d`

> By default the container will install all of comfy's dependencies, torch etc., and compile SageAttention.
> 
> It's gonna take a while.

## Reinstall Everything
1. `docker compose down -v` - this should trash everything except your ComfyUI dir. When you bring the container up again, all of its dependencies will be gone and freshly installed.
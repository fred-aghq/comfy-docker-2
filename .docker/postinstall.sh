if [ ! -f "/temp-data/.removeToReinstall" ]; then
    cp -r /tmp/builtime-pip-install/* $PYENV_ROOT/versions/3.12.3/lib/python3.12/site-packages/
    # pip install --pre torch torchvision torchaudio --index-url https://download.pytorch.org/whl/nightly/cu128
    cd /ComfyUI
    pip install -r requirements.txt
    pip install ninja
    cd /temp-data;
    git clone https://github.com/thu-ml/SageAttention.git
    cd SageAttention
    python setup.py install
    /install-custom-nodes.sh
    touch /temp-data/.removeToReinstall
else
    echo "Skipping installation because .removeToReinstall exists."
fi

cd /ComfyUI

python main.py --listen 0.0.0.0 $COMFY_COMMANDLINE_SWITCHES

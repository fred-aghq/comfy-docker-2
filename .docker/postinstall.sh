if [ ! -f "/temp-data/.removeToReinstall" ]; then
    pip install torch torchvision torchaudio --extra-index-url https://download.pytorch.org/whl/cu128
    pip install -r requirements.txt
    touch /temp-data/.removeToReinstall
else
    echo "Skipping installation because .removeToReinstall exists."
fi

python main.py $COMFY_COMMANDLINE_SWITCHES 

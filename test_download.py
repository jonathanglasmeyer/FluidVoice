#!/usr/bin/env python3
import json, sys, traceback, os
from pathlib import Path

# Allow online downloads and enable progress bars
os.environ["HF_HUB_OFFLINE"] = "0"
os.environ["HF_HUB_DISABLE_PROGRESS_BARS"] = "0"

try:
    print(json.dumps({"message": "Preparing Python environment..."}), flush=True)

    from huggingface_hub import snapshot_download
    from tqdm.auto import tqdm
    import time

    print(json.dumps({"message": "Downloading Parakeet v3 model (~600MB)..."}), flush=True)

    cache_dir = Path.home() / ".cache" / "huggingface" / "hub"

    # Download with native tqdm progress (outputs to stderr)
    model_path = snapshot_download(
        repo_id="mlx-community/parakeet-tdt-0.6b-v3",
        cache_dir=str(cache_dir),
        local_files_only=False
    )

    print(json.dumps({"status": "complete", "message": "Download complete!"}), flush=True)
except Exception as e:
    print(json.dumps({"status": "error", "message": str(e)}), flush=True)
    traceback.print_exc()
    sys.exit(1)
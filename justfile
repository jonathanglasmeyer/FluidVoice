# FluidVoice Development Commands

_default:
    @just --list

# Build and run the app
dev:
    rm -f build-output.txt && unbuffer ./build-dev.sh 2>&1 | tee build-output.txt
    FluidVoice-dev.app/Contents/MacOS/FluidVoice

# Build development version only (without running)
build-dev:
    ./build-dev.sh

# Build production release and install to /Applications
release:
    CODE_SIGN_IDENTITY="EFC93994F7FFF5A8EC85E5CD41174673C1EDCD25" ./build.sh
    @echo "📦 Installing to /Applications..."
    @rm -rf /Applications/FluidVoice.app
    @cp -r FluidVoice.app /Applications/
    @echo "✅ FluidVoice installed to /Applications/FluidVoice.app"

# Build production release (without installing)
build-release:
    CODE_SIGN_IDENTITY="EFC93994F7FFF5A8EC85E5CD41174673C1EDCD25" ./build.sh

# Run tests
test:
    swift test --parallel --build-path .build-dev

# Stream app logs
logs:
    /usr/bin/log stream --predicate 'subsystem == "com.fluidvoice.app"' --info

# Run the development app (restart if running)
run:
    pkill -f FluidVoice || true
    FluidVoice-dev.app/Contents/MacOS/FluidVoice

# Kill app processes
kill:
    pkill -f FluidVoice || true

# Reset all Python dependencies (venv, uv cache, MLX models)
reset-deps:
    @echo "🧹 Resetting Python dependencies..."
    @rm -rf ~/Library/Application\ Support/FluidVoice/python_project/ && echo "✅ Deleted Python venv" || echo "⚠️  No Python venv found"
    @rm -rf ~/.cache/uv/ && echo "✅ Deleted uv cache" || echo "⚠️  No uv cache found"
    @rm -rf ~/.cache/huggingface/ && echo "✅ Deleted HuggingFace cache" || echo "⚠️  No HuggingFace cache found"
    @rm -rf ~/.cache/pip && echo "✅ Deleted pip cache" || echo "⚠️  No pip cache found"
    @rm -rf ~/.cache/mlx && echo "✅ Deleted MLX cache" || echo "⚠️  No MLX cache found"
    @echo "🎯 Dependencies reset complete. Restart app to re-download."
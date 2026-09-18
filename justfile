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
    CODE_SIGN_IDENTITY="1916CCA1F909509F44384DFB1768B333BAE721F3" ./build.sh
    @echo "📦 Installing to /Applications..."
    @rm -rf /Applications/FluidVoice.app
    @cp -r FluidVoice.app /Applications/
    @echo "✅ FluidVoice installed to /Applications/FluidVoice.app"

# Build production release (without installing)
build-release:
    CODE_SIGN_IDENTITY="1916CCA1F909509F44384DFB1768B333BAE721F3" ./build.sh

# Run tests
test:
    xcrun swift test --parallel --build-path .build-dev

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

# Delete the Parakeet CoreML model cache (re-downloaded on next launch)
reset-model:
    @rm -rf ~/Library/Application\ Support/FluidAudio/Models/ && echo "✅ Deleted FluidAudio model cache"
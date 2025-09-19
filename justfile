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

# Build production release
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
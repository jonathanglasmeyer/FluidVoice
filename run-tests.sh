#!/bin/bash

# Run just the FluidVoiceAppTests
swift test --filter "FluidVoiceAppTests/test" 2>&1 | grep -E "(Test Case|passed|failed|error:|Executed)"
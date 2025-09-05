#!/bin/bash

# FluidVoice Development Build with Minimal App Bundle
# Test performance impact of proper Bundle.main support vs raw executable

set -e

# Performance monitoring
START_TIME=$(date +%s)

echo "🏗️ Debug build with minimal app bundle..."

# First build the executable (same as build-dev.sh)
./build-dev.sh > /dev/null 2>&1

EXECUTABLE_TIME=$(date +%s)
EXECUTABLE_DURATION=$((EXECUTABLE_TIME - START_TIME))

# Create minimal app bundle structure
echo "📦 Creating minimal app bundle..."
rm -rf FluidVoice-debug.app
mkdir -p FluidVoice-debug.app/Contents/MacOS
mkdir -p FluidVoice-debug.app/Contents/Resources

# Copy executable
cp .build-dev/debug/FluidVoice FluidVoice-debug.app/Contents/MacOS/

# Copy Python scripts (essential for functionality)
cp Sources/parakeet_transcribe_pcm.py FluidVoice-debug.app/Contents/Resources/ 2>/dev/null || true
cp Sources/mlx_semantic_correct.py FluidVoice-debug.app/Contents/Resources/ 2>/dev/null || true
cp Sources/Resources/pyproject.toml FluidVoice-debug.app/Contents/Resources/ 2>/dev/null || true

# Copy UV binary if present
if [ -f "Sources/Resources/bin/uv" ]; then
    mkdir -p FluidVoice-debug.app/Contents/Resources/bin
    cp Sources/Resources/bin/uv FluidVoice-debug.app/Contents/Resources/bin/
fi

# Create minimal Info.plist (essential for Bundle.main)
cat > FluidVoice-debug.app/Contents/Info.plist << 'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>FluidVoice</string>
    <key>CFBundleIdentifier</key>
    <string>com.fluidvoice.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>FluidVoice</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.3.5-dev</string>
    <key>CFBundleVersion</key>
    <string>135</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>FluidVoice needs access to your microphone to record audio for transcription.</string>
</dict>
</plist>
EOF

chmod +x FluidVoice-debug.app/Contents/MacOS/FluidVoice

END_TIME=$(date +%s)
TOTAL_DURATION=$((END_TIME - START_TIME))
BUNDLE_DURATION=$((END_TIME - EXECUTABLE_TIME))

echo "⏱️ Performance Results:"
echo "   Executable build: ${EXECUTABLE_DURATION}s" 
echo "   Bundle creation:  ${BUNDLE_DURATION}s"
echo "   Total time:       ${TOTAL_DURATION}s"
echo ""
echo "✅ Debug app bundle ready at FluidVoice-debug.app"
echo "🎯 Now has proper Bundle.main support!"
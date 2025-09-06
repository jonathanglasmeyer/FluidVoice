#!/bin/bash

# FluidVoice Development Build Script
# Optimized for fast iteration during development

set -e

# Load environment variables from .env file if it exists
if [[ -f .env ]]; then
    echo "📁 Loading environment from .env..."
    set -a  # Automatically export all variables
    source .env
    set +a  # Disable automatic export
    
    if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
        echo "🔐 Code signing identity loaded"
    fi
else
    echo "💡 No .env file found - copy .env.example to .env for code signing"
fi

# Performance monitoring
START_TIME=$(date +%s)

echo "🚀 Fast development build starting..."

# Generate version info quickly (skip git operations in dev)
BUILD_DATE=$(date '+%Y-%m-%d')
GIT_HASH="dev-$(date +%s)"
VERSION="${AUDIO_WHISPER_VERSION:-dev}"

# Create version file from template (fast path)
if [ -f "Sources/VersionInfo.swift.template" ]; then
  sed -e "s/VERSION_PLACEHOLDER/$VERSION/g" \
    -e "s/GIT_HASH_PLACEHOLDER/$GIT_HASH/g" \
    -e "s/BUILD_DATE_PLACEHOLDER/$BUILD_DATE/g" \
    Sources/VersionInfo.swift.template > Sources/VersionInfo.swift
fi

# Set build cache environment
export SWIFT_BUILD_CACHE_PATH="${SWIFT_BUILD_CACHE_PATH:-$HOME/.swift-build-cache}"
mkdir -p "$SWIFT_BUILD_CACHE_PATH"

# Build with optimizations for development
echo "📦 Building with cache at $SWIFT_BUILD_CACHE_PATH..."

# Use all available cores, debug mode for faster compilation
CORE_COUNT=$(sysctl -n hw.logicalcpu)
swift build \
  -c debug \
  --build-path .build-dev \
  -j $CORE_COUNT

BUILD_SUCCESS=$?

if [ $BUILD_SUCCESS -eq 0 ]; then
  echo "📦 Creating development app bundle..."
  
  # Create app bundle structure
  APP_BUNDLE="FluidVoice-dev.app"
  rm -rf "$APP_BUNDLE"
  mkdir -p "$APP_BUNDLE/Contents/MacOS"
  mkdir -p "$APP_BUNDLE/Contents/Resources"
  
  # Copy executable
  cp ".build-dev/debug/FluidVoice" "$APP_BUNDLE/Contents/MacOS/"
  
  # Copy Info.plist
  if [ -f "Info.plist" ]; then
    cp "Info.plist" "$APP_BUNDLE/Contents/"
  fi
  
  # Ensure UV binary is available for Python package management
  UV_BIN_PATH="Sources/Resources/bin/uv"
  if [ ! -f "$UV_BIN_PATH" ]; then
    echo "📦 Downloading UV binary for Python package management..."
    mkdir -p "Sources/Resources/bin"
    
    # Detect architecture for the correct UV binary
    ARCH=$(uname -m)
    if [ "$ARCH" = "arm64" ]; then
      UV_URL="https://github.com/astral-sh/uv/releases/latest/download/uv-aarch64-apple-darwin.tar.gz"
    else
      UV_URL="https://github.com/astral-sh/uv/releases/latest/download/uv-x86_64-apple-darwin.tar.gz"
    fi
    
    # Download and extract UV binary
    curl -L "$UV_URL" | tar -xz -C "Sources/Resources/bin" --strip-components=1
    chmod +x "$UV_BIN_PATH"
    echo "✅ UV binary downloaded and ready"
  fi
  
  # Copy Bundle resources (Python scripts, etc.) first
  BUNDLE_RESOURCES=".build-dev/arm64-apple-macosx/debug/FluidVoice_FluidVoice.bundle"
  if [ -d "$BUNDLE_RESOURCES" ]; then
    echo "📦 Copying bundle resources..."
    cp -r "$BUNDLE_RESOURCES"/* "$APP_BUNDLE/Contents/Resources/"
  fi
  
  # Copy additional Resources directory 
  if [ -d "Sources/Resources" ]; then
    echo "🔗 Copying additional resources..."
    cp -r "Sources/Resources"/* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true
  fi
  
  # Code sign if identity available
  if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    echo "🔐 Code signing development bundle..."
    codesign -s "$CODE_SIGN_IDENTITY" "$APP_BUNDLE" 2>/dev/null || {
      echo "⚠️  Code signing failed, but bundle created"
    }
  fi
  
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  echo "✅ Development build completed in ${DURATION}s"
  echo "🎯 App bundle ready at $APP_BUNDLE"
else
  echo "❌ Build failed!"
  exit 1
fi
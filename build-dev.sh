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

# Clean any existing app bundle to ensure fresh build
APP_BUNDLE="FluidVoice-dev.app"
if [ -d "$APP_BUNDLE" ]; then
  echo "🧹 Cleaning existing app bundle..."
  rm -rf "$APP_BUNDLE"
fi

# Build with optimizations for development
echo "📦 Building with cache at $SWIFT_BUILD_CACHE_PATH..."

# Use all available cores, debug mode for faster compilation
CORE_COUNT=$(sysctl -n hw.logicalcpu)
xcrun swift build \
  -c debug \
  --build-path .build-dev \
  -j $CORE_COUNT

BUILD_SUCCESS=$?

if [ $BUILD_SUCCESS -eq 0 ]; then
  echo "📦 Creating development app bundle..."
  
  # Create app bundle structure
  mkdir -p "$APP_BUNDLE/Contents/MacOS"
  mkdir -p "$APP_BUNDLE/Contents/Resources"
  
  # Copy executable
  cp ".build-dev/debug/FluidVoice" "$APP_BUNDLE/Contents/MacOS/"
  
  # Copy Info.plist
  if [ -f "Info.plist" ]; then
    cp "Info.plist" "$APP_BUNDLE/Contents/"
  fi
  
  # Copy SwiftPM resource bundle
  BUNDLE_RESOURCES=".build-dev/arm64-apple-macosx/debug/FluidVoice_FluidVoice.bundle"
  if [ -d "$BUNDLE_RESOURCES" ]; then
    echo "📦 Copying bundle resources..."
    cp -r "$BUNDLE_RESOURCES"/* "$APP_BUNDLE/Contents/Resources/"
  fi
  
  # Code sign if identity available
  if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
    echo "🔐 Code signing development bundle..."
    if [ -f "FluidVoice.entitlements" ]; then
      codesign -s "$CODE_SIGN_IDENTITY" --force --options=runtime --timestamp --entitlements FluidVoice.entitlements "$APP_BUNDLE" 2>/dev/null || {
        echo "⚠️  Code signing with entitlements failed, but bundle created"
      }
    else
      codesign -s "$CODE_SIGN_IDENTITY" "$APP_BUNDLE" 2>/dev/null || {
        echo "⚠️  Code signing failed, but bundle created"
      }
    fi
  fi
  
  END_TIME=$(date +%s)
  DURATION=$((END_TIME - START_TIME))
  echo "✅ Development build completed in ${DURATION}s"
  echo "🎯 App bundle ready at $APP_BUNDLE"
else
  echo "❌ Build failed!"
  exit 1
fi
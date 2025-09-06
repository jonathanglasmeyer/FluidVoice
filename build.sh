#!/bin/bash

# FluidVoice Release Build Script
# For development, use: swift build && swift run
# This script is for creating distributable releases

# Parse command line arguments
NOTARIZE=false
while [[ $# -gt 0 ]]; do
  case $1 in
  --notarize)
    NOTARIZE=true
    shift
    ;;
  *)
    echo "Unknown option: $1"
    echo "Usage: $0 [--notarize]"
    exit 1
    ;;
  esac
done

# Load environment variables from .env file if it exists
if [[ -f .env ]]; then
    echo "📁 Loading environment from .env..."
    set -a  # Automatically export all variables
    source .env
    set +a  # Disable automatic export
    
    if [[ -n "$CODE_SIGN_IDENTITY" ]]; then
        echo "🔐 Code signing identity loaded from .env"
    fi
fi

# Generate version info
GIT_HASH=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
BUILD_DATE=$(date '+%Y-%m-%d')

# Read version from VERSION file or use environment variable
DEFAULT_VERSION=$(cat VERSION | tr -d '[:space:]')
VERSION="${AUDIO_WHISPER_VERSION:-$DEFAULT_VERSION}"

echo "🎙️ Building FluidVoice version $VERSION..."

# Update Info.plist with current version
if [ -f "Info.plist" ]; then
  echo "Updating Info.plist version to $VERSION..."
  # Update CFBundleShortVersionString
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" Info.plist 2>/dev/null ||
    sed -i '' "s|<key>CFBundleShortVersionString</key>[[:space:]]*<string>[^<]*</string>|<key>CFBundleShortVersionString</key><string>$VERSION</string>|" Info.plist

  # Update CFBundleVersion (remove dots for build number)
  BUILD_NUMBER="${VERSION//./}"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" Info.plist 2>/dev/null ||
    sed -i '' "s|<key>CFBundleVersion</key>[[:space:]]*<string>[^<]*</string>|<key>CFBundleVersion</key><string>$BUILD_NUMBER</string>|" Info.plist
fi

# Clean previous builds (but preserve cache)
rm -rf .build/apple/Products/Release
rm -rf FluidVoice.app
rm -f Sources/AudioProcessorCLI
# Preserve .build directory for incremental builds

# Create version file from template
if [ -f "Sources/VersionInfo.swift.template" ]; then
  sed -e "s/VERSION_PLACEHOLDER/$VERSION/g" \
    -e "s/GIT_HASH_PLACEHOLDER/$GIT_HASH/g" \
    -e "s/BUILD_DATE_PLACEHOLDER/$BUILD_DATE/g" \
    Sources/VersionInfo.swift.template >Sources/VersionInfo.swift
  echo "Generated VersionInfo.swift from template"
else
  echo "Warning: VersionInfo.swift.template not found, using fallback"
  cat >Sources/VersionInfo.swift <<EOF
import Foundation

struct VersionInfo {
    static let version = "$VERSION"
    static let gitHash = "$GIT_HASH"
    static let buildDate = "$BUILD_DATE"
    
    static var displayVersion: String {
        if gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            return "\(version) (\(shortHash))"
        }
        return version
    }
    
    static var fullVersionInfo: String {
        var info = "FluidVoice \(version)"
        if gitHash != "unknown" && !gitHash.isEmpty {
            let shortHash = String(gitHash.prefix(7))
            info += " • \(shortHash)"
        }
        if buildDate.count > 0 {
            info += " • \(buildDate)"
        }
        return info
    }
}
EOF
fi

# Set build cache for performance
export SWIFT_BUILD_CACHE_PATH="${SWIFT_BUILD_CACHE_PATH:-$HOME/.swift-build-cache}"
mkdir -p "$SWIFT_BUILD_CACHE_PATH"

# Build for release with optimizations
echo "📦 Building for release with cache at $SWIFT_BUILD_CACHE_PATH..."
CORE_COUNT=$(sysctl -n hw.logicalcpu)
swift build \
  -c release \
  --arch arm64 --arch x86_64 \
  -j $CORE_COUNT \
  -Xswiftc -enforce-exclusivity=unchecked \
  -Xswiftc -whole-module-optimization

if [ $? -ne 0 ]; then
  echo "❌ Build failed!"
  exit 1
fi

# Create app bundle
echo "Creating app bundle..."
mkdir -p FluidVoice.app/Contents/MacOS
mkdir -p FluidVoice.app/Contents/Resources
mkdir -p FluidVoice.app/Contents/Resources/bin

# Set build number for Info.plist
BUILD_NUMBER="${VERSION//./}"

# Copy executable (universal binary)
cp .build/apple/Products/Release/FluidVoice FluidVoice.app/Contents/MacOS/

# Copy Python scripts for Parakeet and MLX support
if [ -f "Sources/parakeet_transcribe_pcm.py" ]; then
  cp Sources/parakeet_transcribe_pcm.py FluidVoice.app/Contents/Resources/
  echo "Copied Parakeet PCM Python script"
else
  echo "⚠️ parakeet_transcribe_pcm.py not found, Parakeet functionality will not work"
fi

if [ -f "Sources/mlx_semantic_correct.py" ]; then
  cp Sources/mlx_semantic_correct.py FluidVoice.app/Contents/Resources/
  echo "Copied MLX semantic correction Python script"
else
  echo "⚠️ mlx_semantic_correct.py not found, MLX semantic correction will not work"
fi

# Bundle uv (Apple Silicon). Download if needed, prefer repo copy, else fall back to system uv
if [ -f "Sources/Resources/bin/uv" ]; then
  cp Sources/Resources/bin/uv FluidVoice.app/Contents/Resources/bin/uv
  chmod +x FluidVoice.app/Contents/Resources/bin/uv
  echo "Bundled uv binary (from repo)"
else
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
  chmod +x "Sources/Resources/bin/uv"
  
  # Now copy to app bundle
  cp Sources/Resources/bin/uv FluidVoice.app/Contents/Resources/bin/uv
  chmod +x FluidVoice.app/Contents/Resources/bin/uv
  echo "✅ UV binary downloaded and bundled"
fi

# Bundle pyproject.toml and uv.lock if present
if [ -f "Sources/Resources/pyproject.toml" ]; then
  cp Sources/Resources/pyproject.toml FluidVoice.app/Contents/Resources/pyproject.toml
  echo "Bundled pyproject.toml"
else
  echo "ℹ️ No pyproject.toml found in Sources/Resources"
fi

# Note: AudioProcessorCLI binary no longer needed - using direct Swift audio processing

# Create proper Info.plist
echo "Creating Info.plist..."
cat >FluidVoice.app/Contents/Info.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
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
    <string>$VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUILD_NUMBER</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSMicrophoneUsageDescription</key>
    <string>FluidVoice needs access to your microphone to record audio for transcription.</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSAppTransportSecurity</key>
    <dict>
        <key>NSExceptionDomains</key>
        <dict>
            <key>api.openai.com</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
            <key>generativelanguage.googleapis.com</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
            <key>huggingface.co</key>
            <dict>
                <key>NSIncludesSubdomains</key>
                <true/>
            </dict>
        </dict>
    </dict>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
</dict>
</plist>
EOF

# Generate app icon from our source image
if [ -f "FluidVoiceIcon.png" ]; then
  ./generate-icons.sh

  # Create proper icns file directly in app bundle
  if command -v iconutil >/dev/null 2>&1; then
    iconutil -c icns FluidVoice.iconset -o FluidVoice.app/Contents/Resources/AppIcon.icns 2>/dev/null || echo "Note: iconutil failed, app will use default icon"
  fi

  # Clean up temporary files
  rm -rf FluidVoice.iconset
  rm -f AppIcon.icns # Remove any stray icns file from root
else
  echo "⚠️ FluidVoiceIcon.png not found, app will use default icon"
fi

# Make executable
chmod +x FluidVoice.app/Contents/MacOS/FluidVoice

# Create entitlements file for hardened runtime
echo "Creating entitlements for hardened runtime..."
cat >FluidVoice.entitlements <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.device.audio-input</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
EOF

# Function to sign the app with a given identity
sign_app() {
  local identity="$1"
  local identity_name="$2"

  if [ -n "$identity_name" ]; then
    echo "🔏 Code signing app with: $identity_name ($identity)"
  else
    echo "🔏 Code signing app with: $identity"
  fi

  # Sign uv binary if present (nested executable)
  if [ -f "FluidVoice.app/Contents/Resources/bin/uv" ]; then
    codesign --force --sign "$identity" --options runtime --entitlements FluidVoice.entitlements FluidVoice.app/Contents/Resources/bin/uv
  fi

  codesign --force --deep --sign "$identity" --options runtime --entitlements FluidVoice.entitlements --identifier "com.fluidvoice.app" FluidVoice.app
  if [ $? -eq 0 ]; then
    echo "🔍 Verifying signature..."
    codesign --verify --verbose FluidVoice.app
    echo "✅ App signed successfully"
    return 0
  else
    echo "❌ Code signing failed"
    return 1
  fi
}

# Optional: Code sign the app (requires Apple Developer account)
SIGNING_IDENTITY=""
SIGNING_NAME=""

if [ -n "$CODE_SIGN_IDENTITY" ]; then
  SIGNING_IDENTITY="$CODE_SIGN_IDENTITY"
else
  # Try to auto-detect Developer ID (use the first one found)
  DETECTED_HASH=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $2}')
  DETECTED_NAME=$(security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | awk '{print $3}' | tr -d '"')
  if [ -n "$DETECTED_HASH" ]; then
    echo "🔍 Auto-detected signing identity: $DETECTED_NAME"
    SIGNING_IDENTITY="$DETECTED_HASH"
    SIGNING_NAME="$DETECTED_NAME"
  fi
fi

if [ -n "$SIGNING_IDENTITY" ]; then
  sign_app "$SIGNING_IDENTITY" "$SIGNING_NAME"
else
  echo "💡 No Developer ID found. App will be unsigned."
  echo "💡 To sign the app, get a Developer ID certificate from Apple Developer Portal."
fi

# Clean up entitlements file
rm -f FluidVoice.entitlements

# Notarization (requires code signing first)
if [ "$NOTARIZE" = true ]; then
  echo ""
  echo "🔐 Starting notarization process..."

  # Check for required environment variables
  if [ -z "$AUDIO_WHISPER_APPLE_ID" ] || [ -z "$AUDIO_WHISPER_APPLE_PASSWORD" ] || [ -z "$AUDIO_WHISPER_TEAM_ID" ]; then
    echo "❌ Notarization requires the following environment variables:"
    echo "   AUDIO_WHISPER_APPLE_ID - Your Apple ID email"
    echo "   AUDIO_WHISPER_APPLE_PASSWORD - App-specific password for notarization"
    echo "   AUDIO_WHISPER_TEAM_ID - Your Apple Developer Team ID"
    echo ""
    echo "To create an app-specific password:"
    echo "1. Go to https://appleid.apple.com/account/manage"
    echo "2. Sign in and go to Security > App-Specific Passwords"
    echo "3. Generate a new password for FluidVoice notarization"
    echo ""
    exit 1
  fi

  # Check if app is signed
  if codesign -dvvv FluidVoice.app 2>&1 | grep -q "Signature=adhoc"; then
    echo "❌ App must be properly signed before notarization (not adhoc signed)"
    echo "Please ensure CODE_SIGN_IDENTITY is set or a Developer ID is available"
    exit 1
  fi

  # Create a zip file for notarization
  echo "Creating zip for notarization..."
  ditto -c -k --keepParent FluidVoice.app FluidVoice.zip

  # Submit for notarization
  echo "📤 Submitting to Apple for notarization..."
  xcrun notarytool submit FluidVoice.zip \
    --apple-id "$AUDIO_WHISPER_APPLE_ID" \
    --password "$AUDIO_WHISPER_APPLE_PASSWORD" \
    --team-id "$AUDIO_WHISPER_TEAM_ID" \
    --wait 2>&1 | tee notarization.log

  # Check if notarization was successful
  if grep -q "status: Accepted" notarization.log; then
    # Staple the notarization ticket to the app
    echo "📎 Stapling notarization ticket..."
    xcrun stapler staple FluidVoice.app

    if [ $? -eq 0 ]; then
      echo "✅ Notarization ticket stapled successfully!"
    else
      echo "⚠️ Failed to staple notarization ticket, but app is notarized"
    fi
  else
    echo "❌ Notarization failed. Check notarization.log for details"
    echo ""
    echo "Common issues:"
    echo "- Ensure your Apple ID has accepted all developer agreements"
    echo "- Check that your app-specific password is correct"
    echo "- Verify your Team ID is correct"
    exit 1
  fi

  # Clean up
  rm -f FluidVoice.zip
  rm -f notarization.log
fi

echo "✅ Build complete!"
echo ""
open -R FluidVoice.app

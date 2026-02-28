#!/bin/bash
# Build llama.cpp and whisper.cpp as XCFrameworks for iOS
# This script compiles the C libraries with Metal support and packages them
# for inclusion in the Xcode project.
#
# Prerequisites:
#   - Xcode (with iOS SDK)
#   - CMake (brew install cmake)
#   - git
#
# Usage: ./build-xcframeworks.sh [--clean]

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$PROJECT_ROOT/build-xcfw"
OUTPUT_DIR="$PROJECT_ROOT/Frameworks"

LLAMA_CPP_REPO="https://github.com/ggml-org/llama.cpp.git"
WHISPER_CPP_REPO="https://github.com/ggml-org/whisper.cpp.git"

# Pin to known-good commits
LLAMA_CPP_TAG="b5200"  # Update as needed
WHISPER_CPP_TAG="v1.7.4"

if [ "${1:-}" = "--clean" ]; then
    echo "Cleaning build directory..."
    rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
fi

mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"

echo "=== Building XCFrameworks ==="
echo "Build dir: $BUILD_DIR"
echo "Output dir: $OUTPUT_DIR"
echo ""

# -------------------------------------------------------
# LLAMA.CPP
# -------------------------------------------------------
echo "--- llama.cpp ---"

LLAMA_SRC="$BUILD_DIR/llama.cpp"
if [ ! -d "$LLAMA_SRC" ]; then
    echo "Cloning llama.cpp ($LLAMA_CPP_TAG)..."
    git clone --depth 1 --branch "$LLAMA_CPP_TAG" "$LLAMA_CPP_REPO" "$LLAMA_SRC" 2>/dev/null || \
    git clone --depth 1 "$LLAMA_CPP_REPO" "$LLAMA_SRC"
fi

# Build for iOS device (arm64)
echo "Building llama.cpp for iOS device..."
cmake -S "$LLAMA_SRC" -B "$BUILD_DIR/llama-ios" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DLLAMA_METAL=ON \
    -DLLAMA_ACCELERATE=ON \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    2>/dev/null

cmake --build "$BUILD_DIR/llama-ios" --config Release -- -sdk iphoneos 2>/dev/null

# Build for iOS simulator (arm64)
echo "Building llama.cpp for iOS simulator..."
cmake -S "$LLAMA_SRC" -B "$BUILD_DIR/llama-sim" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DLLAMA_METAL=ON \
    -DLLAMA_ACCELERATE=ON \
    -DLLAMA_BUILD_EXAMPLES=OFF \
    -DLLAMA_BUILD_TESTS=OFF \
    -DLLAMA_BUILD_SERVER=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    2>/dev/null

cmake --build "$BUILD_DIR/llama-sim" --config Release -- -sdk iphonesimulator 2>/dev/null

echo "Creating llama.xcframework..."
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/llama-ios/Release-iphoneos/libllama.a" \
    -headers "$LLAMA_SRC/include" \
    -library "$BUILD_DIR/llama-sim/Release-iphonesimulator/libllama.a" \
    -headers "$LLAMA_SRC/include" \
    -output "$OUTPUT_DIR/llama.xcframework" \
    2>/dev/null

echo "[OK] llama.xcframework built"

# -------------------------------------------------------
# WHISPER.CPP
# -------------------------------------------------------
echo ""
echo "--- whisper.cpp ---"

WHISPER_SRC="$BUILD_DIR/whisper.cpp"
if [ ! -d "$WHISPER_SRC" ]; then
    echo "Cloning whisper.cpp ($WHISPER_CPP_TAG)..."
    git clone --depth 1 --branch "$WHISPER_CPP_TAG" "$WHISPER_CPP_REPO" "$WHISPER_SRC" 2>/dev/null || \
    git clone --depth 1 "$WHISPER_CPP_REPO" "$WHISPER_SRC"
fi

# Build for iOS device
echo "Building whisper.cpp for iOS device..."
cmake -S "$WHISPER_SRC" -B "$BUILD_DIR/whisper-ios" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DWHISPER_METAL=ON \
    -DWHISPER_ACCELERATE=ON \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    2>/dev/null

cmake --build "$BUILD_DIR/whisper-ios" --config Release -- -sdk iphoneos 2>/dev/null

# Build for iOS simulator
echo "Building whisper.cpp for iOS simulator..."
cmake -S "$WHISPER_SRC" -B "$BUILD_DIR/whisper-sim" \
    -G Xcode \
    -DCMAKE_SYSTEM_NAME=iOS \
    -DCMAKE_OSX_DEPLOYMENT_TARGET=17.0 \
    -DCMAKE_OSX_ARCHITECTURES=arm64 \
    -DWHISPER_METAL=ON \
    -DWHISPER_ACCELERATE=ON \
    -DWHISPER_BUILD_EXAMPLES=OFF \
    -DWHISPER_BUILD_TESTS=OFF \
    -DBUILD_SHARED_LIBS=OFF \
    2>/dev/null

cmake --build "$BUILD_DIR/whisper-sim" --config Release -- -sdk iphonesimulator 2>/dev/null

echo "Creating whisper.xcframework..."
xcodebuild -create-xcframework \
    -library "$BUILD_DIR/whisper-ios/Release-iphoneos/libwhisper.a" \
    -headers "$WHISPER_SRC/include" \
    -library "$BUILD_DIR/whisper-sim/Release-iphonesimulator/libwhisper.a" \
    -headers "$WHISPER_SRC/include" \
    -output "$OUTPUT_DIR/whisper.xcframework" \
    2>/dev/null

echo "[OK] whisper.xcframework built"

# -------------------------------------------------------
echo ""
echo "=== XCFrameworks ready at $OUTPUT_DIR ==="
ls -lh "$OUTPUT_DIR"
echo ""
echo "Next steps:"
echo "1. Add llama.xcframework and whisper.xcframework to your Xcode project"
echo "2. Enable LLAMA_CPP_AVAILABLE and WHISPER_CPP_AVAILABLE Swift flags"
echo "3. Link Metal.framework, Accelerate.framework"

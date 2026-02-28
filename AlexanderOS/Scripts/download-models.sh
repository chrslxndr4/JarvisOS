#!/bin/bash
# Download AI models for Alexander OS development
# Run this to pre-download models instead of waiting for in-app download

set -euo pipefail

MODELS_DIR="${1:-./Models}"
mkdir -p "$MODELS_DIR"

QWEN_URL="https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf"
WHISPER_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-base.en.bin"

QWEN_FILE="$MODELS_DIR/qwen2.5-1.5b-instruct-q4_k_m.gguf"
WHISPER_FILE="$MODELS_DIR/ggml-base.en.bin"

echo "=== Alexander OS Model Downloader ==="
echo ""

if [ -f "$QWEN_FILE" ]; then
    echo "[OK] Qwen 2.5 1.5B already downloaded"
else
    echo "[>>] Downloading Qwen 2.5 1.5B Instruct Q4_K_M (~1 GB)..."
    curl -L --progress-bar -o "$QWEN_FILE" "$QWEN_URL"
    echo "[OK] Qwen 2.5 1.5B downloaded"
fi

echo ""

if [ -f "$WHISPER_FILE" ]; then
    echo "[OK] Whisper base.en already downloaded"
else
    echo "[>>] Downloading Whisper base.en (~148 MB)..."
    curl -L --progress-bar -o "$WHISPER_FILE" "$WHISPER_URL"
    echo "[OK] Whisper base.en downloaded"
fi

echo ""
echo "=== All models ready ==="
ls -lh "$MODELS_DIR"

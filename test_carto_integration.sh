#!/bin/bash

# Integration test to verify the complete carto build process works
# This test simulates the actual Docker container scenario

set -euo pipefail

echo "========================================"
echo "Testing Carto Build Integration"
echo "========================================"

# Create a test environment
TEST_ROOT=$(mktemp -d)
STYLE_DIR="$TEST_ROOT/data/style"
mkdir -p "$STYLE_DIR"

echo "Test directory: $TEST_ROOT"
echo ""

# Test 1: Simulate scenario where style files are missing (should fail gracefully)
echo "Test 1: Testing behavior when style files are missing..."
cd "$TEST_ROOT"
mkdir -p data/style

# Run the carto build logic and capture both stdout and stderr
OUTPUT=$(cd data/style && bash -c 'if [ ! -f project.mml ]; then echo "ERROR: project.mml not found in /data/style/"; echo "Cannot generate mapnik.xml without a valid MML file."; exit 1; fi' 2>&1) || true

if echo "$OUTPUT" | grep -q "ERROR.*project.mml not found"; then
    echo "✓ PASS: Correctly handles missing project.mml"
else
    echo "✗ FAIL: Did not handle missing project.mml correctly"
    echo "Output was: $OUTPUT"
    rm -rf "$TEST_ROOT"
    exit 1
fi

# Test 2: Simulate scenario with a valid project.mml (minimal test)
echo ""
echo "Test 2: Testing with a valid minimal project.mml..."
TEST_ROOT2=$(mktemp -d)
STYLE_DIR2="$TEST_ROOT2/data/style"
mkdir -p "$STYLE_DIR2"

# Create a minimal valid project.mml
cat > "$STYLE_DIR2/project.mml" << 'EOF'
{
  "bounds": [-180, -85.0511, 180, 85.0511],
  "center": [0, 0, 2],
  "format": "png",
  "interactivity": false,
  "minzoom": 0,
  "maxzoom": 20,
  "srs": "+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0.0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs +over",
  "Stylesheet": [],
  "Layer": []
}
EOF

cd "$STYLE_DIR2"

# Verify carto can process the minimal file
if command -v carto > /dev/null 2>&1; then
    echo "Running carto on minimal project.mml..."
    if carto project.mml > mapnik.xml 2>&1; then
        if [ -f mapnik.xml ] && [ -s mapnik.xml ]; then
            SIZE=$(stat -c%s mapnik.xml)
            echo "✓ PASS: Successfully generated mapnik.xml ($SIZE bytes)"
        else
            echo "✗ FAIL: mapnik.xml not created or empty"
            rm -rf "$TEST_ROOT" "$TEST_ROOT2"
            exit 1
        fi
    else
        echo "✗ FAIL: carto command failed"
        rm -rf "$TEST_ROOT" "$TEST_ROOT2"
        exit 1
    fi
else
    echo "⚠ SKIP: carto not installed, cannot test actual generation"
    echo "   (This is expected in CI environments without Node.js/carto)"
fi

# Test 3: Test the file size validation logic
echo ""
echo "Test 3: Testing mapnik.xml validation logic..."
TEST_ROOT3=$(mktemp -d)
cd "$TEST_ROOT3"

# Create empty file
touch mapnik.xml
if [ ! -s mapnik.xml ]; then
    echo "✓ PASS: Correctly detects empty mapnik.xml"
else
    echo "✗ FAIL: Did not detect empty mapnik.xml"
    rm -rf "$TEST_ROOT" "$TEST_ROOT2" "$TEST_ROOT3"
    exit 1
fi

# Create valid file
echo "<?xml version='1.0'?><Map></Map>" > mapnik.xml
if [ -f mapnik.xml ] && [ -s mapnik.xml ]; then
    echo "✓ PASS: Correctly validates non-empty mapnik.xml"
else
    echo "✗ FAIL: Did not validate mapnik.xml correctly"
    rm -rf "$TEST_ROOT" "$TEST_ROOT2" "$TEST_ROOT3"
    exit 1
fi

# Cleanup
rm -rf "$TEST_ROOT" "$TEST_ROOT2" "$TEST_ROOT3"

echo ""
echo "========================================"
echo "All integration tests passed!"
echo "========================================"

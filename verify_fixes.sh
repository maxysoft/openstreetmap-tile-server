#!/bin/bash

# Verification script for Mapnik styles and tirex-batch fixes
# Tests the Docker image without requiring a database

set -e

IMAGE_NAME="${1:-test-osm-tile-server:local}"

echo "========================================"
echo "Verifying fixes for Mapnik and tirex-batch"
echo "Image: $IMAGE_NAME"
echo "========================================"
echo ""

# Test 1: Verify Mapnik plugin directory exists
echo "Test 1: Checking Mapnik plugin directory..."
ARCH=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "dpkg --print-architecture")
case "$ARCH" in
  amd64) ARCH_TUPLE="x86_64-linux-gnu" ;;
  arm64) ARCH_TUPLE="aarch64-linux-gnu" ;;
  armhf) ARCH_TUPLE="arm-linux-gnueabihf" ;;
  i386) ARCH_TUPLE="i386-linux-gnu" ;;
  *) ARCH_TUPLE="${ARCH}-linux-gnu" ;;
esac
MAPNIK_PLUGIN_DIR="/usr/lib/${ARCH_TUPLE}/mapnik/4.0/input"
if docker run --rm --entrypoint bash "$IMAGE_NAME" -c "test -d $MAPNIK_PLUGIN_DIR"; then
    echo "✓ PASS: Mapnik plugin directory exists at $MAPNIK_PLUGIN_DIR"
else
    echo "✗ FAIL: Mapnik plugin directory not found at $MAPNIK_PLUGIN_DIR"
    exit 1
fi

# Test 2: Verify PostGIS plugin exists
echo "Test 2: Checking PostGIS plugin..."
if docker run --rm --entrypoint bash "$IMAGE_NAME" -c "test -f $MAPNIK_PLUGIN_DIR/postgis.input"; then
    echo "✓ PASS: PostGIS plugin exists"
else
    echo "✗ FAIL: PostGIS plugin not found"
    exit 1
fi

# Test 3: Verify tirex configuration has correct plugin directory
echo "Test 3: Checking tirex configuration..."
PLUGINDIR=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "grep ^plugindir /etc/tirex/renderer/mapnik.conf | cut -d= -f2")
if [ "$PLUGINDIR" == "$MAPNIK_PLUGIN_DIR" ]; then
    echo "✓ PASS: Tirex configuration has correct plugin directory ($PLUGINDIR)"
else
    echo "✗ FAIL: Tirex plugin directory is incorrect: $PLUGINDIR (expected: $MAPNIK_PLUGIN_DIR)"
    exit 1
fi

# Test 4: Verify tirex-batch command includes bbox
echo "Test 4: Checking tirex-batch bbox parameter..."
if docker run --rm --entrypoint bash "$IMAGE_NAME" -c "grep -q 'bbox=-180,-90,180,90' /run.sh"; then
    echo "✓ PASS: tirex-batch command includes bbox parameter"
else
    echo "✗ FAIL: tirex-batch command missing bbox parameter"
    exit 1
fi

# Test 5: Verify openstreetmap-carto version
echo "Test 5: Checking openstreetmap-carto version..."
VERSION=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "grep -m1 '## \[v5.9.0\]' /home/renderer/src/openstreetmap-carto-backup/CHANGELOG.md")
if [ -n "$VERSION" ]; then
    echo "✓ PASS: openstreetmap-carto v5.9.0 is installed"
else
    echo "✗ FAIL: openstreetmap-carto v5.9.0 not found"
    exit 1
fi

# Test 6: Verify tirex map configuration
echo "Test 6: Checking tirex map configuration..."
if docker run --rm --entrypoint bash "$IMAGE_NAME" -c "test -f /etc/tirex/renderer/mapnik/default.conf"; then
    echo "✓ PASS: Tirex map configuration exists"
else
    echo "✗ FAIL: Tirex map configuration not found"
    exit 1
fi

# Test 7: Verify mapfile path in map configuration
echo "Test 7: Checking mapfile path..."
MAPFILE=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "grep ^mapfile /etc/tirex/renderer/mapnik/default.conf | cut -d= -f2")
if [ "$MAPFILE" == "/home/renderer/src/openstreetmap-carto/mapnik.xml" ]; then
    echo "✓ PASS: Mapfile path is correct"
else
    echo "✗ FAIL: Mapfile path is incorrect: $MAPFILE"
    exit 1
fi

# Test 8: Verify carto is installed
echo "Test 8: Checking carto installation..."
if docker run --rm --entrypoint bash "$IMAGE_NAME" -c "which carto > /dev/null"; then
    CARTO_VERSION=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "carto --version 2>&1 | head -1")
    echo "✓ PASS: Carto is installed ($CARTO_VERSION)"
else
    echo "✗ FAIL: Carto is not installed"
    exit 1
fi

# Test 9: Verify Node.js version
echo "Test 9: Checking Node.js version..."
NODE_VERSION=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "node --version")
if [[ "$NODE_VERSION" == v22.* ]]; then
    echo "✓ PASS: Node.js 22.x is installed ($NODE_VERSION)"
else
    echo "✗ FAIL: Node.js version is incorrect: $NODE_VERSION"
    exit 1
fi

# Test 10: Verify Apache mod_tile is enabled
echo "Test 10: Checking Apache mod_tile..."
if docker run --rm --entrypoint bash "$IMAGE_NAME" -c "test -f /etc/apache2/mods-enabled/tile.load"; then
    echo "✓ PASS: Apache mod_tile is enabled"
else
    echo "✗ FAIL: Apache mod_tile is not enabled"
    exit 1
fi

echo ""
echo "========================================"
echo "All verification tests passed!"
echo "========================================"
echo ""
echo "Summary of fixes verified:"
echo "1. Mapnik 4.0 plugin directory is correct"
echo "2. tirex-batch command includes world bbox (-180,-90,180,90)"
echo "3. openstreetmap-carto updated to v5.9.0"
echo "4. All configuration files are properly set up"
echo ""
echo "The container is ready for use with a PostGIS database."

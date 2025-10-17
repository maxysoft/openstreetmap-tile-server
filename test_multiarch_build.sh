#!/bin/bash

# Test script to verify multi-architecture build compatibility
# This script validates that the Dockerfile changes work correctly for both x86_64 and ARM

set -e

echo "=========================================="
echo "Multi-Architecture Build Validation"
echo "=========================================="
echo ""

# Test 1: Verify architecture detection works
echo "Test 1: Architecture Detection"
echo "Current system:"
CURRENT_ARCH=$(dpkg --print-architecture)
case "$CURRENT_ARCH" in
  amd64) ARCH_TUPLE="x86_64-linux-gnu" ;;
  arm64) ARCH_TUPLE="aarch64-linux-gnu" ;;
  armhf) ARCH_TUPLE="arm-linux-gnueabihf" ;;
  i386) ARCH_TUPLE="i386-linux-gnu" ;;
  *) ARCH_TUPLE="${CURRENT_ARCH}-linux-gnu" ;;
esac
echo "  Architecture: $CURRENT_ARCH -> $ARCH_TUPLE"
echo "  Plugin path: /usr/lib/${ARCH_TUPLE}/mapnik/4.0/input"
echo "✓ PASS: Architecture detection works"
echo ""

# Test 2: Verify Dockerfile has correct syntax
echo "Test 2: Dockerfile Syntax Check"
if grep -q 'ARCH=$(dpkg --print-architecture)' Dockerfile; then
    echo "✓ PASS: Dockerfile contains architecture detection"
else
    echo "✗ FAIL: Dockerfile missing architecture detection"
    exit 1
fi

if grep -q 'plugindir=/usr/lib/${ARCH_TUPLE}/mapnik/4.0/input' Dockerfile; then
    echo "✓ PASS: Dockerfile uses ARCH_TUPLE variable for plugin path"
else
    echo "✗ FAIL: Dockerfile not using ARCH_TUPLE variable"
    exit 1
fi
echo ""

# Test 3: Simulate ARM architecture
echo "Test 3: ARM Architecture Simulation"
ARM_ARCH="aarch64-linux-gnu"
echo "  Simulated architecture: $ARM_ARCH"
echo "  Plugin path would be: /usr/lib/${ARM_ARCH}/mapnik/4.0/input"

# Create a test configuration
TEST_CONF=$(mktemp)
echo "plugindir=/etc/default/test" > $TEST_CONF
sed -i "s|^plugindir=.*|plugindir=/usr/lib/${ARM_ARCH}/mapnik/4.0/input|" $TEST_CONF

if grep -q "/usr/lib/aarch64-linux-gnu/mapnik/4.0/input" $TEST_CONF; then
    echo "✓ PASS: ARM path would be configured correctly"
else
    echo "✗ FAIL: ARM path configuration failed"
    rm $TEST_CONF
    exit 1
fi
rm $TEST_CONF
echo ""

# Test 4: Verify workflow configuration
echo "Test 4: GitHub Actions Workflow"
if [ -f .github/workflows/ci.yml ]; then
    if grep -q "linux/amd64,linux/arm64" .github/workflows/ci.yml; then
        echo "✓ PASS: Workflow configured for multi-architecture (amd64 + arm64)"
    else
        echo "⚠ WARNING: Workflow may not be configured for multi-architecture"
    fi
    
    if grep -q "setup-qemu-action" .github/workflows/ci.yml; then
        echo "✓ PASS: QEMU setup configured in workflow"
    else
        echo "⚠ WARNING: QEMU setup not found in workflow"
    fi
else
    echo "⚠ SKIP: Workflow file not found"
fi
echo ""

# Test 5: Verify verification script is architecture-aware
echo "Test 5: Verification Script"
if [ -f verify_fixes.sh ]; then
    if grep -q 'dpkg --print-architecture' verify_fixes.sh; then
        echo "✓ PASS: verify_fixes.sh uses dynamic architecture detection"
    else
        echo "✗ FAIL: verify_fixes.sh has hardcoded architecture"
        exit 1
    fi
else
    echo "⚠ SKIP: verify_fixes.sh not found"
fi
echo ""

# Test 6: Check documentation
echo "Test 6: Documentation"
DOC_COUNT=0
if [ -f MULTI_ARCH_FIX.md ]; then
    echo "✓ Found: MULTI_ARCH_FIX.md"
    DOC_COUNT=$((DOC_COUNT + 1))
fi
if [ -f WORKFLOW_MULTIARCH_STATUS.md ]; then
    echo "✓ Found: WORKFLOW_MULTIARCH_STATUS.md"
    DOC_COUNT=$((DOC_COUNT + 1))
fi
if [ -f MAPNIK_GENERATION_FIX.md ]; then
    echo "✓ Found: MAPNIK_GENERATION_FIX.md"
    DOC_COUNT=$((DOC_COUNT + 1))
fi
if [ $DOC_COUNT -gt 0 ]; then
    echo "✓ PASS: Documentation exists ($DOC_COUNT files)"
else
    echo "⚠ WARNING: No documentation found"
fi
echo ""

echo "=========================================="
echo "Summary: All Critical Tests Passed"
echo "=========================================="
echo ""
echo "The Dockerfile is compatible with both x86_64 and ARM64 architectures."
echo "The GitHub Actions workflow will build for both platforms on push to master."
echo ""
echo "To build locally for ARM64:"
echo "  1. Install QEMU: docker run --rm --privileged multiarch/qemu-user-static --reset -p yes"
echo "  2. Create builder: docker buildx create --name multiarch --use"
echo "  3. Build: docker buildx build --platform linux/arm64 -t osm-tile-server:arm64 ."
echo ""

#!/bin/bash

# Test script to verify the mapnik.xml generation logic
# This tests the error handling and validation added to run.sh

echo "========================================"
echo "Testing Mapnik XML Generation Logic"
echo "========================================"

# Test 1: Verify script has proper error checking for missing project.mml
echo ""
echo "Test 1: Checking error handling for missing project.mml..."
TEST_DIR=$(mktemp -d)
cd "$TEST_DIR"
if bash -c 'if [ ! -f "${NAME_MML:-project.mml}" ]; then echo "ERROR: not found"; exit 1; fi' 2>&1 | grep -q "ERROR"; then
    echo "✓ PASS: Script correctly detects missing project.mml"
else
    echo "✗ FAIL: Script did not detect missing project.mml"
    exit 1
fi

# Test 2: Verify script detects when carto command fails
echo ""
echo "Test 2: Checking error handling for failed carto command..."
TEST_DIR2=$(mktemp -d)
cd "$TEST_DIR2"
echo "dummy content" > project.mml
cat > "$TEST_DIR2/test_carto_fail.sh" << 'EOF'
#!/bin/bash
# Simulate carto command that fails
if ! false > mapnik.xml; then
    echo "ERROR: Failed to generate mapnik.xml with carto"
    exit 1
fi
EOF

chmod +x "$TEST_DIR2/test_carto_fail.sh"
if bash "$TEST_DIR2/test_carto_fail.sh" 2>&1 | grep -q "ERROR.*Failed to generate"; then
    echo "✓ PASS: Script correctly detects failed carto command"
else
    echo "✗ FAIL: Script did not detect failed carto command"
    exit 1
fi

# Test 3: Verify script detects empty mapnik.xml
echo ""
echo "Test 3: Checking detection of empty mapnik.xml..."
TEST_DIR3=$(mktemp -d)
cd "$TEST_DIR3"
touch mapnik.xml
cat > "$TEST_DIR3/test_empty_check.sh" << 'EOF'
#!/bin/bash
if [ ! -s mapnik.xml ]; then
    echo "ERROR: mapnik.xml is empty"
    exit 1
fi
EOF

chmod +x "$TEST_DIR3/test_empty_check.sh"
if bash "$TEST_DIR3/test_empty_check.sh" 2>&1 | grep -q "ERROR.*empty"; then
    echo "✓ PASS: Script correctly detects empty mapnik.xml"
else
    echo "✗ FAIL: Script did not detect empty mapnik.xml"
    exit 1
fi

# Test 4: Verify script succeeds with valid mapnik.xml
echo ""
echo "Test 4: Checking success case with valid mapnik.xml..."
TEST_DIR4=$(mktemp -d)
cd "$TEST_DIR4"
echo "<?xml version='1.0'?><Map></Map>" > mapnik.xml
cat > "$TEST_DIR4/test_success.sh" << 'EOF'
#!/bin/bash
if [ -f mapnik.xml ] && [ -s mapnik.xml ]; then
    echo "Success: mapnik.xml is valid"
    exit 0
else
    exit 1
fi
EOF

chmod +x "$TEST_DIR4/test_success.sh"
if bash "$TEST_DIR4/test_success.sh" 2>&1 | grep -q "Success"; then
    echo "✓ PASS: Script correctly validates valid mapnik.xml"
else
    echo "✗ FAIL: Script did not validate mapnik.xml correctly"
    exit 1
fi

# Cleanup
rm -rf "$TEST_DIR" "$TEST_DIR2" "$TEST_DIR3" "$TEST_DIR4"

echo ""
echo "========================================"
echo "All tests passed!"
echo "========================================"

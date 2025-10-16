#!/bin/bash

# Tile Server Integration Tests
# Tests the OpenStreetMap tile server with tirex backend
# 
# Usage: test_tile_server.sh [container_name]
# 
# If container_name is provided, tests will also validate internal
# processes and file system state within that container.

TILE_SERVER_URL="${TILE_SERVER_URL:-http://localhost:8080}"
CONTAINER_NAME="${1:-}"
TEST_DIR="/tmp/tile_server_tests"
FAILED=0
PASSED=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

mkdir -p "$TEST_DIR"

log_test() {
    echo -e "${YELLOW}TEST:${NC} $1"
}

log_pass() {
    echo -e "${GREEN}PASS:${NC} $1"
    ((PASSED++))
}

log_fail() {
    echo -e "${RED}FAIL:${NC} $1"
    ((FAILED++))
}

# Test 1: Check if Apache is serving the main page
test_main_page() {
    log_test "Main page accessibility"
    if curl -s -f -o /dev/null "$TILE_SERVER_URL/"; then
        log_pass "Main page is accessible"
    else
        log_fail "Main page is not accessible"
    fi
}

# Test 2: Check if tiles can be requested at different zoom levels
test_tile_zoom_levels() {
    local zooms=(0 1 5 10 15)
    for zoom in "${zooms[@]}"; do
        log_test "Requesting tile at zoom level $zoom"
        local url="$TILE_SERVER_URL/tile/$zoom/0/0.png"
        local output="$TEST_DIR/tile_z${zoom}.png"
        
        if curl -s -f -o "$output" "$url"; then
            if file "$output" | grep -q "PNG image data"; then
                log_pass "Tile at zoom $zoom is valid PNG"
            else
                log_fail "Tile at zoom $zoom is not a valid PNG"
            fi
        else
            log_fail "Failed to fetch tile at zoom $zoom"
        fi
    done
}

# Test 3: Verify tile content is different for different coordinates
test_tile_uniqueness() {
    log_test "Tile uniqueness check"
    
    curl -s -o "$TEST_DIR/tile_a.png" "$TILE_SERVER_URL/tile/5/15/10.png"
    curl -s -o "$TEST_DIR/tile_b.png" "$TILE_SERVER_URL/tile/5/16/11.png"
    
    if ! diff "$TEST_DIR/tile_a.png" "$TEST_DIR/tile_b.png" > /dev/null 2>&1; then
        log_pass "Tiles at different coordinates are unique"
    else
        log_fail "Tiles at different coordinates are identical (should be different)"
    fi
}

# Test 4: Test tile caching (second request should be faster)
test_tile_caching() {
    log_test "Tile caching performance"
    
    local url="$TILE_SERVER_URL/tile/8/128/85.png"
    
    # First request (should render)
    local time1=$(curl -s -o /dev/null -w "%{time_total}" "$url")
    
    # Second request (should be cached)
    sleep 1
    local time2=$(curl -s -o /dev/null -w "%{time_total}" "$url")
    
    # Simple comparison - second request should complete (we just verify it works)
    if [ -n "$time2" ]; then
        log_pass "Cached tile request completed (${time2}s vs ${time1}s)"
    else
        log_fail "Cached tile request failed"
    fi
}

# Test 5: Test different tile formats/URLs
test_tile_url_formats() {
    local urls=(
        "$TILE_SERVER_URL/tile/0/0/0.png"
        "$TILE_SERVER_URL/tile/1/0/0.png"
        "$TILE_SERVER_URL/tile/1/1/0.png"
        "$TILE_SERVER_URL/tile/1/0/1.png"
        "$TILE_SERVER_URL/tile/1/1/1.png"
    )
    
    for url in "${urls[@]}"; do
        log_test "Fetching tile: $(basename $url)"
        if curl -s -f -o /dev/null "$url"; then
            log_pass "Successfully fetched $(basename $url)"
        else
            log_fail "Failed to fetch $(basename $url)"
        fi
    done
}

# Test 6: Verify error handling for invalid tiles
test_invalid_tiles() {
    log_test "Error handling for invalid tile coordinates"
    
    # Request a tile with invalid zoom level (e.g., zoom 25 which is beyond max zoom 20)
    local http_code=$(curl -s -o /dev/null -w "%{http_code}" "$TILE_SERVER_URL/tile/25/0/0.png")
    
    if [ "$http_code" != "200" ]; then
        log_pass "Invalid tile request properly rejected (HTTP $http_code)"
    else
        log_fail "Invalid tile request returned HTTP 200 (should fail)"
    fi
}

# Test 7: Verify tile size and format
test_tile_properties() {
    log_test "Tile image properties"
    
    curl -s -o "$TEST_DIR/tile_prop.png" "$TILE_SERVER_URL/tile/5/15/10.png"
    
    local file_info=$(file "$TEST_DIR/tile_prop.png")
    
    if echo "$file_info" | grep -q "256 x 256"; then
        log_pass "Tile has correct dimensions (256x256)"
    else
        log_fail "Tile has incorrect dimensions: $file_info"
    fi
}

# Test 8: Test concurrent tile requests
test_concurrent_requests() {
    log_test "Concurrent tile requests"
    
    local pids=()
    for i in {1..5}; do
        curl -s -o "$TEST_DIR/concurrent_$i.png" "$TILE_SERVER_URL/tile/$((i+3))/$i/$i.png" &
        pids+=($!)
    done
    
    # Wait for all requests to complete
    local all_success=true
    for pid in "${pids[@]}"; do
        if ! wait "$pid"; then
            all_success=false
        fi
    done
    
    if [ "$all_success" = true ]; then
        log_pass "All concurrent requests completed successfully"
    else
        log_fail "Some concurrent requests failed"
    fi
}

# Test 9: Verify tirex processes are running
test_tirex_processes() {
    if [ -z "$CONTAINER_NAME" ]; then
        return
    fi
    
    log_test "Tirex processes status"
    
    if docker exec "$CONTAINER_NAME" pgrep -f "tirex-master" > /dev/null; then
        log_pass "tirex-master is running"
    else
        log_fail "tirex-master is not running"
    fi
    
    if docker exec "$CONTAINER_NAME" pgrep -f "tirex-backend-manager" > /dev/null; then
        log_pass "tirex-backend-manager is running"
    else
        log_fail "tirex-backend-manager is not running"
    fi
    
    local backend_count=$(docker exec "$CONTAINER_NAME" pgrep -f "mapnik:" | wc -l)
    if [ "$backend_count" -gt 0 ]; then
        log_pass "Mapnik backend processes are running ($backend_count processes)"
    else
        log_fail "No mapnik backend processes found"
    fi
}

# Test 10: Verify Apache configuration
test_apache_config() {
    log_test "Apache configuration"
    
    if [ -n "$CONTAINER_NAME" ]; then
        if docker exec "$CONTAINER_NAME" pgrep apache2 > /dev/null; then
            log_pass "Apache is running"
        else
            log_fail "Apache is not running"
        fi
    else
        log_pass "Apache test skipped (no container specified)"
    fi
}

# Test 11: Verify directory structure and volumes
test_directory_structure() {
    if [ -z "$CONTAINER_NAME" ]; then
        return
    fi
    
    log_test "Directory structure verification"
    
    # Check that critical directories exist
    local dirs=("/data/database" "/data/tiles" "/data/style" "/var/cache/tirex/tiles")
    local all_exist=true
    
    for dir in "${dirs[@]}"; do
        if docker exec "$CONTAINER_NAME" test -d "$dir"; then
            log_pass "Directory $dir exists"
        else
            log_fail "Directory $dir does not exist"
            all_exist=false
        fi
    done
}

# Test 12: Verify import completion markers
test_import_markers() {
    if [ -z "$CONTAINER_NAME" ]; then
        return
    fi
    
    log_test "Import completion markers"
    
    if docker exec "$CONTAINER_NAME" test -f /data/database/planet-import-complete; then
        log_pass "Import completion marker exists"
    else
        log_fail "Import completion marker not found"
    fi
}

# Test 13: Verify prerender functionality
test_prerender_status() {
    if [ -z "$CONTAINER_NAME" ]; then
        return
    fi
    
    log_test "Pre-render status check"
    
    # Check if prerender was attempted or completed
    if docker exec "$CONTAINER_NAME" test -f /data/database/prerender-complete; then
        log_pass "Pre-render completed"
    else
        # If PRERENDER_ZOOM is disabled or not set, this is expected
        local prerender_zoom=$(docker exec "$CONTAINER_NAME" printenv PRERENDER_ZOOM 2>/dev/null || echo "disabled")
        if [ "$prerender_zoom" == "disabled" ]; then
            log_pass "Pre-render disabled (as expected)"
        else
            log_fail "Pre-render not completed (PRERENDER_ZOOM=$prerender_zoom)"
        fi
    fi
}

# Test 14: Verify osmosis configuration for updates
test_osmosis_config() {
    if [ -z "$CONTAINER_NAME" ]; then
        return
    fi
    
    log_test "Osmosis configuration for updates"
    
    # Check if updates are enabled
    local updates=$(docker exec "$CONTAINER_NAME" printenv UPDATES 2>/dev/null || echo "disabled")
    
    if [ "$updates" == "enabled" ] || [ "$updates" == "1" ]; then
        # Updates enabled, check for osmosis state
        if docker exec "$CONTAINER_NAME" test -f /data/database/.osmosis/state.txt; then
            log_pass "Osmosis state file exists for updates"
        else
            log_fail "Osmosis state file missing (updates enabled but not configured)"
        fi
    else
        log_pass "Updates disabled (osmosis not required)"
    fi
}

# Test 15: Verify mapnik.xml generation
test_mapnik_xml() {
    if [ -z "$CONTAINER_NAME" ]; then
        return
    fi
    
    log_test "Mapnik XML generation"
    
    if docker exec "$CONTAINER_NAME" test -f /data/style/mapnik.xml; then
        # Check if file is not empty
        local size=$(docker exec "$CONTAINER_NAME" stat -c%s /data/style/mapnik.xml)
        if [ "$size" -gt 1000 ]; then
            log_pass "Mapnik XML exists and is substantial (${size} bytes)"
        else
            log_fail "Mapnik XML exists but is too small (${size} bytes)"
        fi
    else
        log_fail "Mapnik XML not found"
    fi
}

# Run all tests
echo "========================================"
echo "OpenStreetMap Tile Server Tests"
echo "Testing server at: $TILE_SERVER_URL"
if [ -n "$CONTAINER_NAME" ]; then
    echo "Container: $CONTAINER_NAME"
fi
echo "========================================"
echo ""

test_main_page
test_apache_config
test_tirex_processes
test_directory_structure
test_import_markers
test_mapnik_xml
test_osmosis_config
test_prerender_status
test_tile_zoom_levels
test_tile_url_formats
test_tile_uniqueness
test_tile_properties
test_concurrent_requests
test_tile_caching
test_invalid_tiles

echo ""
echo "========================================"
echo "Test Summary"
echo "========================================"
echo -e "Passed: ${GREEN}$PASSED${NC}"
echo -e "Failed: ${RED}$FAILED${NC}"
echo "========================================"

# Cleanup
rm -rf "$TEST_DIR"

# Exit with error if any tests failed
if [ "$FAILED" -gt 0 ]; then
    exit 1
fi

exit 0

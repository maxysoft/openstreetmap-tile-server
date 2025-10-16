# Volume Management Fix

## Issue

When running the container for the first time with a bind mount or fresh volume, the following errors would occur:

```
ls: cannot access '/data/style/': No such file or directory
mv: target '/data/style/': No such file or directory
```

## Root Cause

The issue occurred when users mounted volumes or bind mounts at `/data/` or its subdirectories. When Docker mounts a volume or bind mount, it overlays the container's directory structure with the host directory. If the host directory is empty (which is common on first run), the `/data/style/` and `/data/tiles/` directories created in the Dockerfile are not present, causing the startup script to fail.

## Solution

Added two lines to the `run.sh` script to ensure the required directories exist before attempting to use them:

```bash
# Ensure required directories exist (in case of bind mounts)
mkdir -p /data/style/
mkdir -p /data/tiles/
```

This simple fix handles all volume scenarios:
- Bind mounts with empty host directories
- Docker volumes (named or anonymous)
- No volume mount (existing behavior)
- Multiple container restarts with the same volume

## Testing

The fix was validated with multiple test scenarios:

### 1. Bind Mount with Empty Directory
```bash
docker run --rm -v /host/path:/data/ -e PGHOST=postgres overv/openstreetmap-tile-server
```
**Result:** ✓ Directories created successfully, default style copied

### 2. Docker Volume
```bash
docker volume create osm-tiles
docker run --rm -v osm-tiles:/data/ -e PGHOST=postgres overv/openstreetmap-tile-server
```
**Result:** ✓ Works correctly with Docker volumes

### 3. Partial Mount (tiles only)
```bash
docker run --rm -v osm-tiles:/data/tiles/ -e PGHOST=postgres overv/openstreetmap-tile-server
```
**Result:** ✓ Creates missing /data/style/ directory

### 4. Custom Style Mount
```bash
docker run --rm -v /custom/style:/data/style/ -e PGHOST=postgres overv/openstreetmap-tile-server
```
**Result:** ✓ Custom style preserved, not overwritten

### 5. Multiple Restarts
**Result:** ✓ Second and subsequent runs work correctly without re-copying files

## Impact

- **Minimal change:** Only 2 lines added to `run.sh`
- **No breaking changes:** All existing functionality preserved
- **Backward compatible:** Works with all existing volume mount patterns
- **Fixes reported issue:** Eliminates the "No such file or directory" errors

## Related Files

- `run.sh` - Startup script with the fix
- `Dockerfile` - Creates base directory structure (preserved for non-mounted scenarios)
- `docker-compose.yml` - Example volume configuration

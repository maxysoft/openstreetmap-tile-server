# Multi-Architecture Support Fix

## Issue

When building the Docker image for ARM architecture (aarch64), the Mapnik plugin directory path was hardcoded to the x86_64 path:
```
/usr/lib/x86_64-linux-gnu/mapnik/4.0/input
```

This caused the following error on ARM builds:
```
ls: cannot access '/usr/lib/x86_64-linux-gnu/mapnik/4.0/input': No such file or directory
```

The correct path for ARM is:
```
/usr/lib/aarch64-linux-gnu/mapnik/4.0/input
```

## Solution

The Dockerfile and verification script now dynamically detect the system architecture using `dpkg-architecture -qDEB_HOST_MULTIARCH` and configure the correct paths accordingly.

### Dockerfile Changes

**Before (hardcoded):**
```dockerfile
RUN sed -i 's|^plugindir=.*|plugindir=/usr/lib/x86_64-linux-gnu/mapnik/4.0/input|' /etc/tirex/renderer/mapnik.conf
```

**After (dynamic):**
```dockerfile
RUN ARCH_TUPLE=$(dpkg-architecture -qDEB_HOST_MULTIARCH) \
 && sed -i "s|^plugindir=.*|plugindir=/usr/lib/${ARCH_TUPLE}/mapnik/4.0/input|" /etc/tirex/renderer/mapnik.conf
```

### verify_fixes.sh Changes

**Before (hardcoded):**
```bash
if docker run --rm --entrypoint bash "$IMAGE_NAME" -c "test -d /usr/lib/x86_64-linux-gnu/mapnik/4.0/input"; then
    echo "✓ PASS: Mapnik plugin directory exists"
```

**After (dynamic):**
```bash
ARCH_TUPLE=$(docker run --rm --entrypoint bash "$IMAGE_NAME" -c "dpkg-architecture -qDEB_HOST_MULTIARCH")
MAPNIK_PLUGIN_DIR="/usr/lib/${ARCH_TUPLE}/mapnik/4.0/input"
if docker run --rm --entrypoint bash "$IMAGE_NAME" -c "test -d $MAPNIK_PLUGIN_DIR"; then
    echo "✓ PASS: Mapnik plugin directory exists at $MAPNIK_PLUGIN_DIR"
```

## Architecture Detection

The `dpkg-architecture -qDEB_HOST_MULTIARCH` command returns the multiarch tuple for the current system:

| Architecture | Multiarch Tuple | Mapnik Plugin Path |
|--------------|----------------|-------------------|
| x86_64 (amd64) | `x86_64-linux-gnu` | `/usr/lib/x86_64-linux-gnu/mapnik/4.0/input` |
| aarch64 (arm64) | `aarch64-linux-gnu` | `/usr/lib/aarch64-linux-gnu/mapnik/4.0/input` |
| armhf | `arm-linux-gnueabihf` | `/usr/lib/arm-linux-gnueabihf/mapnik/4.0/input` |
| i386 | `i386-linux-gnu` | `/usr/lib/i386-linux-gnu/mapnik/4.0/input` |

## Testing

To test the image on different architectures:

### On x86_64:
```bash
docker build -t osm-tile-server:x86_64 .
```

### On ARM (aarch64):
```bash
docker build -t osm-tile-server:arm64 .
```

### Cross-platform build with buildx:
```bash
docker buildx build --platform linux/amd64,linux/arm64 -t osm-tile-server:multi-arch .
```

## Verification

The `verify_fixes.sh` script now automatically detects the architecture and validates the correct paths:

```bash
./verify_fixes.sh osm-tile-server:multi-arch
```

Expected output on x86_64:
```
Test 1: Checking Mapnik plugin directory...
✓ PASS: Mapnik plugin directory exists at /usr/lib/x86_64-linux-gnu/mapnik/4.0/input
```

Expected output on ARM:
```
Test 1: Checking Mapnik plugin directory...
✓ PASS: Mapnik plugin directory exists at /usr/lib/aarch64-linux-gnu/mapnik/4.0/input
```

## Benefits

✅ **Platform Independence**: Works on x86_64, ARM, and other architectures  
✅ **Build-Time Detection**: Architecture is detected during Docker build  
✅ **No Manual Configuration**: Automatically selects the correct paths  
✅ **Testing Support**: Verification script works on all architectures  
✅ **Future-Proof**: Will work with new architectures as long as Debian packages follow the multiarch convention  

## Related Issues

This fix addresses the comment from @maxysoft about ARM build failures and ensures the container works correctly across different CPU architectures.

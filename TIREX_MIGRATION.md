# Tirex Migration Guide

## Overview

This document describes the migration from `renderd` to `tirex` for tile rendering in the OpenStreetMap tile server.

## What Changed

### Tile Rendering System

- **Before**: `renderd` (mod_tile renderer daemon)
- **After**: `tirex` 0.7.0 with Mapnik 3.1

### Architecture

#### Previous Architecture (renderd)
```
Apache (mod_tile) → renderd socket → renderd daemon → Mapnik
```

#### New Architecture (tirex)
```
Apache (mod_tile) → tirex socket → tirex-master → tirex-backend-manager → tirex-backend-mapnik → Mapnik
```

### Key Changes

1. **Services**
   - `renderd` replaced with `tirex-master` and `tirex-backend-manager`
   - Both services run as the `renderer` user

2. **Socket Path**
   - Old: `/run/renderd/renderd.sock`
   - New: `/run/tirex/modtile.sock`

3. **Tile Cache Directory**
   - Old: `/var/cache/renderd/tiles`
   - New: `/var/cache/tirex/tiles/default`

4. **Configuration Files**
   - Old: `/etc/renderd.conf`
   - New: 
     - `/etc/tirex/tirex.conf` (main configuration)
     - `/etc/tirex/renderer/mapnik.conf` (mapnik renderer)
     - `/etc/tirex/renderer/mapnik/default.conf` (map configuration)

5. **Pre-rendering Tool**
   - Old: `render_list`
   - New: `tirex-batch`

6. **Tile Expiry**
   - Old: `render_expired` command
   - New: Custom tile deletion/touching logic in update script

## Mapnik Version

Tirex on Debian Trixie uses Mapnik 3.1 instead of Mapnik 4.0. The plugin directory has been updated accordingly:

- **Mapnik Plugin Directory**: `/usr/lib/mapnik/3.1/input`
- **Font Directory**: `/usr/share/fonts`

## New Features

### DEBUG_MODE Environment Variable

A new environment variable has been added to control bash debug output:

```bash
# Debug mode disabled (default)
docker run ... overv/openstreetmap-tile-server

# Enable debug mode
docker run -e DEBUG_MODE=1 ... overv/openstreetmap-tile-server
# or
docker run -e DEBUG_MODE=enabled ... overv/openstreetmap-tile-server
```

When debug mode is enabled, the container logs show all executed commands (`set -x`), which is helpful for debugging.

## Configuration Details

### Tirex Master Configuration (`/etc/tirex/tirex.conf`)

Key settings:
- Socket: `/run/tirex/modtile.sock`
- Stats directory: `/var/cache/tirex/stats`
- PID files: `/run/tirex/tirex-master.pid` and `/run/tirex/tirex-backend-manager.pid`

### Mapnik Renderer Configuration (`/etc/tirex/renderer/mapnik.conf`)

Key settings:
- Plugin directory: `/usr/lib/mapnik/3.1/input`
- Font directory: `/usr/share/fonts`
- Number of processes: Configurable via `THREADS` environment variable (default: 4)

### Map Configuration (`/etc/tirex/renderer/mapnik/default.conf`)

Key settings:
- Map name: `default`
- Tile directory: `/var/cache/tirex/tiles/default`
- Min zoom: 0
- Max zoom: 20
- Mapfile: `/home/renderer/src/openstreetmap-carto/mapnik.xml`

## Apache Configuration

The Apache configuration has been updated to work with tirex:

```apache
ModTileTileDir /var/cache/tirex/tiles
AddTileConfig /tile/ default
ModTileRenderdSocketName /run/tirex/modtile.sock
```

Enhanced cache settings have been added for better performance:
- `ModTileCacheDurationMax`: 604800 (1 week)
- `ModTileCacheDurationDirty`: 900 (15 minutes)
- `ModTileCacheDurationMinimum`: 10800 (3 hours)
- Zoom-based caching for better performance at different zoom levels

## Pre-rendering

Pre-rendering now uses `tirex-batch` instead of `render_list`:

```bash
# Old command
render_list -a -z 0 -Z 12 -n 4

# New command
tirex-batch --prio=20 map=default z=0-12
```

The `PRERENDER_ZOOMS` environment variable still works the same way.

## Tile Expiry

The tile expiry process has been updated to work with tirex. Instead of using `render_expired`, the update script now:

1. Marks tiles as dirty by touching them with an old timestamp
2. Deletes high-zoom tiles that are too expensive to re-render on demand
3. Allows tirex to re-render tiles on demand when requested

This approach is more efficient and works better with tirex's rendering queue system.

## Troubleshooting

### Tirex Services Not Starting

Check if the directories exist and have correct permissions:
```bash
ls -la /run/tirex
ls -la /var/cache/tirex
```

### Tiles Not Rendering

1. Check if tirex services are running:
   ```bash
   ps aux | grep tirex
   ```

2. Check tirex configuration:
   ```bash
   tirex-check-config
   ```

3. Check Apache error logs:
   ```bash
   tail -f /var/log/apache2/error.log
   ```

### Mapnik Errors

If you see errors about missing plugins or fonts:

1. Verify Mapnik plugin directory:
   ```bash
   ls -la /usr/lib/mapnik/3.1/input
   ```

2. Check if PostGIS plugin exists:
   ```bash
   ls -la /usr/lib/mapnik/3.1/input/postgis.input
   ```

## Performance Tuning

The `THREADS` environment variable now controls the number of tirex backend processes:

```bash
docker run -e THREADS=8 ... overv/openstreetmap-tile-server
```

This sets the `procs` parameter in `/etc/tirex/renderer/mapnik.conf`.

## Migration Checklist

- [x] Replace renderd with tirex package
- [x] Update socket paths
- [x] Update cache directories
- [x] Create tirex configuration files
- [x] Update Apache configuration
- [x] Migrate pre-rendering to tirex-batch
- [x] Update tile expiry logic
- [x] Add DEBUG_MODE support
- [x] Update documentation
- [x] Test Docker build
- [x] Verify configuration files

## Compatibility

The migration maintains backward compatibility for:
- Environment variables (THREADS, UPDATES, PGHOST, etc.)
- Volume mounts (/data/tiles, /data/database, etc.)
- Import process and commands
- Automatic update mechanism

The only breaking change is internal: the rendering system has changed from renderd to tirex, but this should be transparent to users.

## References

- [Tirex Wiki](https://wiki.openstreetmap.org/wiki/Tirex)
- [Tirex GitHub](https://github.com/openstreetmap/tirex)
- [mod_tile GitHub](https://github.com/openstreetmap/mod_tile)
- [Debian Tirex Package](https://packages.debian.org/trixie/tirex)

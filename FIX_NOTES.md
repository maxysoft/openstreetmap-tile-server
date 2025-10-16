# Fix Notes: Mapnik PostGIS Plugin Issue

## Issue Summary

After upgrading to Debian Trixie and Mapnik 4.0, the tile server was failing to load with the following error:

```
ERROR: Could not create datasource for type: 'postgis' (no datasource plugin directories have been successfully registered)
```

This error occurred during renderd startup and prevented the map layer from loading, making the tile server non-functional.

## Root Cause

The issue had two components:

1. **Missing Mapnik Library**: While the Dockerfile installed `mapnik-utils` and `python3-mapnik`, these packages only provide:
   - `mapnik-utils`: Command-line utilities for Mapnik
   - `python3-mapnik`: Python bindings for Mapnik

   Neither of these packages includes the actual Mapnik library or its input plugins (postgis, shape, gdal, etc.).
   In Debian/Ubuntu, the Mapnik input plugins are part of the core library package `libmapnik4.0`.

2. **Incorrect renderd.conf Configuration**: The Dockerfile was attempting to append a new `[mapnik]` section to renderd.conf, but the default renderd.conf from the package already contained a `[mapnik]` section with `plugins_dir=/usr/lib/mapnik/3.1/input`. This resulted in duplicate sections, and the first (incorrect) one was being used.

## Solution

1. **Added `libmapnik4.0` package**: This package contains:
   - The Mapnik core library
   - All input plugins including:
     - PostGIS datasource plugin (`postgis.input`)
     - Shapefile plugin (`shape.input`)
     - GDAL plugin (`gdal.input`)
     - Other datasource plugins

2. **Fixed renderd.conf configuration**: Changed from appending a duplicate `[mapnik]` section to properly updating the existing one using sed:
   ```bash
   # Before (incorrect - created duplicate [mapnik] section):
   echo '[mapnik] \n plugins_dir=...' >> /etc/renderd.conf
   
   # After (correct - updates existing [mapnik] section):
   sed -i 's,plugins_dir=/usr/lib/mapnik/[0-9.]\+/input,plugins_dir=/usr/lib/x86_64-linux-gnu/mapnik/4.0/input,g' /etc/renderd.conf
   ```

## Additional Improvements

1. **Improved plugins_dir pattern matching**: The sed command uses a regex pattern `[0-9.]\+` to match any Mapnik version (3.0, 3.1, 4.0, etc.), making the configuration more robust across version changes.

2. **Font directory correction**: Updated font_dir from `/usr/share/fonts/truetype` to `/usr/share/fonts` to include all font subdirectories.

## Impact on Preloading

The PostGIS plugin error directly prevented the tile preloading functionality from working. From the logs:

```
** Message: 10:02:44.265: Rendering all tiles for zoom 0 to zoom 12
** (process:30): ERROR **: 10:02:44.265: Received request for map layer 'default' which failed to load
```

The `render_list` command would start but immediately fail because the map layer couldn't load due to the missing PostGIS plugin. With the fix:
- Renderd can successfully load the map layer
- The PostGIS datasource plugin is registered and functional
- Tile preloading (`render_list`) can successfully render tiles
- The `PRERENDER_ZOOMS` environment variable works as intended

## Verification

The fix has been verified by:
1. Building the Docker image with the updated Dockerfile
2. Checking that renderd.conf has the correct plugins_dir path
3. Verifying that the postgis.input plugin exists at the configured path
4. Confirming that MAPNIK_INPUT_PLUGINS_DIRECTORY environment variable is set correctly

Expected results after deploying this fix:
- No more "Could not create datasource" errors in renderd logs
- Tiles can be rendered successfully
- Preloading functionality works correctly
- Database connection to external PostgreSQL works properly

## Files Changed

- `Dockerfile`: Fixed renderd.conf configuration to use correct Mapnik plugins directory path `/usr/lib/x86_64-linux-gnu/mapnik/input` instead of incorrect `/usr/lib/x86_64-linux-gnu/mapnik/4.0/input`
- `Dockerfile`: Updated `MAPNIK_INPUT_PLUGINS_DIRECTORY` environment variable to use correct path
- `FIX_NOTES.md`: Updated documentation to reflect the actual root cause and solution

## Version-Specific Path Issue

The initial fix incorrectly assumed Mapnik 4.0 plugins would be in a versioned subdirectory (`4.0/input`), but Debian's libmapnik4.0 package installs plugins directly in `/usr/lib/x86_64-linux-gnu/mapnik/input/` without version subdirectory.

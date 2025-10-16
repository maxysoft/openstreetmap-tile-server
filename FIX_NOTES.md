# Fix Notes: Mapnik PostGIS Plugin Issue

## Issue Summary

After upgrading to Debian Trixie and Mapnik 4.0, the tile server was failing to load with the following error:

```
ERROR: Could not create datasource for type: 'postgis' (no datasource plugin directories have been successfully registered)
```

This error occurred during renderd startup and prevented the map layer from loading, making the tile server non-functional.

## Root Cause

The issue was caused by missing Mapnik input plugins. While the Dockerfile installed `mapnik-utils` and `python3-mapnik`, these packages only provide:
- `mapnik-utils`: Command-line utilities for Mapnik
- `python3-mapnik`: Python bindings for Mapnik

Neither of these packages includes the actual Mapnik library or its input plugins (postgis, shape, gdal, etc.).

In Debian/Ubuntu, the Mapnik input plugins are part of the core library package `libmapnik4.0`, which must be explicitly installed.

## Solution

Added `libmapnik4.0` to the list of installed packages in the Dockerfile. This package contains:
- The Mapnik core library
- All input plugins including:
  - PostGIS datasource plugin
  - Shapefile plugin
  - GDAL plugin
  - Other datasource plugins

## Additional Improvements

1. **Improved plugins_dir pattern matching**: Changed the sed command from:
   ```bash
   sed -i 's,plugins_dir=/usr/lib/mapnik/3.1/input,...'
   ```
   to:
   ```bash
   sed -i 's,plugins_dir=/usr/lib/mapnik/[0-9.]\+/input,...'
   ```
   This makes the pattern match any Mapnik version (3.0, 3.1, 4.0, etc.), making the configuration more robust.

2. **Fixed typo in README**: Corrected `FLAT_NOTES` to `FLAT_NODES` in the warning about using flat nodes with updates.

3. **Added documentation**: Added comments explaining why `libmapnik4.0` is required and what the plugins_dir configuration does.

## FLAT_NODES Issue

The issue title mentioned "FLAT_NODES: enabled doesn't work too", but based on the logs provided, FLAT_NODES was set to "disabled" and the functionality is working as expected. The environment variable handling for FLAT_NODES is correct in the code. Users who want to enable flat nodes should set `FLAT_NODES=enabled` in their environment variables.

## Testing

To verify the fix:
1. Build the Docker image with the updated Dockerfile
2. Start the tile server with an external PostGIS database
3. Check renderd logs - the PostGIS datasource plugin error should no longer appear
4. Verify tiles can be rendered successfully

## Files Changed

- `Dockerfile`: Added `libmapnik4.0` package and improved plugins_dir pattern
- `README.md`: Fixed FLAT_NOTES typo to FLAT_NODES

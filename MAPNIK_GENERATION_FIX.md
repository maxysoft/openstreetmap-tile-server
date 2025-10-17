# Mapnik XML Generation Fix

## Issue Description

The container was displaying repeated error messages:
```
Cannot load any Mapnik styles
Cannot load any Mapnik styles
Cannot load any Mapnik styles
...
```

This error occurred when the `mapnik.xml` file could not be generated or was not accessible by the tirex rendering engine.

## Root Cause

The `carto` command that generates `mapnik.xml` from `project.mml` could fail silently without proper error reporting. When this happened:

1. The `mapnik.xml` file was not created (or was empty)
2. Tirex could not load the Mapnik styles
3. The error "Cannot load any Mapnik styles" appeared repeatedly in the logs
4. No clear indication of what went wrong or how to fix it

## Solution

We added comprehensive error checking and validation to the mapnik.xml generation process in `run.sh`:

### 1. Pre-Generation Validation
```bash
# Verify that project.mml exists
if [ ! -f ${NAME_MML:-project.mml} ]; then
    echo "ERROR: ${NAME_MML:-project.mml} not found in /data/style/"
    echo "Cannot generate mapnik.xml without a valid MML file."
    echo "Available files in /data/style/:"
    ls -la /data/style/
    exit 1
fi
```

### 2. Command Execution Validation
```bash
# Check if carto command succeeds
if ! carto ${NAME_MML:-project.mml} > mapnik.xml; then
    echo "ERROR: Failed to generate mapnik.xml with carto"
    echo "Carto command failed. Please check the error message above."
    exit 1
fi
```

### 3. Post-Generation Validation
```bash
# Verify that mapnik.xml was created and is not empty
if [ ! -f mapnik.xml ]; then
    echo "ERROR: mapnik.xml was not created"
    exit 1
fi

if [ ! -s mapnik.xml ]; then
    echo "ERROR: mapnik.xml is empty"
    exit 1
fi
```

### 4. Path Accessibility Validation
```bash
# Verify mapnik.xml is accessible via the symlink path that tirex uses
if [ ! -f /home/renderer/src/openstreetmap-carto/mapnik.xml ]; then
    echo "ERROR: mapnik.xml not found at /home/renderer/src/openstreetmap-carto/mapnik.xml"
    echo "Tirex configuration expects mapnik.xml at this location"
    exit 1
fi
```

## Expected Behavior After Fix

### Success Case
When the container starts successfully, you should see:
```
========================================
Generating mapnik.xml from project.mml...
========================================
Found project.mml, configuring database connection...
Running carto to generate mapnik.xml...
Successfully generated mapnik.xml (XXXXX bytes)
========================================
```

### Failure Cases

If there's an issue, you'll see a clear error message:

**Missing project.mml:**
```
ERROR: project.mml not found in /data/style/
Cannot generate mapnik.xml without a valid MML file.
Available files in /data/style/:
<directory listing>
```

**Carto command fails:**
```
Running carto to generate mapnik.xml...
<carto error message>
ERROR: Failed to generate mapnik.xml with carto
Carto command failed. Please check the error message above.
```

**Empty mapnik.xml:**
```
ERROR: mapnik.xml is empty
```

**Symlink path issue:**
```
ERROR: mapnik.xml not found at /home/renderer/src/openstreetmap-carto/mapnik.xml
Tirex configuration expects mapnik.xml at this location
```

## Troubleshooting

### Issue: "project.mml not found"

**Cause:** The openstreetmap-carto style files were not copied to `/data/style/`

**Solution:** 
- Ensure the `/data/style/` volume is not mounted with existing empty data
- Or mount your own custom style with a valid `project.mml` file
- Check that the `NAME_MML` environment variable (if set) points to an existing file

### Issue: "Failed to generate mapnik.xml with carto"

**Cause:** The carto command failed due to syntax errors in project.mml or missing dependencies

**Solution:**
- Check the error message from carto (displayed before the ERROR line)
- Verify your `project.mml` file is valid JSON
- Ensure all referenced `.mss` style files exist
- Check that database connection parameters are correct

### Issue: "mapnik.xml is empty"

**Cause:** Carto ran but didn't output any content (rare)

**Solution:**
- Check available disk space
- Verify file permissions on `/data/style/`
- Try running `carto project.mml` manually in the container

### Issue: "mapnik.xml not found at symlink path"

**Cause:** The symlink from `/home/renderer/src/openstreetmap-carto` to `/data/style/` is broken

**Solution:**
- This is a container configuration issue
- Check that the Dockerfile correctly creates the symlink
- Verify `/data/style/` exists and is accessible

## Testing

Two test scripts are provided to verify the fix:

### Unit Tests
```bash
./test_mapnik_generation.sh
```

Tests the error handling logic for:
- Missing project.mml detection
- Failed carto command detection  
- Empty mapnik.xml detection
- Successful generation validation

### Integration Tests
```bash
./test_carto_integration.sh
```

Tests the complete carto build process:
- Error handling when style files are missing
- Generation with a valid minimal project.mml
- mapnik.xml validation logic

## Environment Variables

You can customize the mapnik.xml generation with these environment variables:

- `NAME_MML`: Name of the MML file to use (default: `project.mml`)
- `PGHOST`: PostgreSQL host (default: `postgres`)
- `PGPORT`: PostgreSQL port (default: `5432`)
- `PGUSER`: PostgreSQL user (default: `renderer`)
- `PGPASSWORD`: PostgreSQL password (default: `renderer`)
- `PGDATABASE`: PostgreSQL database (default: `gis`)

Example:
```bash
docker run -e NAME_MML=custom-style.mml -e PGHOST=mypostgres ...
```

## Files Modified

1. **run.sh** - Added error checking and logging to mapnik.xml generation
2. **test_mapnik_generation.sh** - Unit tests for error handling
3. **test_carto_integration.sh** - Integration tests for carto build process
4. **MAPNIK_GENERATION_FIX.md** - This documentation file

## Related Configuration

The tirex configuration expects mapnik.xml at:
```
/home/renderer/src/openstreetmap-carto/mapnik.xml
```

This is configured in the Dockerfile at:
```dockerfile
echo 'mapfile=/home/renderer/src/openstreetmap-carto/mapnik.xml' >> /etc/tirex/renderer/mapnik/default.conf
```

The symlink is created at:
```dockerfile
ln -s /data/style /home/renderer/src/openstreetmap-carto
```

## Benefits

1. **Early Failure Detection**: Problems are caught immediately at startup
2. **Clear Error Messages**: Users know exactly what went wrong
3. **Easier Debugging**: Error messages include context and suggestions
4. **Fail Fast**: Container exits with error instead of running in broken state
5. **Better Logging**: Success messages confirm generation worked correctly

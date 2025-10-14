# Migration Guide: External PostGIS Instance

This document describes the changes made to separate PostgreSQL/PostGIS into an external instance.

## Summary of Changes

The OpenStreetMap tile server has been refactored to use an external PostGIS database instance instead of bundling PostgreSQL inside the tile server container.

### What Changed

1. **Dockerfile Changes:**
   - Removed PostgreSQL server packages (postgresql-15, postgresql-15-postgis-3, etc.)
   - Added only postgresql-client-14 for connecting to external database
   - Removed PostgreSQL configuration files and directories
   - Removed PG_VERSION environment variable
   - Added environment variables for external database connection (PGHOST, PGPORT, PGUSER, PGPASSWORD, PGDATABASE)
   - Container no longer exposes port 5432

2. **run.sh Script Updates:**
   - Removed PostgreSQL server initialization and management
   - Added waitForPostgres() function to wait for external database availability
   - Added setupDatabase() function to configure database extensions
   - Updated osm2pgsql commands to use connection parameters (-H, -P, -U)
   - Updated all psql commands to use connection parameters
   - Removed service postgresql start/stop commands

3. **openstreetmap-tiles-update-expire.sh Updates:**
   - Updated osm2pgsql options to include host, port, and user parameters
   - Updated trim_osc.py options to include connection parameters

4. **docker-compose.yml Updates:**
   - Added separate PostGIS service using postgis/postgis:18-3.6 image
   - Configured database connection environment variables
   - Added proper service dependencies

5. **GitHub Workflow Updates:**
   - Added separate PostGIS container startup in CI/CD
   - Updated import and run commands to link with PostGIS container
   - Updated cleanup to remove PostGIS container

6. **README.md Updates:**
   - Updated all examples to show external PostGIS setup
   - Added instructions for starting PostGIS container
   - Updated docker-compose instructions
   - Clarified volume usage (database volume now for PostGIS only)
   - Updated connection instructions

## New Architecture

```
┌─────────────────────────┐
│  Tile Server Container  │
│  - Apache               │
│  - Renderd              │
│  - osm2pgsql (client)   │
│  - psql (client)        │
└───────────┬─────────────┘
            │
            │ connects to
            ↓
┌─────────────────────────┐
│ PostGIS Container       │
│ postgis/postgis:18-3.6  │
│ - PostgreSQL 18         │
│ - PostGIS 3.6           │
└─────────────────────────┘
```

## Default Connection Parameters

- Host: `postgres` (container name)
- Port: `5432`
- User: `renderer`
- Password: `renderer`
- Database: `gis`

All parameters can be customized via environment variables.

## Benefits

1. **Separation of Concerns:** Database and tile rendering are now separate services
2. **Easier Scaling:** Database can be scaled independently
3. **Better Resource Management:** Can allocate resources separately to each service
4. **Simpler Upgrades:** Can upgrade database or tile server independently
5. **Standard PostGIS Image:** Uses official postgis/postgis image (version 18-3.6)
6. **Smaller Tile Server Image:** Reduced image size by removing PostgreSQL server

## Migration Steps for Existing Users

If you're migrating from the old setup:

1. **Export your existing data:**
   ```bash
   docker exec -it <old-container> pg_dump -U renderer gis > backup.sql
   ```

2. **Start new PostGIS container:**
   ```bash
   docker run -d --name postgres \
       -e POSTGRES_DB=gis \
       -e POSTGRES_USER=renderer \
       -e POSTGRES_PASSWORD=renderer \
       -v osm-data:/var/lib/postgresql/data \
       --shm-size=256M \
       postgis/postgis:18-3.6
   ```

3. **Import your data:**
   ```bash
   docker exec -i postgres psql -U renderer -d gis < backup.sql
   ```

4. **Start tile server with new setup:**
   ```bash
   docker run -d \
       -p 8080:80 \
       --link postgres:postgres \
       -e PGHOST=postgres \
       -v osm-tiles:/data/tiles/ \
       overv/openstreetmap-tile-server
   ```
   
   Note: The container now automatically detects if data has been imported. The legacy `run` command is still supported for backward compatibility but is no longer required.

## Docker Compose Usage

The easiest way to use the new setup is with docker-compose:

```bash
# Option 1: Auto-import with DOWNLOAD_PBF (recommended)
# Set DOWNLOAD_PBF in docker-compose.yml or .env file
docker-compose up -d

# Option 2: Mount a PBF file for auto-import
docker-compose run --rm -v /path/to/data.osm.pbf:/data/region.osm.pbf map

# Option 3: Legacy explicit import command (still supported)
docker-compose run --rm -v /path/to/data.osm.pbf:/data/region.osm.pbf map import
docker-compose up -d
```

The container will automatically detect if the database is empty and import data on first startup.

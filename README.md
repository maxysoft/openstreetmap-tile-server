# openstreetmap-tile-server

[![CI](https://github.com/maxysoft/openstreetmap-tile-server/actions/workflows/ci.yml/badge.svg)](https://github.com/maxysoft/openstreetmap-tile-server/actions/workflows/ci.yml) [![](https://images.microbadger.com/badges/image/overv/openstreetmap-tile-server.svg)](https://microbadger.com/images/overv/openstreetmap-tile-server "openstreetmap-tile-server")
[![Docker Image Version (latest semver)](https://img.shields.io/docker/v/overv/openstreetmap-tile-server?label=docker%20image)](https://hub.docker.com/r/overv/openstreetmap-tile-server/tags)

This container allows you to easily set up an OpenStreetMap PNG tile server given a `.osm.pbf` file. It is based on the [latest Ubuntu 18.04 LTS guide](https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/) from [switch2osm.org](https://switch2osm.org/) and therefore uses the default OpenStreetMap style.

**Base Image:** Debian Trixie (Stable) - `debian:trixie-20250929-slim`  
**Node.js Version:** 22.x LTS (Jod) with npm 10.9.3  
**Carto Version:** 1.2.0 (latest)  
**Tile Rendering:** Tirex 0.7.0 with Mapnik 4.0  
**OpenStreetMap Style:** openstreetmap-carto v5.9.0

**Note:** This tile server requires an external PostGIS database. The tile server container connects to a separate PostgreSQL/PostGIS instance (using the `postgis/postgis:18-3.6` image).

**Recent Change:** This tile server has been migrated from `renderd` to `tirex` for improved performance and compatibility with Debian Trixie. See the [Recent Updates](#recent-updates) section for details.

## Setting up and running the server

The tile server automatically detects if the database is empty and imports OSM data before starting. This means you can set up and run the server with a single command!

### Quick Start

First create Docker volumes to hold the PostgreSQL database and tiles:

    docker volume create osm-data
    docker volume create osm-tiles

Next, start a PostGIS database instance:

```
docker run -d --name postgres \
    -e POSTGRES_DB=gis \
    -e POSTGRES_USER=renderer \
    -e POSTGRES_PASSWORD=renderer \
    -v osm-data:/var/lib/postgresql/data \
    --shm-size=256M \
    postgis/postgis:18-3.6
```

Now start the tile server with automatic download and import:

```
docker run -p 8080:80 \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server
```

The container will:
1. Check if the database contains OSM data
2. If empty, automatically download and import the specified PBF file
3. Start the tile server

On subsequent restarts, the import step is automatically skipped.

### Alternative: Pre-downloaded files

If you already have an `.osm.pbf` file downloaded, you can mount it instead:

```
docker run -p 8080:80 \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server
```

Note that the import process requires an internet connection for downloading external data. If you want to run the openstreetmap-tile server on a computer that is isolated, you must first import on an internet connected computer, export the `osm-data` volume as a tarfile, and then restore the data volume on the target computer system.

Also when running on an isolated system, the default `index.html` from the container will not work, as it requires access to the web for the leaflet packages.

### Enabling automatic updates (optional)

If your import is an extract of the planet and has polygonal bounds associated with it, like those from [geofabrik.de](https://download.geofabrik.de/), then it is possible to set your server up for automatic updates. Include both the PBF and POLY files, and set the `UPDATES=enabled` variable:

```
docker run -p 8080:80 \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -e UPDATES=enabled \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server
```

Refer to the section *Automatic updating and tile expiry* to configure the update process.

Please note: If you're not importing the whole planet, then the `.poly` file is necessary to limit automatic updates to the relevant region.
Therefore, when you only have a `.osm.pbf` file but not a `.poly` file, you should not enable automatic updates.

### Using an alternate style

By default the container will use openstreetmap-carto if it is not specified. However, you can modify the style at run-time by mounting a custom style directory:

```
docker run -p 8080:80 \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -e NAME_LUA=sample.lua \
    -e NAME_STYLE=test.style \
    -e NAME_MML=project.mml \
    -e NAME_SQL=test.sql \
    -v /home/user/openstreetmap-carto-modified:/data/style/ \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server
```

If you do not define the "NAME_*" variables, the script will default to those found in the openstreetmap-carto style.

If you do not see the expected style, double check your paths as the style may not have been found at the directory specified. By default, `openstreetmap-carto` will be used if a style cannot be found.

**Only openstreetmap-carto and styles like it, eg, ones with one lua script, one style, one mml, one SQL can be used**

## How it works

The container automatically detects if the database contains OSM data on startup:
- **If empty**: Automatically imports data (from `DOWNLOAD_PBF` or mounted `/data/region.osm.pbf`), then starts the tile server
- **If data exists**: Skips import and starts the tile server immediately

This means you get the simplest possible workflow - just start the container and it handles everything!

Your tiles will be available at `http://localhost:8080/tile/{z}/{x}/{y}.png`. The demo map in `leaflet-demo.html` will be available on `http://localhost:8080`. Note that it will initially take quite a bit of time to render the larger tiles for the first time.

**Note:** The first-run import process may take a significant amount of time depending on the size of the data being imported. Monitor the container logs to track progress.

### Using Docker Compose

The `docker-compose.yml` file included with this repository shows how to run your server with a separate PostGIS database. Simply set the `DOWNLOAD_PBF` environment variable in your `docker-compose.yml` for the tile-server service, then start the services:

```
docker-compose up -d
```

The tile server will automatically download and import the data on first run, then start serving tiles. Subsequent restarts will skip the import step.

If you prefer to use a pre-downloaded PBF file, you can mount it instead of setting `DOWNLOAD_PBF`:

```
docker-compose run --rm -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf tile-server
```

### Legacy command support (backward compatibility)

For backward compatibility, the container still supports the legacy `import` and `run` commands:

```bash
# Legacy import-only command (imports data then exits)
docker run --rm ... overv/openstreetmap-tile-server import

# Legacy run command (same as no command - auto-imports if needed, then runs)
docker run ... overv/openstreetmap-tile-server run
```

However, these are optional. The recommended approach is to simply start the container without specifying a command, and it will automatically handle everything.

### Preserving rendered tiles and server state

**Single /data/ volume** (recommended): All persistent data is now stored under `/data/`:
- `/data/tiles/` - Rendered tile cache
- `/data/style/` - OpenStreetMap Carto style files
- `/data/region.osm.pbf` - Imported OSM data file
- `/data/region.poly` - Region boundary polygon
- `/data/planet-import-complete` - Import completion marker
- `/data/prerender-complete` - Pre-render completion marker
- `/data/.osmosis/` - Osmosis replication state (for updates)
- `/data/flat_nodes.bin` - Flat nodes cache (if FLAT_NODES enabled)

**Simplified volume mounting**:
```bash
docker volume create osm-data

docker run -p 8080:80 \
    -v osm-data:/data/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server
```

This single volume mount preserves:
- Rendered tiles across container restarts
- Import and prerender completion state
- Update replication state
- Region boundary configuration
- All server state for faster restarts

**Note**: The harmless warning "ERROR: Did not find table 'osm2pgsql_properties'" during first import is expected - osm2pgsql is checking for previous imports.

### Enabling automatic updating (optional)

Given that you've set up your import as described in the *Automatic updates* section during server setup, you can enable the updating process by setting the `UPDATES` variable while running your server as well:

```
docker run \
    -p 8080:80 \
    -e REPLICATION_URL=https://planet.openstreetmap.org/replication/minute/ \
    -e MAX_INTERVAL_SECONDS=60 \
    -e UPDATES=enabled \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server \
    run
```

This will enable a background process that automatically downloads changes from the OpenStreetMap server, filters them for the relevant region polygon you specified, updates the database and finally marks the affected tiles for rerendering.

### Tile expiration (optional)

Specify custom tile expiration settings to control which zoom level tiles are marked as expired when an update is performed. Tiles can be marked as expired in the cache (TOUCHFROM), but will still be served
until a new tile has been rendered, or deleted from the cache (DELETEFROM), so nothing will be served until a new tile has been rendered.

The example tile expiration values below are the default values.

```
docker run \
    -p 8080:80 \
    -e REPLICATION_URL=https://planet.openstreetmap.org/replication/minute/ \
    -e MAX_INTERVAL_SECONDS=60 \
    -e UPDATES=enabled \
    -e EXPIRY_MINZOOM=13 \
    -e EXPIRY_TOUCHFROM=13 \
    -e EXPIRY_DELETEFROM=19 \
    -e EXPIRY_MAXZOOM=20 \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server \
    run
```

### Cross-origin resource sharing

To enable the `Access-Control-Allow-Origin` header to be able to retrieve tiles from other domains, simply set the `ALLOW_CORS` variable to `enabled`:

```
docker run \
    -p 8080:80 \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -e ALLOW_CORS=enabled \
    -d overv/openstreetmap-tile-server \
    run
```

### Connecting to Postgres

To connect to the external PostgreSQL database, expose port 5432 on the PostGIS container:

```
docker run -d --name postgres \
    -e POSTGRES_DB=gis \
    -e POSTGRES_USER=renderer \
    -e POSTGRES_PASSWORD=renderer \
    -v osm-data:/var/lib/postgresql/data \
    -p 5432:5432 \
    --shm-size=256M \
    postgis/postgis:18-3.6
```

Use the user `renderer` and the database `gis` to connect.

```
psql -h localhost -U renderer gis
```

The default password is `renderer`, but it can be changed by setting the `POSTGRES_PASSWORD` environment variable when starting the PostGIS container, and the `PGPASSWORD` environment variable when starting the tile server.

## Performance tuning and tweaking

Details for update procedure and invoked scripts can be found here [link](https://ircama.github.io/osm-carto-tutorials/updating-data/).

### DEBUG_MODE

By default, the container runs without bash debug mode. You can enable debug mode by setting the `DEBUG_MODE` environment variable to `1` or `enabled`, which will show all executed commands in the logs (`set -x`). This can be helpful for debugging but may be verbose for production use:

```
docker run \
    -p 8080:80 \
    -e DEBUG_MODE=1 \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server
```

### THREADS

The import and tile serving processes use 4 threads by default, but this number can be changed by setting the `THREADS` environment variable. For example:
```
docker run \
    -p 8080:80 \
    -e THREADS=24 \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server \
    run
```

### CACHE

The import and tile serving processes use 800 MB RAM cache by default, but this number can be changed by option -C. For example:
```
docker run \
    -p 8080:80 \
    -e "OSM2PGSQL_EXTRA_ARGS=-C 4096" \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server \
    run
```

### AUTOVACUUM

The PostgreSQL database has the autovacuum feature enabled by default. You can configure this in the PostGIS container by setting appropriate PostgreSQL configuration parameters. See the [PostGIS documentation](https://hub.docker.com/r/postgis/postgis) for details.

### FLAT_NODES

If you are planning to import the entire planet or you are running into memory errors then you may want to enable the `--flat-nodes` option for osm2pgsql. You can then use it during the import process as follows:

```
docker run --rm \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -e "FLAT_NODES=enabled" \
    overv/openstreetmap-tile-server \
    import
```

Warning: enabling `FLAT_NODES` together with `UPDATES` only works for entire planet imports (without a `.poly` file).  Otherwise this will break the automatic update script. This is because trimming the differential updates to the specific regions currently isn't supported when using flat nodes.

### Benchmarks

You can find an example of the import performance to expect with this image on the [OpenStreetMap wiki](https://wiki.openstreetmap.org/wiki/Osm2pgsql/benchmarks#debian_9_.2F_openstreetmap-tile-server).

## Troubleshooting

### ERROR: could not resize shared memory segment / No space left on device

If you encounter such entries in the log, it will mean that the default shared memory limit (64 MB) is too low for the containers and it should be raised:
```
renderd[121]: ERROR: failed to render TILE default 2 0-3 0-3
renderd[121]: reason: Postgis Plugin: ERROR: could not resize shared memory segment "/PostgreSQL.790133961" to 12615680 bytes: ### No space left on device
```
To raise it use `--shm-size` parameter on both the PostGIS container and the tile server container. For example:
```
docker run -d --name postgres \
    -e POSTGRES_DB=gis \
    -e POSTGRES_USER=renderer \
    -e POSTGRES_PASSWORD=renderer \
    -v osm-data:/var/lib/postgresql/data \
    --shm-size="256m" \
    postgis/postgis:18-3.6

docker run \
    -p 8080:80 \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    --shm-size="192m" \
    -d overv/openstreetmap-tile-server \
    run
```
For too high values you may notice excessive CPU load and memory usage. It might be that you will have to experimentally find the best values for yourself.

### The import process unexpectedly exits

You may be running into problems with memory usage during the import. Have a look at the "Flat nodes" section in this README.

## Recent Updates

### Migration to Tirex (October 2025)

The tile server has been migrated from `renderd` to `tirex` for better compatibility with Debian Trixie and improved tile rendering:

- **Tile Rendering**: Switched from `renderd` (mod_tile) to `tirex` 0.7.0
- **Mapnik Version**: Using Mapnik 4.0 (included with Debian Trixie)
- **OpenStreetMap Style**: Updated to openstreetmap-carto v5.9.0 for latest bug fixes
- **Architecture Changes**:
  - Replaced `renderd` daemon with `tirex-master` and `tirex-backend-manager`
  - Updated socket path from `/run/renderd/renderd.sock` to `/run/tirex/modtile.sock`
  - Updated tile cache directory from `/var/cache/renderd` to `/var/cache/tirex`
  - Pre-rendering now uses `tirex-batch` instead of `render_list`
  - Tile expiry uses custom logic compatible with tirex
- **New Features**:
  - Added `DEBUG_MODE` environment variable to enable bash debug output
  - Improved tile caching configuration in Apache
  - Better separation between master and backend rendering processes
- **Benefits**:
  - More robust tile rendering with tirex's proven architecture
  - Better compatibility with Debian Trixie packages
  - Improved performance and scalability
  - Active maintenance and community support

### Base Image Migration (October 2025)

The tile server has been migrated from Ubuntu 22.04 to Debian Trixie (Stable) for improved performance and smaller image size:

- **Base Image**: `debian:trixie-20250929-slim` (was `ubuntu:22.04`)
- **Node.js**: Upgraded to 22.20.0 LTS (Jod) with npm 10.9.3 (was using system npm)
- **Package Changes**:
  - Replaced `unrar` with `unrar-free` (Debian native package)
  - Replaced `pip install osmium` with `python3-pyosmium` (Debian native package)
  - Node.js now installed from NodeSource repository for latest LTS version
- **Performance**: Reduced Docker layers and improved build caching
- **Benefits**: 
  - Smaller base image size
  - Better security with Debian's stable packages
  - Modern Node.js LTS for better npm package support
  - All packages upgraded to latest compatible versions

For migration details, see [TRIXIE_MIGRATION_PLAN.md](TRIXIE_MIGRATION_PLAN.md).

## License

```
Copyright 2019 Alexander Overvoorde

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    https://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

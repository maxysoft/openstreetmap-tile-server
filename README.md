# openstreetmap-tile-server

[![Build Status](https://travis-ci.org/Overv/openstreetmap-tile-server.svg?branch=master)](https://travis-ci.org/Overv/openstreetmap-tile-server) [![](https://images.microbadger.com/badges/image/overv/openstreetmap-tile-server.svg)](https://microbadger.com/images/overv/openstreetmap-tile-server "openstreetmap-tile-server")
[![Docker Image Version (latest semver)](https://img.shields.io/docker/v/overv/openstreetmap-tile-server?label=docker%20image)](https://hub.docker.com/r/overv/openstreetmap-tile-server/tags)

This container allows you to easily set up an OpenStreetMap PNG tile server given a `.osm.pbf` file. It is based on the [latest Ubuntu 18.04 LTS guide](https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/) from [switch2osm.org](https://switch2osm.org/) and therefore uses the default OpenStreetMap style.

**Note:** This tile server requires an external PostGIS database. The tile server container connects to a separate PostgreSQL/PostGIS instance (using the `postgis/postgis:18-3.6` image).

## Setting up the server

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

Next, download an `.osm.pbf` extract from geofabrik.de for the region that you're interested in. You can then start importing it into PostgreSQL by running a container and mounting the file as `/data/region.osm.pbf`. For example:

```
docker run --rm \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    --link postgres:postgres \
    -e PGHOST=postgres \
    overv/openstreetmap-tile-server \
    import
```

If the container exits without errors, then your data has been successfully imported and you are now ready to run the tile server.

Note that the import process requires an internet connection. The run process does not require an internet connection. If you want to run the openstreetmap-tile server on a computer that is isolated, you must first import on an internet connected computer, export the `osm-data` volume as a tarfile, and then restore the data volume on the target computer system.

Also when running on an isolated system, the default `index.html` from the container will not work, as it requires access to the web for the leaflet packages.

### Automatic updates (optional)

If your import is an extract of the planet and has polygonal bounds associated with it, like those from [geofabrik.de](https://download.geofabrik.de/), then it is possible to set your server up for automatic updates. Make sure to reference both the OSM file and the polygon file during the `import` process to facilitate this, and also include the `UPDATES=enabled` variable:

```
docker run --rm \
    -e UPDATES=enabled \
    -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf \
    -v /absolute/path/to/luxembourg.poly:/data/region.poly \
    --link postgres:postgres \
    -e PGHOST=postgres \
    overv/openstreetmap-tile-server \
    import
```

Refer to the section *Automatic updating and tile expiry* to actually enable the updates while running the tile server.

Please note: If you're not importing the whole planet, then the `.poly` file is necessary to limit automatic updates to the relevant region.
Therefore, when you only have a `.osm.pbf` file but not a `.poly` file, you should not enable automatic updates.

### Letting the container download the file

It is also possible to let the container download files for you rather than mounting them in advance by using the `DOWNLOAD_PBF` and `DOWNLOAD_POLY` parameters:

```
docker run --rm \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    --link postgres:postgres \
    -e PGHOST=postgres \
    overv/openstreetmap-tile-server \
    import
```

### Using an alternate style

By default the container will use openstreetmap-carto if it is not specified. However, you can modify the style at run-time. Be aware you need the style mounted at `run` AND `import` as the Lua script needs to be run:

```
docker run --rm \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/luxembourg.poly \
    -e NAME_LUA=sample.lua \
    -e NAME_STYLE=test.style \
    -e NAME_MML=project.mml \
    -e NAME_SQL=test.sql \
    -v /home/user/openstreetmap-carto-modified:/data/style/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    overv/openstreetmap-tile-server \
    import
```

If you do not define the "NAME_*" variables, the script will default to those found in the openstreetmap-carto style.

Be sure to mount the volume during `run` with the same `-v /home/user/openstreetmap-carto-modified:/data/style/`

If you do not see the expected style upon `run` double check your paths as the style may not have been found at the directory specified. By default, `openstreetmap-carto` will be used if a style cannot be found

**Only openstreetmap-carto and styles like it, eg, ones with one lua script, one style, one mml, one SQL can be used**

## Running the server

Run the server like this (assuming you already have the PostGIS container running from the setup step):

```
docker run \
    -p 8080:80 \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server \
    run
```

Your tiles will now be available at `http://localhost:8080/tile/{z}/{x}/{y}.png`. The demo map in `leaflet-demo.html` will then be available on `http://localhost:8080`. Note that it will initially take quite a bit of time to render the larger tiles for the first time.

### Using Docker Compose

The `docker-compose.yml` file included with this repository shows how the aforementioned commands can be used with Docker Compose to run your server with a separate PostGIS database. To use it:

1. First, import your data:
```
docker-compose run --rm -v /absolute/path/to/luxembourg.osm.pbf:/data/region.osm.pbf map import
```

2. Then start the services:
```
docker-compose up -d
```

### Preserving rendered tiles

Tiles that have already been rendered will be stored in `/data/tiles/`. The tiles volume is already configured in the examples above to persist rendered tiles across container restarts.

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

Warning: enabling `FLAT_NOTES` together with `UPDATES` only works for entire planet imports (without a `.poly` file).  Otherwise this will break the automatic update script. This is because trimming the differential updates to the specific regions currently isn't supported when using flat nodes.

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

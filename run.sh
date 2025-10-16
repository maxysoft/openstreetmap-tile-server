#!/bin/bash

set -euo pipefail

# Enable bash debug mode if requested
if [ "${DEBUG_MODE:-}" == "1" ] || [ "${DEBUG_MODE:-}" == "enabled" ]; then
    set -x
fi

function waitForPostgres() {
    echo "Waiting for PostgreSQL at ${PGHOST}:${PGPORT}..."
    until PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c '\q' 2>/dev/null; do
        echo "PostgreSQL is unavailable - sleeping"
        sleep 2
    done
    echo "PostgreSQL is up!"
}

function setupDatabase() {
    echo "Setting up database..."
    # Check if database already has PostGIS extension
    if ! PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c "SELECT 1 FROM pg_extension WHERE extname='postgis'" 2>/dev/null | grep -q 1; then
        echo "Creating PostGIS extension..."
        PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c "CREATE EXTENSION IF NOT EXISTS postgis;"
        # Note: In PostGIS 3.x, geometry_columns and spatial_ref_sys are views, not tables
        # so we don't need to change their ownership
    fi
    # Check if database already has hstore extension
    if ! PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c "SELECT 1 FROM pg_extension WHERE extname='hstore'" 2>/dev/null | grep -q 1; then
        echo "Creating hstore extension..."
        PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c "CREATE EXTENSION IF NOT EXISTS hstore;"
    fi
}



# Support legacy command arguments for backward compatibility
# New behavior: if no argument provided, automatically detect and import if needed, then run
COMMAND="${1:-}"

if [ -n "$COMMAND" ] && [ "$COMMAND" != "import" ] && [ "$COMMAND" != "run" ]; then
    echo "usage: [import|run]"
    echo "commands (optional):"
    echo "    import: Set up the database and import /data/region.osm.pbf, then exit"
    echo "    run: Check database, auto-import if needed, then run tile server"
    echo "    (no command): Same as 'run' - auto-import if needed, then run tile server"
    echo "environment variables:"
    echo "    THREADS: defines number of threads used for importing / tile rendering"
    echo "    UPDATES: consecutive updates (enabled/disabled)"
    echo "    NAME_LUA: name of .lua script to run as part of the style"
    echo "    NAME_STYLE: name of the .style to use"
    echo "    NAME_MML: name of the .mml file to render to mapnik.xml"
    echo "    NAME_SQL: name of the .sql file to use"
    exit 1
fi

# Ensure required directories exist (in case of bind mounts)
mkdir -p /data/style/
mkdir -p /data/tiles/

# if there is no custom style mounted, then use osm-carto
if [ ! "$(ls -A /data/style/)" ]; then
    mv /home/renderer/src/openstreetmap-carto-backup/* /data/style/
fi

# carto build
if [ ! -f /data/style/mapnik.xml ]; then
    cd /data/style/
    
    # Configure PostgreSQL connection parameters in project.mml
    if [ -f ${NAME_MML:-project.mml} ]; then
        # Update the osm2pgsql section with external PostgreSQL connection parameters
        sed -i 's/dbname: "gis"/dbname: "'${PGDATABASE:-gis}'"/' ${NAME_MML:-project.mml}
        
        # Add host, port, user, and password if not connecting to local socket
        if [ "${PGHOST:-postgres}" != "localhost" ] && [ "${PGHOST:-postgres}" != "127.0.0.1" ]; then
            # Add host parameter after dbname line
            sed -i '/dbname: "'${PGDATABASE:-gis}'"/a\    host: "'${PGHOST:-postgres}'"' ${NAME_MML:-project.mml}
            # Add port parameter (as number, not string)
            sed -i '/host: "'${PGHOST:-postgres}'"/a\    port: '${PGPORT:-5432} ${NAME_MML:-project.mml}
            # Add user parameter
            sed -i '/port: '${PGPORT:-5432}'/a\    user: "'${PGUSER:-renderer}'"' ${NAME_MML:-project.mml}
            # Add password parameter
            sed -i '/user: "'${PGUSER:-renderer}'"/a\    password: "'${PGPASSWORD:-renderer}'"' ${NAME_MML:-project.mml}
        fi
    fi
    
    carto ${NAME_MML:-project.mml} > mapnik.xml
fi

# Function to perform the import process
function performImport() {
    echo "========================================"
    echo "Starting OSM data import process..."
    echo "========================================"
    
    # Ensure that data directory exists
    mkdir -p /data/
    chown renderer: /data/

    # Setup database extensions
    setupDatabase

    # Download Luxembourg as sample if no data is provided
    if [ ! -f /data/region.osm.pbf ] && [ -z "${DOWNLOAD_PBF:-}" ]; then
        echo "WARNING: No import file at /data/region.osm.pbf, so importing Luxembourg as example..."
        DOWNLOAD_PBF="https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf"
        DOWNLOAD_POLY="https://download.geofabrik.de/europe/luxembourg.poly"
    fi

    if [ -n "${DOWNLOAD_PBF:-}" ]; then
        echo "INFO: Download PBF file: $DOWNLOAD_PBF"
        wget ${WGET_ARGS:-} "$DOWNLOAD_PBF" -O /data/region.osm.pbf
        if [ -n "${DOWNLOAD_POLY:-}" ]; then
            echo "INFO: Download PBF-POLY file: $DOWNLOAD_POLY"
            wget ${WGET_ARGS:-} "$DOWNLOAD_POLY" -O /data/region.poly
        fi
    fi

    if [ "${UPDATES:-}" == "enabled" ] || [ "${UPDATES:-}" == "1" ]; then
        # determine and set osmosis_replication_timestamp (for consecutive updates)
        REPLICATION_TIMESTAMP=`osmium fileinfo -g header.option.osmosis_replication_timestamp /data/region.osm.pbf`

        # initial setup of osmosis workspace (for consecutive updates)
        sudo -E -u renderer openstreetmap-tiles-update-expire.sh $REPLICATION_TIMESTAMP
    fi

    # copy polygon file if available (no-op now since it's in the same location)
    # Region poly is already at /data/region.poly

    # flat-nodes
    if [ "${FLAT_NODES:-}" == "enabled" ] || [ "${FLAT_NODES:-}" == "1" ]; then
        mkdir -p /data/
        chown renderer: /data/
        OSM2PGSQL_EXTRA_ARGS="${OSM2PGSQL_EXTRA_ARGS:-} --flat-nodes /data/flat_nodes.bin"
    fi

    # Import data
    sudo -E -u renderer osm2pgsql -d ${PGDATABASE:-gis} -H ${PGHOST:-postgres} -P ${PGPORT:-5432} -U ${PGUSER:-renderer} --create --slim -G --hstore  \
      --tag-transform-script /data/style/${NAME_LUA:-openstreetmap-carto.lua}  \
      --number-processes ${THREADS:-4}  \
      -S /data/style/${NAME_STYLE:-openstreetmap-carto.style}  \
      /data/region.osm.pbf  \
      ${OSM2PGSQL_EXTRA_ARGS:-}  \
    ;

    # old flat-nodes dir - migrate to new location
    if [ -f /nodes/flat_nodes.bin ] && ! [ -f /data/flat_nodes.bin ]; then
        mkdir -p /data/
        mv /nodes/flat_nodes.bin /data/flat_nodes.bin
        chown renderer: /data/flat_nodes.bin
    fi
    # Migrate from old /data/osm-flatnodes/ or /data/database/ location
    if [ -f /data/database/flat_nodes.bin ] && ! [ -f /data/flat_nodes.bin ]; then
        mv /data/database/flat_nodes.bin /data/flat_nodes.bin
        chown renderer: /data/flat_nodes.bin
    fi
    if [ -f /data/osm-flatnodes/flat_nodes.bin ] && ! [ -f /data/flat_nodes.bin ]; then
        mv /data/osm-flatnodes/flat_nodes.bin /data/flat_nodes.bin
        chown renderer: /data/flat_nodes.bin
    fi

    # Create database functions (required for openstreetmap-carto)
    if [ -f /data/style/functions.sql ]; then
        echo "Creating database functions..."
        PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -f /data/style/functions.sql
    fi

    # Create indexes
    if [ -f /data/style/${NAME_SQL:-indexes.sql} ]; then
        echo "Creating indexes..."
        PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -f /data/style/${NAME_SQL:-indexes.sql}
    fi

    #Import external data
    chown -R renderer: /home/renderer/src/ /data/style/
    if [ -f /data/style/scripts/get-external-data.py ] && [ -f /data/style/external-data.yml ]; then
        sudo -E -u renderer python3 /data/style/scripts/get-external-data.py -c /data/style/external-data.yml -D /data/style/data -d ${PGDATABASE:-gis} -H ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer}
    fi

    # Register that data has changed for mod_tile caching purposes
    sudo -u renderer touch /data/planet-import-complete
    
    echo "========================================"
    echo "Import completed successfully!"
    echo "========================================"
}

# Legacy support: if explicitly called with "import", do import and exit
if [ "$COMMAND" == "import" ]; then
    # Wait for PostgreSQL to be ready
    waitForPostgres
    
    performImport
    
    exit 0
fi

# Default behavior: Check database and auto-import if needed, then run tile server
# This runs when COMMAND is "run" or empty (no command specified)
# Clean /tmp
rm -rf /tmp/*

# migrate old files
if [ -f /nodes/flat_nodes.bin ] && ! [ -f /data/flat_nodes.bin ]; then
    mkdir -p /data/
    mv /nodes/flat_nodes.bin /data/flat_nodes.bin
fi
# Migrate from old /data/osm-flatnodes/ or /data/database/ location
if [ -f /data/database/flat_nodes.bin ] && ! [ -f /data/flat_nodes.bin ]; then
    mv /data/database/flat_nodes.bin /data/flat_nodes.bin
fi
if [ -f /data/osm-flatnodes/flat_nodes.bin ] && ! [ -f /data/flat_nodes.bin ]; then
    mv /data/osm-flatnodes/flat_nodes.bin /data/flat_nodes.bin
fi
if [ -f /data/tiles/data.poly ] && ! [ -f /data/region.poly ]; then
    mv /data/tiles/data.poly /data/region.poly
fi

# sync planet-import-complete file
if [ -f /data/tiles/planet-import-complete ] && ! [ -f /data/planet-import-complete ]; then
    cp /data/tiles/planet-import-complete /data/planet-import-complete
fi
if [ -f /data/database/planet-import-complete ] && ! [ -f /data/planet-import-complete ]; then
    cp /data/database/planet-import-complete /data/planet-import-complete
fi
# Ensure backwards compatibility - keep copy in /data/tiles/ too
if ! [ -f /data/tiles/planet-import-complete ] && [ -f /data/planet-import-complete ]; then
    cp /data/planet-import-complete /data/tiles/planet-import-complete
fi

# Ensure proper permissions for tile directory
chown -R renderer: /data/tiles /var/cache/tirex

# Wait for PostgreSQL to be ready
waitForPostgres

# Check if database has been imported
echo "Checking if database has been imported..."
if ! PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c "SELECT 1 FROM information_schema.tables WHERE table_name='planet_osm_polygon'" 2>/dev/null | grep -q 1; then
    echo "Database is empty - import required."
    
    # Check if we have import data available
    if [ -f /data/region.osm.pbf ] || [ -n "${DOWNLOAD_PBF:-}" ]; then
        echo "Import data available - starting automatic import..."
        performImport
    else
        echo ""
        echo "========================================"
        echo "ERROR: Database is empty and no import data is available!"
        echo "========================================"
        echo ""
        echo "Please provide OSM data in one of the following ways:"
        echo ""
        echo "1. Set DOWNLOAD_PBF environment variable:"
        echo "   -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf"
        echo ""
        echo "2. Mount a PBF file:"
        echo "   -v /path/to/region.osm.pbf:/data/region.osm.pbf"
        echo ""
        exit 1
    fi
else
    echo "Database already contains imported OSM data - skipping import."
fi

# Configure tirex backend processes based on THREADS
sed -i -E "s/^procs=.*/procs=${THREADS:-4}/g" /etc/tirex/renderer/mapnik.conf

# Ensure tirex directories exist with proper permissions
mkdir -p /run/tirex /var/cache/tirex/stats
chown -R renderer: /run/tirex /var/cache/tirex

# Start tirex-master first (in foreground mode with -f flag)
echo "Starting tirex-master..."
sudo -u renderer tirex-master -f &
TIREX_MASTER_PID=$!

# Wait for tirex-master to be ready and create its socket
echo "Waiting for tirex-master socket..."
for i in {1..30}; do
    if [ -S /run/tirex/master.sock ]; then
        echo "Tirex-master socket is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Tirex-master socket not created after 30 seconds"
        exit 1
    fi
    sleep 1
done

# Start tirex-backend-manager (in foreground mode with -f flag)
echo "Starting tirex-backend-manager..."
sudo -u renderer tirex-backend-manager -f &
TIREX_BACKEND_PID=$!

# Wait for tirex socket to be created
echo "Waiting for tirex socket..."
for i in {1..30}; do
    if [ -S /run/tirex/modtile.sock ]; then
        echo "Tirex socket is ready!"
        break
    fi
    if [ $i -eq 30 ]; then
        echo "ERROR: Tirex socket not created after 30 seconds"
        exit 1
    fi
    sleep 1
done

# Configure Apache CORS
if [ "${ALLOW_CORS:-}" == "enabled" ] || [ "${ALLOW_CORS:-}" == "1" ]; then
    echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars
fi

# Initialize Apache after renderd is ready
echo "Starting Apache..."
service apache2 restart

# Pre-render tiles if requested using tirex-batch
if [ -n "${PRERENDER_ZOOMS:-}" ] && [ "${PRERENDER_ZOOMS:-}" != "disabled" ]; then
    # Check if we need to pre-render (only do this once)
    if [ ! -f /data/prerender-complete ]; then
        echo "========================================"
        echo "Pre-rendering tiles for zoom levels: ${PRERENDER_ZOOMS}"
        echo "This is a one-time operation and may take 1-2 hours for zoom 0-12"
        echo "========================================"
        
        # Parse zoom range (e.g., "0-12" -> min=0, max=12)
        ZOOM_MIN=$(echo "${PRERENDER_ZOOMS}" | cut -d'-' -f1)
        ZOOM_MAX=$(echo "${PRERENDER_ZOOMS}" | cut -d'-' -f2)
        
        # Run tirex-batch in background to avoid blocking startup
        # tirex-batch uses a different format than render_list
        sudo -u renderer tirex-batch --prio=20 map=default z=${ZOOM_MIN}-${ZOOM_MAX} &
        PRERENDER_PID=$!
        
        # Wait for pre-rendering to complete (run in background)
        (
            wait $PRERENDER_PID
            touch /data/prerender-complete
            echo "========================================"
            echo "Pre-rendering completed for zoom ${ZOOM_MIN}-${ZOOM_MAX}"
            echo "========================================"
        ) &
        
        echo "Pre-rendering started in background (PID: $PRERENDER_PID)"
        echo "Server will continue starting while pre-rendering runs in background"
    else
        echo "Pre-rendering already completed (found /data/prerender-complete)"
        echo "To re-run pre-rendering, delete /data/prerender-complete"
    fi
fi

# start cron job to trigger consecutive updates
if [ "${UPDATES:-}" == "enabled" ] || [ "${UPDATES:-}" == "1" ]; then
    /etc/init.d/cron start
    sudo -u renderer touch /var/log/tiles/run.log; tail -f /var/log/tiles/run.log >> /proc/1/fd/1 &
    sudo -u renderer touch /var/log/tiles/osmosis.log; tail -f /var/log/tiles/osmosis.log >> /proc/1/fd/1 &
    sudo -u renderer touch /var/log/tiles/expiry.log; tail -f /var/log/tiles/expiry.log >> /proc/1/fd/1 &
    sudo -u renderer touch /var/log/tiles/osm2pgsql.log; tail -f /var/log/tiles/osm2pgsql.log >> /proc/1/fd/1 &

fi

# Run while handling docker stop's SIGTERM
stop_handler() {
    kill -TERM "$TIREX_MASTER_PID" "$TIREX_BACKEND_PID"
}
trap stop_handler SIGTERM

wait "$TIREX_MASTER_PID"

exit 0

#!/bin/bash

set -euo pipefail

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
        PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c "ALTER TABLE geometry_columns OWNER TO ${PGUSER:-renderer};"
        PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c "ALTER TABLE spatial_ref_sys OWNER TO ${PGUSER:-renderer};"
    fi
    # Check if database already has hstore extension
    if ! PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c "SELECT 1 FROM pg_extension WHERE extname='hstore'" 2>/dev/null | grep -q 1; then
        echo "Creating hstore extension..."
        PGPASSWORD=${PGPASSWORD:-renderer} psql -h ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer} -d ${PGDATABASE:-gis} -c "CREATE EXTENSION IF NOT EXISTS hstore;"
    fi
}

if [ "$#" -ne 1 ]; then
    echo "usage: <import|run>"
    echo "commands:"
    echo "    import: Set up the database and import /data/region.osm.pbf"
    echo "    run: Runs Apache and renderd to serve tiles at /tile/{z}/{x}/{y}.png"
    echo "environment variables:"
    echo "    THREADS: defines number of threads used for importing / tile rendering"
    echo "    UPDATES: consecutive updates (enabled/disabled)"
    echo "    NAME_LUA: name of .lua script to run as part of the style"
    echo "    NAME_STYLE: name of the .style to use"
    echo "    NAME_MML: name of the .mml file to render to mapnik.xml"
    echo "    NAME_SQL: name of the .sql file to use"
    exit 1
fi

set -x

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

if [ "$1" == "import" ]; then
    # Ensure that database directory exists
    mkdir -p /data/database/
    chown renderer: /data/database/

    # Wait for PostgreSQL to be ready
    waitForPostgres
    
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

    # copy polygon file if available
    if [ -f /data/region.poly ]; then
        cp /data/region.poly /data/database/region.poly
        chown renderer: /data/database/region.poly
    fi

    # flat-nodes
    if [ "${FLAT_NODES:-}" == "enabled" ] || [ "${FLAT_NODES:-}" == "1" ]; then
        OSM2PGSQL_EXTRA_ARGS="${OSM2PGSQL_EXTRA_ARGS:-} --flat-nodes /data/database/flat_nodes.bin"
    fi

    # Import data
    sudo -E -u renderer osm2pgsql -d ${PGDATABASE:-gis} -H ${PGHOST:-postgres} -P ${PGPORT:-5432} -U ${PGUSER:-renderer} --create --slim -G --hstore  \
      --tag-transform-script /data/style/${NAME_LUA:-openstreetmap-carto.lua}  \
      --number-processes ${THREADS:-4}  \
      -S /data/style/${NAME_STYLE:-openstreetmap-carto.style}  \
      /data/region.osm.pbf  \
      ${OSM2PGSQL_EXTRA_ARGS:-}  \
    ;

    # old flat-nodes dir
    if [ -f /nodes/flat_nodes.bin ] && ! [ -f /data/database/flat_nodes.bin ]; then
        mv /nodes/flat_nodes.bin /data/database/flat_nodes.bin
        chown renderer: /data/database/flat_nodes.bin
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
        sudo -E -u renderer python3 /data/style/scripts/get-external-data.py -c /data/style/external-data.yml -D /data/style/data
    fi

    # Register that data has changed for mod_tile caching purposes
    sudo -u renderer touch /data/database/planet-import-complete

    exit 0
fi

if [ "$1" == "run" ]; then
    # Clean /tmp
    rm -rf /tmp/*

    # migrate old files
    if [ -f /nodes/flat_nodes.bin ] && ! [ -f /data/database/flat_nodes.bin ]; then
        mv /nodes/flat_nodes.bin /data/database/flat_nodes.bin
    fi
    if [ -f /data/tiles/data.poly ] && ! [ -f /data/database/region.poly ]; then
        mv /data/tiles/data.poly /data/database/region.poly
    fi

    # sync planet-import-complete file
    if [ -f /data/tiles/planet-import-complete ] && ! [ -f /data/database/planet-import-complete ]; then
        cp /data/tiles/planet-import-complete /data/database/planet-import-complete
    fi
    if ! [ -f /data/tiles/planet-import-complete ] && [ -f /data/database/planet-import-complete ]; then
        cp /data/database/planet-import-complete /data/tiles/planet-import-complete
    fi

    # Ensure proper permissions for tile directory
    chown -R renderer: /data/tiles /var/cache/renderd

    # Wait for PostgreSQL to be ready
    waitForPostgres

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /etc/renderd.conf

    # Start renderd first and wait for socket
    echo "Starting renderd..."
    sudo -u renderer renderd -f -c /etc/renderd.conf &
    RENDERD_PID=$!

    # Wait for renderd socket to be created
    echo "Waiting for renderd socket..."
    for i in {1..30}; do
        if [ -S /run/renderd/renderd.sock ]; then
            echo "Renderd socket is ready!"
            break
        fi
        if [ $i -eq 30 ]; then
            echo "ERROR: Renderd socket not created after 30 seconds"
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
        kill -TERM "$RENDERD_PID"
    }
    trap stop_handler SIGTERM

    wait "$RENDERD_PID"

    exit 0
fi

echo "invalid command"
exit 1

#!/bin/sh

set -e

#------------------------------------------------------------------------------
# Change directory to mod_tile directory so that we can run replag
# and other things directly from this script when run from cron.
# Change the actual location to wherever installed locally.
#------------------------------------------------------------------------------
# Extra OSM2PGSQL_OPTIONS may need setting if a tag transform script is
# in use.  See https://github.com/SomeoneElseOSM/SomeoneElse-style and
# http://wiki.openstreetmap.org/wiki/User:SomeoneElse/Ubuntu_1404_tileserver_load
# The database name always needs setting.
#------------------------------------------------------------------------------
OSMOSIS_BIN=osmosis
OSM2PGSQL_BIN=osm2pgsql
TRIM_BIN=/home/renderer/src/regional/trim_osc.py

DBNAME=${PGDATABASE:-gis}
OSM2PGSQL_OPTIONS="-d $DBNAME -H ${PGHOST:-postgres} -P ${PGPORT:-5432} -U ${PGUSER:-renderer} -G --hstore --tag-transform-script /data/style/${NAME_LUA:-openstreetmap-carto.lua} --number-processes ${THREADS:-4} -S /data/style/${NAME_STYLE:-openstreetmap-carto.style} ${OSM2PGSQL_EXTRA_ARGS}"

# flat-nodes
if [ -f /data/flat_nodes.bin ]; then
    OSM2PGSQL_OPTIONS="${OSM2PGSQL_OPTIONS} --flat-nodes /data/flat_nodes.bin"
fi

#------------------------------------------------------------------------------
# When using trim_osc.py we can define either a bounding box (such as this
# example for England and Wales) or a polygon.
# See https://github.com/zverik/regional .
# This area will usually correspond to the data originally loaded.
#------------------------------------------------------------------------------
TRIM_POLY_FILE="/data/region.poly"
TRIM_OPTIONS="-d $DBNAME -H ${PGHOST:-postgres} -p ${PGPORT:-5432} -U ${PGUSER:-renderer}"
TRIM_REGION_OPTIONS="-p $TRIM_POLY_FILE"

BASE_DIR=/data
LOG_DIR=/var/log/tiles
WORKOSM_DIR=$BASE_DIR/.osmosis

LOCK_FILE=/tmp/openstreetmap-update-expire-lock.txt
CHANGE_FILE=$BASE_DIR/changes.osc.gz
EXPIRY_FILE=$BASE_DIR/dirty_tiles
STOP_FILE=$BASE_DIR/stop.txt

OSMOSISLOG=$LOG_DIR/osmosis.log
PGSQLLOG=$LOG_DIR/osm2pgsql.log
EXPIRYLOG=$LOG_DIR/expiry.log
RUNLOG=$LOG_DIR/run.log

#------------------------------------------------------------------------------
# The tile expiry section below can re-render, delete or dirty expired tiles.
# By default, tiles between EXPIRY_MINZOOM and EXPIRY_MAXZOOM are rerendered.
# "render_expired" can optionally delete (and/or dirty) tiles above a certail
# threshold rather than rendering them.
# Here we expire (but don't immediately rerender) tiles between zoom levels
# 13 and 18 and delete between 19 and 20.
#------------------------------------------------------------------------------
EXPIRY_MINZOOM=${EXPIRY_MINZOOM:="13"}
EXPIRY_TOUCHFROM=${EXPIRY_TOUCHFROM:="13"}
EXPIRY_DELETEFROM=${EXPIRY_DELETEFROM:="19"}
EXPIRY_MAXZOOM=${EXPIRY_MAXZOOM:="20"}

#*************************************************************************
#*************************************************************************

m_info()
{
    echo "[`date +"%Y-%m-%d %H:%M:%S"`] $$ $1" >> "$RUNLOG"
}

m_error()
{
    echo "[`date +"%Y-%m-%d %H:%M:%S"`] $$ [error] $1" >> "$RUNLOG"

    m_info "resetting state"
    /bin/cp $WORKOSM_DIR/last.state.txt $WORKOSM_DIR/state.txt || true

    rm "$CHANGE_FILE" || true
    rm "$EXPIRY_FILE.$$" || true
    rm "$LOCK_FILE"
    exit
}

m_ok()
{
    echo "[`date +"%Y-%m-%d %H:%M:%S"`] $$ $1" >> "$RUNLOG"
}

getlock()
{
    if [ -s $1 ]; then
        if [ "$(ps -p `cat $1` | wc -l)" -gt 1 ]; then
            return 1 #false
        fi
    fi

    echo $$ >"$1"
    return 0 #true
}

freelock()
{
    rm "$1"
    rm "$CHANGE_FILE"
}


if [ $# -eq 1 ] ; then
    m_info "Initialising Osmosis replication system to $1"
    mkdir -p $WORKOSM_DIR
    $OSMOSIS_BIN -v 5 --read-replication-interval-init workingDirectory=$WORKOSM_DIR 1>&2 2> "$OSMOSISLOG"

    init_seq=$(/usr/lib/python3-pyosmium/pyosmium-get-changes --server $REPLICATION_URL -D $1)
    url_dynamicPart=$(printf %09d $init_seq | sed 's_\([0-9][0-9][0-9]\)\([0-9][0-9][0-9]\)\([0-9][0-9][0-9]\)_\1/\2/\3_')
    wget $REPLICATION_URL/$url_dynamicPart.state.txt -O $WORKOSM_DIR/state.txt

    cat > $WORKOSM_DIR/configuration.txt <<- EOM
baseUrl=$REPLICATION_URL
maxInterval=$MAX_INTERVAL_SECONDS
EOM
fi

# make sure the lockfile is removed when we exit and then claim it
if ! getlock "$LOCK_FILE"; then
    m_info "pid `cat $LOCK_FILE` still running"
    exit 3
fi

if [ -e $STOP_FILE ]; then
    m_info "stopped"
    exit 2
fi

# -----------------------------------------------------------------------------
# Add disk space check from https://github.com/zverik/regional
# -----------------------------------------------------------------------------
MIN_DISK_SPACE_MB=500

if `python -c "import os, sys; st=os.statvfs('$BASE_DIR'); sys.exit(1 if st.f_bavail*st.f_frsize/1024/1024 > $MIN_DISK_SPACE_MB else 0)"`; then
    m_info "there is less than $MIN_DISK_SPACE_MB MB left"
    exit 4
fi

seq=`cat $WORKOSM_DIR/state.txt | grep sequenceNumber | cut -d= -f2`
replag=`dateutils.ddiff $(cat $WORKOSM_DIR/state.txt | grep timestamp | cut -d "=" -f 2 | sed 's,\\\,,g') now`

m_ok "start import from seq-nr $seq, replag is $replag"

/bin/cp $WORKOSM_DIR/state.txt $WORKOSM_DIR/last.state.txt
m_ok "downloading diff"

if ! $OSMOSIS_BIN --read-replication-interval workingDirectory=$WORKOSM_DIR --simplify-change --write-xml-change $CHANGE_FILE 1>&2 2> "$OSMOSISLOG"; then
    m_error "Osmosis error"
fi

if [ -f $TRIM_POLY_FILE ] ; then
  m_ok "filtering diff"
  if ! $TRIM_BIN $TRIM_OPTIONS $TRIM_REGION_OPTIONS  -z $CHANGE_FILE $CHANGE_FILE 1>&2 2>> "$RUNLOG"; then
      m_error "Trim_osc error"
  fi
else
  m_ok "filtering diff skipped"
fi
m_ok "importing diff"

#------------------------------------------------------------------------------
# Previously openstreetmap-tiles-update-expire tried to dirty layer
# "$EXPIRY_MAXZOOM - 3" (which was 15) only.  Instead we write all expired
# tiles in range to the list (note the "-" rather than ":" in the "-e"
# parameter).
#------------------------------------------------------------------------------
if ! $OSM2PGSQL_BIN -a --slim -e$EXPIRY_MINZOOM-$EXPIRY_MAXZOOM $OSM2PGSQL_OPTIONS -o "$EXPIRY_FILE.$$" $CHANGE_FILE 1>&2 2> "$PGSQLLOG"; then
    m_error "osm2pgsql error"
fi

#------------------------------------------------------------------------------
# The lockfile is normally removed before we expire tiles because that is
# something that can be done in parallel with further processing.  In order to
# avoid rework, if actually rerendering is done rather than just deleting or
# dirtying, it makes sense to move it lower down.
#------------------------------------------------------------------------------
#   m_ok "Import complete; removing lock file"
#   freelock "$LOCK_FILE"
m_ok "expiring tiles"

#------------------------------------------------------------------------------
# With tirex we expire tiles using a different approach:
# 1. For tiles that need to be dirtied/touched, we use a loop to delete them
# 2. tirex will re-render on demand when tiles are requested
# The expiry file format from osm2pgsql is: zoom/x/y
#------------------------------------------------------------------------------
if [ -f "$EXPIRY_FILE.$$" ]; then
    m_ok "Processing expired tiles"
    
    # Process each expired tile
    while IFS=/ read -r z x y; do
        # Skip invalid lines
        if [ -z "$z" ] || [ -z "$x" ] || [ -z "$y" ]; then
            continue
        fi
        
        # Convert zoom to integer for comparison
        zoom=$((z))
        
        # Touch tiles (mark as dirty) for EXPIRY_MINZOOM to EXPIRY_TOUCHFROM-1
        if [ $zoom -ge $EXPIRY_MINZOOM ] && [ $zoom -lt $EXPIRY_DELETEFROM ]; then
            tile_path="/var/cache/tirex/tiles/default/$z/$x/$y.png"
            if [ -f "$tile_path" ]; then
                # Mark as outdated by touching the file with old timestamp
                touch -t 200001010000 "$tile_path" 2>/dev/null || true
            fi
        fi
        
        # Delete tiles for EXPIRY_DELETEFROM and above
        if [ $zoom -ge $EXPIRY_DELETEFROM ] && [ $zoom -le $EXPIRY_MAXZOOM ]; then
            tile_path="/var/cache/tirex/tiles/default/$z/$x/$y.png"
            rm -f "$tile_path" 2>/dev/null || true
        fi
    done < "$EXPIRY_FILE.$$" 2>> "$EXPIRYLOG"
    
    m_ok "Expired tiles processed"
else
    m_info "No expiry file found"
fi

rm "$EXPIRY_FILE.$$"

#------------------------------------------------------------------------------
# Only remove the lock file after expiry (if system is slow we want to delay
# the next import, not have multiple render_expired processes running)
#------------------------------------------------------------------------------
freelock "$LOCK_FILE"

m_ok "Done with import"

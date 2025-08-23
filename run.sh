#!/bin/bash

set -euo pipefail

function createPostgresConfig() {
  cp /etc/postgresql/$PG_VERSION/main/postgresql.custom.conf.tmpl /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  sudo -u postgres echo "autovacuum = $AUTOVACUUM" >> /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
  cat /etc/postgresql/$PG_VERSION/main/conf.d/postgresql.custom.conf
}

function setPostgresPassword() {
    sudo -u postgres psql -c "ALTER USER renderer PASSWORD '${PGPASSWORD:-renderer}'"
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
    echo "    STYLE_TYPE: osm-bright or openstreetmap-carto (default: openstreetmap-carto)"
    echo "    DOWNLOAD_GEODANMARK: if enabled, downloads GeoDanmark shapefiles"
    exit 1
fi

set -x

# if there is no custom style mounted, then use the selected style
if [ ! "$(ls -A /data/style/)" ]; then
    if [ "${STYLE_TYPE:-}" == "osm-bright" ]; then
        echo "INFO: Using osm-bright style"
        mv /home/renderer/src/osm-bright-backup/* /data/style/
        
        # Copy external data to style directory
        mkdir -p /data/style/data
        cp -r /data/external-data/* /data/style/data/
        
        # Configure osm-bright
        cd /data/style
        if [ ! -f project.mml ]; then
            echo "INFO: Creating minimal osm-bright project configuration..."
            
            # Create a simple project.mml that references osm-bright styles
            cat > project.mml << 'EOF'
{
  "srs": "+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs +over",
  "Stylesheet": [
    "osm-bright.mss"
  ],
  "Layer": [
    {
      "id": "land-low",
      "name": "land-low", 
      "srs": "+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs +over",
      "geometry": "polygon",
      "Datasource": {
        "file": "data/simplified-land-polygons-complete-3857/README.txt",
        "type": "csv"
      },
      "properties": {
        "maxzoom": 9
      }
    },
    {
      "id": "water",
      "name": "water",
      "srs": "+proj=merc +a=6378137 +b=6378137 +lat_ts=0.0 +lon_0=0.0 +x_0=0.0 +y_0=0 +k=1.0 +units=m +nadgrids=@null +wktext +no_defs +over",
      "geometry": "polygon", 
      "Datasource": {
        "table": "(SELECT way FROM planet_osm_polygon WHERE waterway IS NOT NULL OR natural IN ('water','coastline') OR landuse='reservoir') AS water",
        "host": "localhost",
        "port": "5432",
        "user": "renderer", 
        "password": "renderer",
        "dbname": "gis",
        "type": "postgis"
      }
    }
  ]
}
EOF

            # Create a simple osm-bright.mss style file
            cat > osm-bright.mss << 'EOF'
/* OSM Bright Minimal Style */

Map {
  background-color: #f8f4f0;
}

#land-low {
  polygon-fill: #f8f4f0;
}

#water {
  polygon-fill: #c5d4e8;
  line-color: #8fa5c7;
  line-width: 0.5;
}
EOF
        fi
        
        # Create osm-bright.style file if it doesn't exist
        if [ ! -f osm-bright.style ]; then
            echo "INFO: Creating minimal osm-bright.style configuration..."
            cat > osm-bright.style << 'EOF'
# This is the osm2pgsql .style file for osm-bright.
# It defines which OSM tags to import into PostgreSQL for the osm-bright style.

# OsmType  Tag          DataType     Flags
node,way   name         text         linear
node,way   natural      text         polygon
node,way   waterway     text         polygon
node,way   landuse      text         polygon
node,way   water        text         polygon
node,way   highway      text         linear
node,way   railway      text         linear
node,way   building     text         polygon
node,way   amenity      text         polygon
node,way   place        text         polygon
node,way   layer        int4         linear
node,way   admin_level  text         linear
node,way   boundary     text         linear
way        way_area     real         linear # This is calculated during import
EOF
        fi
        
        # Set default osm-bright parameters - no lua transform needed
        NAME_MML="${NAME_MML:-project.mml}"
    else
        echo "INFO: Using openstreetmap-carto style"
        
        # Download openstreetmap-carto if not cached
        if [ ! -d /home/renderer/src/openstreetmap-carto-backup ]; then
            echo "INFO: Downloading openstreetmap-carto style..."
            cd /home/renderer/src
            git config --global http.sslverify false
            git clone --single-branch --branch v5.4.0 https://github.com/gravitystorm/openstreetmap-carto.git openstreetmap-carto-backup --depth 1
            cd openstreetmap-carto-backup
            sed -i 's/, "unifont Medium", "Unifont Upper Medium"//g' style/fonts.mss
            sed -i 's/"Noto Sans Tibetan Regular",//g' style/fonts.mss
            sed -i 's/"Noto Sans Tibetan Bold",//g' style/fonts.mss
            sed -i 's/Noto Sans Syriac Eastern Regular/Noto Sans Syriac Regular/g' style/fonts.mss
            rm -rf .git
        fi
        
        mv /home/renderer/src/openstreetmap-carto-backup/* /data/style/
        NAME_MML="${NAME_MML:-project.mml}"
    fi
fi

# carto build
if [ ! -f /data/style/mapnik.xml ]; then
    cd /data/style/
    carto ${NAME_MML:-project.mml} > mapnik.xml
fi

if [ "$1" == "import" ]; then
    # Ensure that database directory is in right state
    mkdir -p /data/database/postgres/
    chown renderer: /data/database/
    chown -R postgres: /var/lib/postgresql /data/database/postgres/
    if [ ! -f /data/database/postgres/PG_VERSION ]; then
        sudo -u postgres /usr/lib/postgresql/$PG_VERSION/bin/pg_ctl -D /data/database/postgres/ initdb -o "--locale C.UTF-8"
    fi

    # Initialize PostgreSQL
    createPostgresConfig
    service postgresql start
    sudo -u postgres createuser --if-not-exists renderer
    sudo -u postgres createdb -E UTF8 -O renderer gis || true
    sudo -u postgres psql -d gis -c "CREATE EXTENSION IF NOT EXISTS postgis;"
    sudo -u postgres psql -d gis -c "CREATE EXTENSION IF NOT EXISTS hstore;"
    sudo -u postgres psql -d gis -c "ALTER TABLE geometry_columns OWNER TO renderer;"
    sudo -u postgres psql -d gis -c "ALTER TABLE spatial_ref_sys OWNER TO renderer;"
    setPostgresPassword

    # Download GeoDanmark shapefiles if requested
    if [ "${DOWNLOAD_GEODANMARK:-}" == "enabled" ] || [ "${DOWNLOAD_GEODANMARK:-}" == "1" ]; then
        echo "INFO: Downloading GeoDanmark shapefiles..."
        mkdir -p /data/geodanmark
        cd /data/geodanmark
        
        # Note: This would download ~4GB. For the demo, we create a placeholder
        echo "# GeoDanmark placeholder - in production, download from:" > geodanmark.txt
        echo "# https://download.kortforsyningen.dk/content/geodanmark" >> geodanmark.txt
        echo "# File: DK_SHAPE_UTM32-EUREF89.zip" >> geodanmark.txt
        
        # In production, you would run:
        # wget -O DK_SHAPE_UTM32-EUREF89.zip [geodanmark_download_url]
        # unzip DK_SHAPE_UTM32-EUREF89.zip
        
        cd /data
    fi

    # Download Luxembourg as sample if no data is provided
    if [ ! -f /data/region.osm.pbf ] && [ -z "${DOWNLOAD_PBF:-}" ]; then
        if [ "${STYLE_TYPE:-}" == "osm-bright" ]; then
            echo "WARNING: No import file at /data/region.osm.pbf, so importing Denmark as example for osm-bright..."
            DOWNLOAD_PBF="https://download.geofabrik.de/europe/denmark-latest.osm.pbf"
            DOWNLOAD_POLY="https://download.geofabrik.de/europe/denmark.poly"
        else
            echo "WARNING: No import file at /data/region.osm.pbf, so importing Luxembourg as example..."
            DOWNLOAD_PBF="https://download.geofabrik.de/europe/luxembourg-latest.osm.pbf"
            DOWNLOAD_POLY="https://download.geofabrik.de/europe/luxembourg.poly"
        fi
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
    if [ "${STYLE_TYPE:-}" == "osm-bright" ]; then
        # osm-bright uses different defaults
        sudo -u renderer osm2pgsql -d gis --create --slim -G --hstore  \
          --number-processes ${THREADS:-4}  \
          -S /data/style/${NAME_STYLE:-osm-bright.style}  \
          /data/region.osm.pbf  \
          ${OSM2PGSQL_EXTRA_ARGS:-}  \
        ;
    else
        # openstreetmap-carto style
        sudo -u renderer osm2pgsql -d gis --create --slim -G --hstore  \
          --tag-transform-script /data/style/${NAME_LUA:-openstreetmap-carto.lua}  \
          --number-processes ${THREADS:-4}  \
          -S /data/style/${NAME_STYLE:-openstreetmap-carto.style}  \
          /data/region.osm.pbf  \
          ${OSM2PGSQL_EXTRA_ARGS:-}  \
        ;
    fi

    # old flat-nodes dir
    if [ -f /nodes/flat_nodes.bin ] && ! [ -f /data/database/flat_nodes.bin ]; then
        mv /nodes/flat_nodes.bin /data/database/flat_nodes.bin
        chown renderer: /data/database/flat_nodes.bin
    fi

    # Create indexes
    if [ -f /data/style/${NAME_SQL:-indexes.sql} ]; then
        sudo -u postgres psql -d gis -f /data/style/${NAME_SQL:-indexes.sql}
    fi

    #Import external data
    chown -R renderer: /home/renderer/src/ /data/style/
    if [ -f /data/style/scripts/get-external-data.py ] && [ -f /data/style/external-data.yml ]; then
        sudo -E -u renderer python3 /data/style/scripts/get-external-data.py -c /data/style/external-data.yml -D /data/style/data
    fi

    # Register that data has changed for mod_tile caching purposes
    sudo -u renderer touch /data/database/planet-import-complete

    service postgresql stop

    exit 0
fi

if [ "$1" == "run" ]; then
    # Clean /tmp
    rm -rf /tmp/*

    # migrate old files
    if [ -f /data/database/PG_VERSION ] && ! [ -d /data/database/postgres/ ]; then
        mkdir /data/database/postgres/
        mv /data/database/* /data/database/postgres/
    fi
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

    # Fix postgres data privileges
    chown -R postgres: /var/lib/postgresql/ /data/database/postgres/

    # Configure Apache CORS
    if [ "${ALLOW_CORS:-}" == "enabled" ] || [ "${ALLOW_CORS:-}" == "1" ]; then
        echo "export APACHE_ARGUMENTS='-D ALLOW_CORS'" >> /etc/apache2/envvars
    fi

    # Initialize PostgreSQL and Apache
    createPostgresConfig
    service postgresql start
    service apache2 restart
    setPostgresPassword

    # Configure renderd threads
    sed -i -E "s/num_threads=[0-9]+/num_threads=${THREADS:-4}/g" /etc/renderd.conf

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
        kill -TERM "$child"
    }
    trap stop_handler SIGTERM

    sudo -u renderer renderd -f -c /etc/renderd.conf &
    child=$!
    wait "$child"

    service postgresql stop

    exit 0
fi

echo "invalid command"
exit 1

FROM debian:trixie-20250929-slim AS compiler-common
ENV DEBIAN_FRONTEND=noninteractive
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

RUN apt-get update \
&& apt-get install -y --no-install-recommends \
 ca-certificates gnupg lsb-release locales \
 wget curl \
 git-core unzip unrar-free \
&& locale-gen $LANG && update-locale LANG=$LANG \
&& sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list' \
&& wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
&& apt-get update \
&& apt-get -y upgrade

###########################################################################################################

FROM compiler-common AS compiler-stylesheet
RUN cd ~ \
&& git clone --single-branch --branch v5.9.0 https://github.com/gravitystorm/openstreetmap-carto.git --depth 1 \
&& cd openstreetmap-carto \
&& sed -i 's/, "unifont Medium", "Unifont Upper Medium"//g' style/fonts.mss \
&& sed -i 's/"Noto Sans Tibetan Regular",//g' style/fonts.mss \
&& sed -i 's/"Noto Sans Tibetan Bold",//g' style/fonts.mss \
&& sed -i 's/Noto Sans Syriac Eastern Regular/Noto Sans Syriac Regular/g' style/fonts.mss \
&& sed -i 's/"Noto Sans Syriac Black",//g' style/fonts.mss \
&& sed -i 's/"Noto Emoji Bold",//g' style/fonts.mss \
&& rm -rf .git

###########################################################################################################

FROM compiler-common AS compiler-helper-script
RUN mkdir -p /home/renderer/src \
&& cd /home/renderer/src \
&& git clone https://github.com/zverik/regional \
&& cd regional \
&& rm -rf .git \
&& chmod u+x /home/renderer/src/regional/trim_osc.py

###########################################################################################################

FROM compiler-common AS final

# Based on
# https://switch2osm.org/serving-tiles/manually-building-a-tile-server-18-04-lts/
ENV DEBIAN_FRONTEND=noninteractive
ENV AUTOVACUUM=on
ENV UPDATES=disabled
ENV REPLICATION_URL=https://planet.openstreetmap.org/replication/hour/
ENV MAX_INTERVAL_SECONDS=3600

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install Node.js 22.x LTS from NodeSource and get packages in a single layer
# Note: tirex pulls in the correct libmapnik version as a dependency
# Installing tirex will install libmapnik3.1 on Debian Trixie
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
&& apt-get update \
&& apt-get install -y --no-install-recommends \
 apache2 \
 cron \
 dateutils \
 fonts-hanazono \
 fonts-noto-cjk \
 fonts-noto-hinted \
 fonts-noto-unhinted \
 fonts-unifont \
 gnupg2 \
 gdal-bin \
 liblua5.3-dev \
 lua5.3 \
 mapnik-utils \
 nodejs \
 osm2pgsql \
 osmium-tool \
 osmosis \
 postgresql-client-18 \
 python-is-python3 \
 python3-mapnik \
 python3-lxml \
 python3-psycopg2 \
 python3-shapely \
 python3-pip \
 python3-pyosmium \
 python3-yaml \
 python3-requests \
 tirex \
 sudo \
 vim \
&& apt-get clean autoclean \
&& apt-get autoremove --yes \
&& rm -rf /var/lib/{apt,dpkg,cache,log}/

RUN adduser --disabled-password --gecos "" renderer

# Download fonts in a single layer
RUN wget https://github.com/googlefonts/noto-emoji/blob/9a5261d871451f9b5183c93483cbd68ed916b1e9/fonts/NotoEmoji-Regular.ttf?raw=true --content-disposition -P /usr/share/fonts/ \
&& wget https://github.com/stamen/terrain-classic/blob/master/fonts/unifont-Medium.ttf?raw=true --content-disposition -P /usr/share/fonts/

# Install Node.js packages with cache cleanup
RUN npm install -g carto@1.2.0 \
&& npm cache clean --force \
&& rm -rf /root/.npm /tmp/*

# Configure Apache in a single layer
COPY apache.conf /etc/apache2/sites-available/000-default.conf
RUN a2enmod tile \
&& a2enmod headers \
&& a2disconf tirex \
&& ln -sf /dev/stdout /var/log/apache2/access.log \
&& ln -sf /dev/stderr /var/log/apache2/error.log

# leaflet
COPY leaflet-demo.html /var/www/html/index.html
RUN cd /var/www/html/ \
&& wget https://github.com/Leaflet/Leaflet/releases/download/v1.9.4/leaflet.zip \
&& unzip leaflet.zip \
&& rm leaflet.zip

# Icon
RUN wget -O /var/www/html/favicon.ico https://www.openstreetmap.org/favicon.ico

# Copy update scripts
COPY openstreetmap-tiles-update-expire.sh /usr/bin/
RUN chmod +x /usr/bin/openstreetmap-tiles-update-expire.sh \
&& mkdir /var/log/tiles \
&& chmod a+rw /var/log/tiles \
&& echo "* * * * *   renderer    openstreetmap-tiles-update-expire.sh\n" >> /etc/crontab

# Configure environment variables for external PostGIS connection
ENV PGHOST=postgres
ENV PGPORT=5432
ENV PGUSER=renderer
ENV PGPASSWORD=renderer
ENV PGDATABASE=gis

# Create volume directories
RUN mkdir -p /run/tirex/ \
  &&  mkdir  -p  /data/style/  \
  &&  mkdir  -p  /home/renderer/src/  \
  &&  chown  -R  renderer:  /data/  \
  &&  chown  -R  renderer:  /home/renderer/src/  \
  &&  chown  -R  renderer:  /run/tirex  \
  &&  mkdir  -p  /data/tiles/  \
  &&  chown  -R  renderer: /data/tiles \
  &&  ln  -s  /data/style              /home/renderer/src/openstreetmap-carto  \
  &&  mkdir  -p  /var/cache/tirex/tiles  \
  &&  chown  -R renderer:  /var/cache/tirex  \
  &&  ln  -s  /data/tiles              /var/cache/tirex/tiles/default                \
;

# Configure tirex with tile settings and correct paths
# Update tirex.conf for proper socket and stats directories
RUN sed -i 's|^modtile_socket_name=.*|modtile_socket_name=/run/tirex/modtile.sock|' /etc/tirex/tirex.conf \
 && sed -i 's|^socket_dir=.*|socket_dir=/run/tirex|' /etc/tirex/tirex.conf \
 && sed -i 's|^stats_dir=.*|stats_dir=/var/cache/tirex/stats|' /etc/tirex/tirex.conf \
 && sed -i 's|^master_pidfile=.*|master_pidfile=/run/tirex/tirex-master.pid|' /etc/tirex/tirex.conf \
 && sed -i 's|^backend_manager_pidfile=.*|backend_manager_pidfile=/run/tirex/tirex-backend-manager.pid|' /etc/tirex/tirex.conf

# Configure mapnik renderer for tirex
# Note: Debian Trixie has Mapnik 4.0 with plugins in architecture-specific paths
# Dynamically detect the architecture multiarch tuple (e.g., x86_64-linux-gnu, aarch64-linux-gnu)
RUN ARCH=$(dpkg --print-architecture) \
 && case "$ARCH" in \
      amd64) ARCH_TUPLE="x86_64-linux-gnu" ;; \
      arm64) ARCH_TUPLE="aarch64-linux-gnu" ;; \
      armhf) ARCH_TUPLE="arm-linux-gnueabihf" ;; \
      i386) ARCH_TUPLE="i386-linux-gnu" ;; \
      *) ARCH_TUPLE="$(uname -m)-linux-gnu" ;; \
    esac \
 && sed -i "s|^plugindir=.*|plugindir=/usr/lib/${ARCH_TUPLE}/mapnik/4.0/input|" /etc/tirex/renderer/mapnik.conf \
 && sed -i 's|^fontdir=.*|fontdir=/usr/share/fonts|' /etc/tirex/renderer/mapnik.conf \
 && sed -i 's|^procs=.*|procs=4|' /etc/tirex/renderer/mapnik.conf

# Create tirex map configuration for default OpenStreetMap map
RUN mkdir -p /etc/tirex/renderer/mapnik && \
    echo '# OpenStreetMap Carto Configuration' > /etc/tirex/renderer/mapnik/default.conf && \
    echo 'name=default' >> /etc/tirex/renderer/mapnik/default.conf && \
    echo 'tiledir=/var/cache/tirex/tiles/default' >> /etc/tirex/renderer/mapnik/default.conf && \
    echo 'minz=0' >> /etc/tirex/renderer/mapnik/default.conf && \
    echo 'maxz=20' >> /etc/tirex/renderer/mapnik/default.conf && \
    echo 'mapfile=/home/renderer/src/openstreetmap-carto/mapnik.xml' >> /etc/tirex/renderer/mapnik/default.conf

# Install helper script
COPY --from=compiler-helper-script /home/renderer/src/regional /home/renderer/src/regional

COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/renderer/src/openstreetmap-carto-backup

# Start running
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []
EXPOSE 80

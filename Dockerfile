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
ENV MAPNIK_INPUT_PLUGINS_DIRECTORY=/usr/lib/x86_64-linux-gnu/mapnik/4.0/input

RUN ln -snf /usr/share/zoneinfo/$TZ /etc/localtime && echo $TZ > /etc/timezone

# Install Node.js 22.x LTS from NodeSource and get packages in a single layer
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
 libmapnik4.0 \
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
 renderd \
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
&& ln -s /home/renderer/src/mod_tile/osmosis-db_replag /usr/bin/osmosis-db_replag \
&& echo "* * * * *   renderer    openstreetmap-tiles-update-expire.sh\n" >> /etc/crontab

# Configure environment variables for external PostGIS connection
ENV PGHOST=postgres
ENV PGPORT=5432
ENV PGUSER=renderer
ENV PGPASSWORD=renderer
ENV PGDATABASE=gis

# Create volume directories
RUN mkdir -p /run/renderd/ \
  &&  mkdir  -p  /data/database/  \
  &&  mkdir  -p  /data/style/  \
  &&  mkdir  -p  /home/renderer/src/  \
  &&  chown  -R  renderer:  /data/  \
  &&  chown  -R  renderer:  /home/renderer/src/  \
  &&  chown  -R  renderer:  /run/renderd  \
  &&  mkdir  -p  /data/tiles/  \
  &&  chown  -R  renderer: /data/tiles \
  &&  ln  -s  /data/style              /home/renderer/src/openstreetmap-carto  \
  &&  mkdir  -p  /var/cache/renderd  \
  &&  chown  renderer:  /var/cache/renderd  \
  &&  ln  -s  /data/tiles              /var/cache/renderd/tiles                \
;

RUN echo '[default] \n\
URI=/tile/ \n\
TILEDIR=/var/cache/renderd/tiles \n\
XML=/home/renderer/src/openstreetmap-carto/mapnik.xml \n\
HOST=localhost \n\
TILESIZE=256 \n\
MAXZOOM=20' >> /etc/renderd.conf \
 && sed -i 's,/usr/share/fonts/truetype,/usr/share/fonts,g' /etc/renderd.conf \
 && sed -i 's,plugins_dir=/usr/lib/mapnik/3.1/input,plugins_dir=/usr/lib/x86_64-linux-gnu/mapnik/4.0/input,g' /etc/renderd.conf

# Install helper script
COPY --from=compiler-helper-script /home/renderer/src/regional /home/renderer/src/regional

COPY --from=compiler-stylesheet /root/openstreetmap-carto /home/renderer/src/openstreetmap-carto-backup

# Start running
COPY run.sh /
ENTRYPOINT ["/run.sh"]
CMD []
EXPOSE 80

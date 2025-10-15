# Runtime Performance Optimizations

This document provides comprehensive recommendations for improving runtime performance of the OpenStreetMap tile server, addressing import speed, tile rendering performance, and caching strategies.

## Table of Contents
1. [Import Performance](#import-performance)
2. [Tile Rendering Performance](#tile-rendering-performance)
3. [Apache mod_tile Caching](#apache-mod_tile-caching)
4. [Varnish Integration](#varnish-integration)
5. [Scaling for Large Maps](#scaling-for-large-maps)

---

## Import Performance

### Current Issue
Initial import uses only a few CPU cores and can be slow for large datasets.

### Recommended Optimizations

#### 1. Increase osm2pgsql Threads
The default is 4 threads. Increase based on your CPU cores:

```bash
docker run ... -e THREADS=16 ...  # For 16+ core systems
```

**Recommendation**: Set `THREADS` to 75% of available CPU cores (e.g., 12 threads for 16-core system).

#### 2. Enable Flat Nodes (Essential for Large Imports)
For countries or larger regions, flat nodes dramatically improve import speed and reduce memory usage:

```bash
docker run ... -e FLAT_NODES=enabled ...
```

**Impact**: Reduces memory usage from ~8GB to ~1GB for planet imports, significantly faster for large datasets.

**Disk Space Requirements**:
The flat nodes file stores node coordinates on disk instead of in RAM. Approximate sizes:

| Region | Flat Nodes File Size |
|--------|---------------------|
| Luxembourg | ~100 MB |
| Switzerland | ~500 MB |
| Germany | ~3 GB |
| France | ~4 GB |
| Europe | ~35 GB |
| Planet | ~70 GB |

**Storage Configuration**:
- **Dedicated Volume Recommended**: Mount a separate volume for `/data/osm-flatnodes/` to isolate flat nodes storage
- **Fast Storage**: Use SSD/NVMe for best performance
- **Example docker-compose.yml**:
```yaml
volumes:
  - osm-flatnodes:/data/osm-flatnodes/  # Dedicated volume for flat nodes storage
```

**When to Use**:
- ✅ **USE** for imports >1GB PBF (countries and larger)
- ✅ **USE** when RAM is limited (<16GB)
- ❌ **SKIP** for small regions (<500MB PBF) - overhead not worth it
- ❌ **SKIP** if you have >32GB RAM and import small regions

#### 3. Optimize PostgreSQL for Import
Add these PostgreSQL tuning parameters for import phase:

```yaml
# In docker-compose.yml - PostgreSQL service
command: >
  postgres
  -c shared_buffers=2GB              # Increase from 512MB
  -c maintenance_work_mem=2GB        # Increase from 256MB (important for indexing)
  -c work_mem=256MB                  # Increase from 64MB for import
  -c effective_cache_size=8GB        # Increase based on available RAM
  -c checkpoint_timeout=15min        # Increase from 10min
  -c max_wal_size=4GB                # Increase from 2GB
  -c synchronous_commit=off          # Already set - keep this
  -c fsync=off                       # ONLY during import, then re-enable!
  -c full_page_writes=off            # ONLY during import, then re-enable!
  -c autovacuum=off                  # Disable during import, re-enable after
  -c random_page_cost=1.1            # Already set for SSD
```

**CRITICAL**: `fsync=off`, `full_page_writes=off`, and `autovacuum=off` should ONLY be used during initial import. After import, restart PostgreSQL with these removed or set to defaults.

#### 4. Increase Shared Memory
```bash
docker run ... --shm-size=4GB ...  # Increase from 256MB for tile server
```

For PostgreSQL container:
```bash
--shm-size=2GB  # Increase from 1GB for large imports
```

#### 5. Use SSD Storage
Ensure Docker volumes are on SSD/NVMe storage for 5-10x faster import.

#### 6. Import Strategy for Large Maps
For Europe or planet:
```bash
# Use slim mode (no metadata, faster)
OSM2PGSQL_EXTRA_ARGS="--drop --slim"

# Split by country/region and import separately, then merge
# Or use regional extracts from Geofabrik
```

---

## Tile Rendering Performance

### Current Issues
- First tile loading is slow
- Requests timeout when rendering takes too long
- Map doesn't load completely

### Recommended Optimizations

#### 1. Pre-render Tiles (Render Expired)
Pre-render tiles for common zoom levels before serving traffic:

```bash
# After import, pre-render low zoom levels (0-12)
docker exec -it tile-server sudo -u renderer render_list \
  -a -z 0 -Z 12 -n 4

# Pre-render high-traffic areas at higher zooms
docker exec -it tile-server sudo -u renderer render_list \
  -a -z 13 -Z 15 -n 4 -x <min_x> -X <max_x> -y <min_y> -Y <max_y>
```

**Impact**: Dramatically reduces first-load time. Pre-render zoom 0-10 (only ~1-2 hours), optionally 11-14 for high-traffic areas.

#### 2. Increase Renderd Threads
Default is 4 threads. Increase for better parallelism:

```bash
docker run ... -e THREADS=8 ...  # For 8+ core systems
```

**Recommendation**: Set to number of CPU cores for balanced performance.

#### 3. Adjust Apache Timeout
Modify `apache.conf` to handle slow renders:

```apache
ModTileRequestTimeout 10          # Increase from 0 (change to 10 seconds)
ModTileMissingRequestTimeout 60   # Increase from 30 (change to 60 seconds)
```

#### 4. Enable Tile Expiry Queue
For better render queue management, add to renderd.conf:

```ini
[default]
...
MAX_LOAD_OLD=4
MAX_LOAD_MISSING=8
```

This prioritizes missing tiles over old tiles during high load.

#### 5. Optimize Mapnik Rendering
Add environment variable for Mapnik buffer size:

```bash
-e MAPNIK_MAP_BUFFER_SIZE=128  # Default is 0, increase for complex geometries
```

#### 6. PostgreSQL Connection Pooling
For high traffic, implement PgBouncer:

```yaml
# Add to docker-compose.yml
pgbouncer:
  image: edoburu/pgbouncer:latest
  environment:
    DATABASE_URL: postgres://osm_usr:Random_Password@tile-server-db/osm_tiles
    POOL_MODE: transaction
    MAX_CLIENT_CONN: 1000
    DEFAULT_POOL_SIZE: 50
  depends_on:
    - tile-server-db
  networks:
    - tile-server-net

# Update tile-server to connect via PgBouncer
tile-server:
  environment:
    PGHOST: pgbouncer
    PGPORT: 5432
```

---

## Apache mod_tile Caching

### How mod_tile Caching Works

**Cache Location**: `/var/cache/renderd/tiles/` (mounted to `/data/tiles/`)

**Cache Structure**:
- Tiles stored as PNG files in a hierarchical directory structure
- Path: `/data/tiles/default/{z}/{x}/{y}.png`
- Metadata stored in `.meta` files (8x8 tile metatiles)

**Cache Behavior**:
1. **Request received**: Apache checks if tile exists and is fresh
2. **Tile exists**: Served directly (very fast)
3. **Tile missing/expired**: Renderd generates tile, saves to cache, serves
4. **Tile stale**: Background re-render if `UPDATES=enabled`

### Cache Persistence

**Will cache survive container restart?**
- ✅ **YES** - if `/data/tiles/` is mounted to a Docker volume
- ❌ **NO** - if not mounted (cache lost on restart)

**Ensure cache persistence**:
```bash
docker volume create osm-tiles
docker run ... -v osm-tiles:/data/tiles/ ...
```

### Cache Size Estimation

**Cache size depends on**:
- Geographic area covered
- Zoom levels rendered
- Map complexity (urban areas = larger)

**Estimated cache sizes**:

| Region | Zoom 0-10 | Zoom 0-12 | Zoom 0-14 | Zoom 0-16 | Zoom 0-18 |
|--------|-----------|-----------|-----------|-----------|-----------|
| Luxembourg | 100 MB | 200 MB | 500 MB | 2 GB | 10 GB |
| Switzerland | 200 MB | 400 MB | 1 GB | 5 GB | 30 GB |
| Germany | 500 MB | 1 GB | 5 GB | 30 GB | 200 GB |
| France | 800 MB | 2 GB | 10 GB | 60 GB | 400 GB |
| Europe | 2 GB | 8 GB | 50 GB | 400 GB | 3 TB |
| Planet | 5 GB | 20 GB | 150 GB | 1.5 TB | 15 TB |

**Formula**: Each zoom level has 4x more tiles than previous level.

**Recommendation for Europe**:
- Pre-render zoom 0-12: ~8 GB
- On-demand render zoom 13-18
- Total cache: 50-200 GB (depending on traffic patterns)

### Cache Management

**Clear old tiles**:
```bash
# Clear tiles older than 30 days
find /data/tiles/default -name "*.png" -mtime +30 -delete
```

**Monitor cache size**:
```bash
du -sh /data/tiles/
```

---

## Varnish Integration

### Why Use Varnish?

**Benefits**:
- ✅ **RAM caching**: 10-100x faster than disk-based mod_tile cache
- ✅ **Reduced backend load**: 80-95% cache hit rate typical
- ✅ **Better handling of slow renders**: Queue protection
- ✅ **Compression**: Automatic gzip/brotli compression
- ✅ **Traffic spikes**: Handles 10,000+ req/s easily

**When to use**:
- High traffic (>100 requests/second)
- Large geographic area with hot spots
- Need sub-10ms response times

### Varnish Memory Requirements

**Memory calculation**:
```
Memory needed = (Active tiles × Tile size × 1.5 overhead)
```

**Examples**:

| Tiles Cached | Avg Tile Size | Memory Needed |
|--------------|---------------|---------------|
| 10,000 | 15 KB | 220 MB |
| 100,000 | 15 KB | 2.2 GB |
| 1,000,000 | 15 KB | 22 GB |
| 10,000,000 | 15 KB | 220 GB |

**Recommendation for Europe**:
- Cache zoom 10-16 hot spots: ~50,000-500,000 tiles
- Memory: **8-16 GB** for optimal performance
- Cache TTL: 7 days for zoom 0-12, 1 day for zoom 13-18

### Varnish Setup

**docker-compose.yml**:
```yaml
version: '3.8'

services:
  tile-server-db:
    # ... existing config ...

  tile-server:
    # ... existing config ...
    ports: []  # Remove port exposure
    expose:
      - "80"

  varnish:
    image: varnish:7.6  # Varnish 7.x stable (not 8.x yet)
    container_name: varnish-cache
    restart: unless-stopped
    ports:
      - "8080:80"
    environment:
      VARNISH_SIZE: 8G  # Adjust based on available RAM
    volumes:
      - ./varnish.vcl:/etc/varnish/default.vcl:ro
    depends_on:
      - tile-server
    networks:
      - tile-server-net
    command: >
      -p default_ttl=604800
      -p default_grace=3600
      -p http_resp_hdr_len=65536
      -p http_resp_size=98304
      -p workspace_backend=256k
```

**varnish.vcl** (create this file):
```vcl
vcl 4.1;

backend default {
    .host = "tile-server";
    .port = "80";
    .connect_timeout = 10s;
    .first_byte_timeout = 120s;  # Allow slow renders
    .between_bytes_timeout = 30s;
}

sub vcl_recv {
    # Only cache GET and HEAD requests
    if (req.method != "GET" && req.method != "HEAD") {
        return (pass);
    }

    # Cache tiles
    if (req.url ~ "^/tile/") {
        return (hash);
    }

    # Don't cache other requests
    return (pass);
}

sub vcl_backend_response {
    # Set TTL based on zoom level
    if (bereq.url ~ "^/tile/([0-9]+)/") {
        set beresp.http.X-Zoom = regsub(bereq.url, "^/tile/([0-9]+)/.*", "\1");
        
        # Low zoom (0-10): cache 30 days
        if (std.integer(beresp.http.X-Zoom, 99) < 11) {
            set beresp.ttl = 30d;
        }
        # Medium zoom (11-14): cache 7 days
        else if (std.integer(beresp.http.X-Zoom, 99) < 15) {
            set beresp.ttl = 7d;
        }
        # High zoom (15-18): cache 1 day
        else {
            set beresp.ttl = 1d;
        }

        # Allow stale content during backend issues
        set beresp.grace = 6h;
        
        # Remove zoom header before sending to client
        unset beresp.http.X-Zoom;
    }

    # Enable gzip compression
    if (beresp.http.content-type ~ "image/png") {
        set beresp.do_gzip = true;
    }
}

sub vcl_deliver {
    # Add cache status header for debugging
    if (obj.hits > 0) {
        set resp.http.X-Cache = "HIT";
        set resp.http.X-Cache-Hits = obj.hits;
    } else {
        set resp.http.X-Cache = "MISS";
    }
}

sub vcl_hit {
    # Refresh tiles in background if they're getting stale
    if (obj.ttl < 0s && obj.ttl + obj.grace > 0s) {
        return (deliver);  # Deliver stale, refresh in background
    }
}
```

### Varnish Monitoring

**Cache statistics**:
```bash
docker exec varnish-cache varnishstat -1
```

**Key metrics**:
- `cache_hit` - Cache hits (should be >80%)
- `cache_miss` - Cache misses
- `n_object` - Objects in cache
- `g_bytes` - Memory used

---

## Nginx/Angie as Apache Alternative

### Can You Replace Apache with Nginx or Angie?

**Short Answer**: Yes, but with caveats. When using Varnish for caching, you can replace Apache with nginx or angie as the backend web server.

### Why Replace Apache?

**Advantages of nginx/angie**:
- ✅ **Lower memory footprint**: ~10-50MB vs Apache's ~100-200MB per process
- ✅ **Better concurrent connection handling**: Event-driven vs process-based
- ✅ **Simpler configuration**: Easier to understand and maintain
- ✅ **Better static file performance**: 2-3x faster for serving tiles from cache
- ✅ **Angie**: Fork of nginx with additional features (HTTP/3, dynamic upstreams)

**Disadvantages**:
- ❌ **No native mod_tile support**: Must use Varnish or another cache layer
- ❌ **Manual tile cache management**: No built-in expired tile handling
- ⚠️ **Requires Varnish**: Nginx/angie should not directly serve uncached tiles

### Architecture Options

#### Option 1: Varnish + Nginx + mod_tile (Recommended)

```
Clients → Varnish (RAM cache) → nginx (proxy) → Apache + mod_tile → renderd
```

**Best for**: High traffic with mixed workloads

**Configuration**:
```yaml
# docker-compose.yml
services:
  # Apache + mod_tile (backend, not exposed)
  tile-server:
    image: overv/openstreetmap-tile-server
    expose:
      - "80"
    # ... rest of config ...

  # nginx as reverse proxy (optional middle layer)
  nginx:
    image: nginx:alpine
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - osm-tiles:/var/cache/tiles:ro  # Read-only tile cache
    depends_on:
      - tile-server
    networks:
      - tile-server-net

  # Varnish (frontend)
  varnish:
    image: varnish:7.6
    ports:
      - "8080:80"
    environment:
      VARNISH_SIZE: 8G
    volumes:
      - ./varnish-nginx.vcl:/etc/varnish/default.vcl:ro
    depends_on:
      - nginx
    networks:
      - tile-server-net
```

**nginx.conf**:
```nginx
events {
    worker_connections 4096;
}

http {
    upstream tile_backend {
        server tile-server:80;
        keepalive 32;
    }

    server {
        listen 80;
        
        # Serve tiles from cache if available
        location /tile/ {
            root /var/cache/tiles;
            try_files $uri @backend;
            
            # Cache control headers
            add_header X-Cache-Status "HIT";
            expires 7d;
        }
        
        # Fallback to Apache mod_tile for missing tiles
        location @backend {
            proxy_pass http://tile_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            
            # Timeouts for slow renders
            proxy_connect_timeout 10s;
            proxy_read_timeout 120s;
            
            add_header X-Cache-Status "MISS";
        }
        
        # Serve static content
        location / {
            proxy_pass http://tile_backend;
        }
    }
}
```

#### Option 2: Varnish + Angie + mod_tile

```
Clients → Varnish (RAM cache) → angie (proxy) → Apache + mod_tile → renderd
```

**Angie advantages over nginx**:
- HTTP/3 support (QUIC)
- Dynamic upstream configuration
- Better monitoring/stats
- Enhanced security features

**angie.conf** (similar to nginx):
```nginx
# Same as nginx.conf, but with additional features
http {
    upstream tile_backend {
        server tile-server:80;
        keepalive 32;
        
        # Angie-specific: dynamic reconfiguration
        zone tile_backend 64k;
    }
    
    # ... rest similar to nginx ...
}
```

#### Option 3: Varnish + renderd Direct (Advanced)

```
Clients → Varnish → renderd HTTP interface (port 7653)
```

**Most efficient but requires custom setup**:
- Remove Apache entirely
- Configure renderd to listen on HTTP port
- Varnish connects directly to renderd
- **Not recommended** unless you have specific needs

### When to Use Each Option

**Use Apache (default)**:
- ✅ Small to medium deployments (<100 req/s)
- ✅ Don't want to manage Varnish
- ✅ Need mod_tile features (automatic expiry, meta-tiles)
- ✅ Simple setup preferred

**Use Varnish + Apache**:
- ✅ Medium to high traffic (>100 req/s)
- ✅ Want RAM caching without changing backend
- ✅ Best balance of performance and simplicity

**Use Varnish + nginx + Apache**:
- ✅ Very high traffic (>1000 req/s)
- ✅ Want to minimize Apache load
- ✅ Need nginx for other services too
- ✅ Have expertise with nginx

**Use Varnish + angie + Apache**:
- ✅ Same as nginx, plus:
- ✅ Need HTTP/3 support
- ✅ Want better monitoring
- ✅ Enterprise requirements

### Migration Path

**From Apache-only to nginx/angie**:

1. **Phase 1**: Add Varnish in front of Apache
   - Validate performance improvement
   - No backend changes needed

2. **Phase 2**: Add nginx/angie between Varnish and Apache
   - nginx serves cached tiles directly
   - Apache only handles cache misses
   - Reduces Apache load by 70-90%

3. **Phase 3** (Optional): Optimize further
   - Tune nginx worker processes
   - Implement nginx tile caching to disk
   - Consider removing Apache if renderd can be exposed

### Performance Comparison

| Configuration | Req/s | Memory | Complexity |
|--------------|-------|--------|-----------|
| Apache only | 50-100 | 200 MB | Low |
| Varnish + Apache | 500-2000 | 8 GB | Medium |
| Varnish + nginx + Apache | 2000-5000 | 8.1 GB | High |
| Varnish + angie + Apache | 2000-5000 | 8.1 GB | High |

### Recommendation

**For most users**: Stick with **Varnish + Apache** (Option in Varnish Integration section)
- Simplest setup with best performance gains
- No need for additional nginx/angie layer
- Apache + mod_tile handles tile generation well

**For high-scale users**: Consider **Varnish + nginx + Apache**
- When serving >1000 req/s
- When every millisecond counts
- When you have DevOps expertise

**Bottom line**: Adding nginx/angie provides only marginal benefits (~10-20%) over Varnish + Apache alone, with added complexity. Focus on Varnish first.

---

## Scaling for Large Maps (Europe/Planet)

### Multi-tier Architecture

For serving entire Europe or planet, use a tiered approach:

```
┌─────────────┐
│   Clients   │
└──────┬──────┘
       │
┌──────▼──────────┐
│ CDN (CloudFlare)│  ← 50-90% traffic served here
└──────┬──────────┘
       │
┌──────▼──────┐
│   Varnish   │  ← 80-95% of remaining traffic cached
│   (8-16 GB) │
└──────┬──────┘
       │
┌──────▼────────┐
│   mod_tile    │  ← Disk cache + on-demand rendering
│   Apache      │
└──────┬────────┘
       │
┌──────▼────────┐
│   renderd     │  ← 8-16 threads
│   (4-8 procs) │
└──────┬────────┘
       │
┌──────▼────────┐
│  PostgreSQL   │  ← Heavily tuned, possibly with replicas
│  + PgBouncer  │
└───────────────┘
```

### Recommended Configuration for Europe

**Hardware**:
- **CPU**: 16-32 cores
- **RAM**: 64-128 GB
- **Storage**: 2-4 TB NVMe SSD
- **Database**: 500 GB+ (Europe is ~70 GB compressed)

**PostgreSQL tuning**:
```yaml
command: >
  postgres
  -c shared_buffers=16GB
  -c effective_cache_size=48GB
  -c maintenance_work_mem=4GB
  -c work_mem=256MB
  -c max_connections=500
  -c max_wal_size=8GB
  -c checkpoint_timeout=15min
  -c random_page_cost=1.1
  -c effective_io_concurrency=200
  -c max_worker_processes=16
  -c max_parallel_workers_per_gather=8
  -c max_parallel_workers=16
```

**Tile server**:
```bash
docker run ... \
  -e THREADS=16 \
  -e FLAT_NODES=enabled \
  --shm-size=8GB \
  --cpus=16 \
  -m 32G \
  ...
```

**Varnish**:
```yaml
environment:
  VARNISH_SIZE: 32G  # Or more if available
```

### Pre-rendering Strategy

**Phase 1**: Pre-render base layers (run overnight)
```bash
# Zoom 0-10 (entire world, ~2 hours)
render_list -a -z 0 -Z 10 -n 16

# Zoom 11-12 (Europe only, ~8 hours)
render_list -a -z 11 -Z 12 -n 16 -x <bounds> -y <bounds>
```

**Phase 2**: Pre-render cities (run over weekend)
```bash
# Major European cities at zoom 13-15
# Use city bounding boxes from OSM
```

**Phase 3**: On-demand rendering
- Zoom 13-18 rendered as requested
- Expired tiles re-rendered in background

### Monitoring

**Essential metrics**:
1. Tile request rate (req/s)
2. Cache hit rate (should be >80%)
3. Render queue length (should be <100)
4. Average render time per zoom level
5. PostgreSQL connection pool usage
6. Disk I/O and CPU usage

**Recommended tools**:
- Prometheus + Grafana for metrics
- mod_tile stats: `/mod_tile` endpoint
- PostgreSQL stats: `pg_stat_statements`

---

## Quick Wins Summary

**Immediate improvements (no architectural changes)**:

1. ✅ **Increase THREADS**: Set to 75% of CPU cores
2. ✅ **Enable FLAT_NODES**: For imports >1GB PBF
3. ✅ **Pre-render zoom 0-12**: Do once, benefit forever
4. ✅ **Increase Apache timeout**: Change to 60s for missing tiles
5. ✅ **Mount cache volume**: Ensure `/data/tiles/` persists
6. ✅ **Add Varnish**: 8GB RAM, 10x performance boost

**Example docker-compose with quick wins**:
```yaml
version: '3.8'

services:
  tile-server-db:
    # ... as before ...
    command: >
      postgres
      -c shared_buffers=2GB
      -c maintenance_work_mem=1GB
      -c work_mem=128MB
      -c effective_cache_size=8GB
      -c max_wal_size=4GB
      -c checkpoint_timeout=15min

  tile-server:
    image: overv/openstreetmap-tile-server
    shm_size: 2GB
    environment:
      THREADS: 12  # Adjust for your CPU
      FLAT_NODES: enabled
      PGHOST: tile-server-db
      # ... other vars ...
    volumes:
      - osm-tiles:/data/tiles/  # Persistent cache
```

Then after import, pre-render:
```bash
docker exec -it tile-server sudo -u renderer \
  render_list -a -z 0 -Z 12 -n 8
```

This should give you 5-10x better performance immediately!

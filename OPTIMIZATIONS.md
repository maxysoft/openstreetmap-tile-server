# Production Optimizations

This document describes the production optimizations applied to the OpenStreetMap tile server.

## Docker Image Optimizations

### 1. Multi-stage Build Cleanup
- **pip cache cleanup**: Added `--no-cache-dir` flag to `pip3 install` to prevent caching unnecessary files
- **npm cache cleanup**: Added `npm cache clean --force` after installing carto
- **Temporary files cleanup**: Added cleanup of `/root/.npm` and `/tmp/*` directories
- **Impact**: Reduces final image size by removing unnecessary build artifacts

### 2. Layer Optimization
- **Combined font downloads**: Merged two separate RUN commands for font downloads into a single layer
- **Combined Apache configuration**: Consolidated Apache module loading and log configuration into a single RUN command
- **Combined package installations**: Pip and npm package installations now happen in a single layer with cleanup
- **Impact**: Reduces the number of image layers from ~25 to ~22, improving build caching and reducing image overhead

## Docker Compose Production Enhancements

### 3. Restart Policy
- **Added**: `restart: unless-stopped` to both services
- **Benefit**: Containers automatically restart on failure or host reboot (unless explicitly stopped)
- **Production Ready**: Ensures high availability without manual intervention

### 4. PostgreSQL Performance Tuning
Optimized PostgreSQL configuration for production workloads:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `shared_buffers` | 512MB | Cache for frequently accessed data |
| `work_mem` | 64MB | Memory for query operations |
| `maintenance_work_mem` | 256MB | Memory for maintenance operations (VACUUM, INDEX) |
| `max_connections` | 200 | Support for concurrent connections |
| `effective_cache_size` | 2GB | Help query planner estimate available cache |
| `random_page_cost` | 1.1 | Optimized for SSD storage |
| `max_wal_size` | 2GB | Write-Ahead Log size for better write performance |

**Health Check Added**: PostgreSQL service includes health check using `pg_isready` to ensure database is accepting connections before starting dependent services.

### 5. Custom Networking
- **Added**: Dedicated bridge network `tile-network`
- **Benefits**:
  - Better isolation from other Docker applications
  - Automatic DNS resolution between services
  - Improved security with network segmentation
  - No need for legacy `--link` flags
  - Easier to add additional services (e.g., monitoring, caching)

### Additional Production Features
- **Service Dependencies**: Map service waits for PostgreSQL to be healthy before starting
- **Version Update**: Updated to docker-compose version 3.8 for latest features

## Performance Impact

### Image Size
- Previous layers: Multiple separate RUN commands created ~25 layers
- Optimized layers: Combined commands reduce to ~22 layers
- Cache cleanup reduces image size by removing build artifacts

### Startup Reliability
- Health checks ensure PostgreSQL is ready before tile server connects
- Automatic restarts handle transient failures
- Proper service dependencies prevent connection errors on startup

### Runtime Performance
- PostgreSQL tuning improves query performance and reduces disk I/O
- Custom network provides better isolation and DNS resolution
- Increased shared_buffers and work_mem improve tile rendering speed

## Usage

### Development
Use the standard docker-compose workflow:
```bash
docker-compose up -d
```

### Production
The optimized configuration is production-ready with:
- Automatic restarts
- Performance-tuned database
- Health monitoring
- Network isolation

### Monitoring Recommendations
For production monitoring, consider adding:
1. Prometheus exporters for metrics
2. Grafana dashboards for visualization
3. PgBouncer for connection pooling (for very high load)
4. Log aggregation (ELK stack or similar)
5. Resource limits (CPU/Memory constraints)

## Customization

### PostgreSQL Tuning
Adjust PostgreSQL parameters in `docker-compose.yml` based on your server specs:
- For 8GB RAM server: `shared_buffers=2GB`, `effective_cache_size=6GB`
- For 16GB RAM server: `shared_buffers=4GB`, `effective_cache_size=12GB`
- For 32GB RAM server: `shared_buffers=8GB`, `effective_cache_size=24GB`

### Network Configuration
The custom network can be extended to include other services:
```yaml
services:
  redis:
    image: redis:alpine
    networks:
      - tile-network
```

## Testing

All optimizations have been tested and verified:
- ✅ Docker image builds successfully
- ✅ Reduced number of layers
- ✅ Cache cleanup verified
- ✅ docker-compose.yml syntax validated
- ✅ PostgreSQL health checks functional
- ✅ Service dependencies working correctly
- ✅ Custom network isolation verified

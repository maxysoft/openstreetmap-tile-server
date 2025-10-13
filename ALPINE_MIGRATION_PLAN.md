# Migration Plan: Ubuntu 22.04 to Alpine Linux 3.22+

## Overview
Migrating the OpenStreetMap tile server from Ubuntu 22.04 to Alpine Linux would significantly reduce the image size and improve security through a smaller attack surface. However, this requires careful planning due to dependency differences.

## Current State Analysis

### Ubuntu 22.04 Image Dependencies
The current Dockerfile uses the following critical packages:
- **apache2** - Web server with mod_tile
- **renderd** - Tile rendering daemon
- **osm2pgsql** - OSM data import tool
- **postgresql-client-18** - PostgreSQL client
- **python3-mapnik** - Mapnik Python bindings
- **osmium-tool** - OSM data processing
- **osmosis** - OSM data replication
- **carto** (npm package) - CartoCSS compiler
- **Various fonts** - Noto fonts, Hanazono, etc.

### Alpine Linux Challenges

#### 1. Package Availability
Alpine uses `apk` package manager with a different repository structure:
- **Available in Alpine repositories**:
  - `apache2` ✓
  - `postgresql-client` ✓
  - `python3` ✓
  - `nodejs` / `npm` ✓
  - `gdal` ✓
  - `osmium-tool` ✓
  
- **Not readily available or requires building from source**:
  - `renderd` - Not in Alpine repos, must build from source
  - `mod_tile` - Apache module, must build from source
  - `osm2pgsql` - Available in edge/testing, may need building
  - `python3-mapnik` - Not packaged, requires building Mapnik
  - `osmosis` - Java-based, need to install Java runtime

#### 2. Library Compatibility
Alpine uses `musl libc` instead of `glibc`:
- Some C++ libraries may have compatibility issues
- Build processes may need adjustments
- Performance characteristics may differ

#### 3. Init System
Alpine uses OpenRC instead of systemd:
- Service management scripts need rewriting
- No `service apache2 restart` - use `rc-service apache2 restart`

## Migration Strategy

### Phase 1: Research & Preparation (1-2 weeks)

1. **Create Alpine test branch**
   - Set up parallel Alpine Dockerfile
   - Test package availability in Alpine 3.22

2. **Build custom packages**
   - Build `renderd` from source: https://github.com/openstreetmap/mod_tile
   - Build `osm2pgsql` if needed
   - Build Mapnik and Python bindings

3. **Identify font packages**
   - Map Ubuntu font packages to Alpine equivalents
   - Test font rendering quality

### Phase 2: Initial Alpine Dockerfile (2-3 weeks)

```dockerfile
FROM alpine:3.22 AS builder

# Install build dependencies
RUN apk add --no-cache \
    build-base \
    cmake \
    cairo-dev \
    mapnik-dev \
    boost-dev \
    iniparser-dev \
    apache2-dev \
    git

# Build mod_tile and renderd from source
RUN git clone https://github.com/openstreetmap/mod_tile.git && \
    cd mod_tile && \
    mkdir build && cd build && \
    cmake .. && \
    make && \
    make install

# Build osm2pgsql if not in repos
# ... (similar pattern)

FROM alpine:3.22

# Install runtime dependencies
RUN apk add --no-cache \
    apache2 \
    postgresql-client \
    python3 \
    py3-mapnik \
    nodejs \
    npm \
    gdal \
    osmium-tool \
    cairo \
    mapnik \
    iniparser \
    ttf-dejavu \
    ttf-liberation \
    # Font packages - need research
    bash \
    curl \
    sudo

# Copy compiled binaries from builder
COPY --from=builder /usr/local/lib/apache2/modules/mod_tile.so /usr/lib/apache2/modules/
COPY --from=builder /usr/local/bin/renderd /usr/bin/

# ... rest of configuration
```

### Phase 3: Testing & Validation (1-2 weeks)

1. **Functional testing**
   - Import test data (Luxembourg)
   - Verify tile rendering
   - Check all zoom levels
   - Validate font rendering

2. **Performance testing**
   - Compare rendering speed
   - Memory usage comparison
   - CPU utilization

3. **Integration testing**
   - Test with external PostgreSQL
   - Test update mechanisms
   - Test cron jobs

### Phase 4: Migration & Deployment (1 week)

1. **Update CI/CD**
   - Modify `.github/workflows/ci.yml`
   - Test workflow with Alpine image
   - Update documentation

2. **Documentation updates**
   - Update README.md
   - Create migration guide for users
   - Document any breaking changes

## Estimated Benefits

### Image Size Reduction
- **Current Ubuntu 22.04 image**: ~800-1200 MB
- **Estimated Alpine image**: ~400-600 MB
- **Savings**: ~40-50% size reduction

### Security Improvements
- Smaller attack surface
- Fewer installed packages
- Regular Alpine security updates

### Performance
- Potentially faster startup times
- Lower memory footprint
- Similar runtime performance (needs testing)

## Risks & Mitigation

### Risk 1: Package Compatibility
**Mitigation**: 
- Build critical packages from source
- Maintain builder stage for complex dependencies
- Thorough testing phase

### Risk 2: musl vs glibc Issues
**Mitigation**:
- Test all functionality extensively
- Keep Ubuntu image as fallback
- Document any known issues

### Risk 3: Service Management Differences
**Mitigation**:
- Rewrite service scripts for OpenRC
- Test service lifecycle thoroughly
- Update documentation

### Risk 4: Font Rendering Differences
**Mitigation**:
- Test font packages thoroughly
- Compare rendered tiles visually
- Adjust font configurations as needed

## Timeline Summary

| Phase | Duration | Key Deliverables |
|-------|----------|------------------|
| Research & Preparation | 1-2 weeks | Test environment, package list |
| Initial Dockerfile | 2-3 weeks | Working Alpine Dockerfile |
| Testing & Validation | 1-2 weeks | Test results, benchmark data |
| Migration & Deployment | 1 week | Updated CI/CD, documentation |
| **Total** | **5-8 weeks** | Production-ready Alpine image |

## Alternative: Minimal Ubuntu

If Alpine migration proves too complex, consider:

### Ubuntu Minimal Base
```dockerfile
FROM ubuntu:22.04-minimal
# Install only essential packages
# Remove unnecessary packages after installation
# Use multi-stage build to separate build and runtime
```

**Benefits**:
- Easier migration (same package manager)
- Reduced complexity
- Size reduction: ~30-40%

## Recommendation

1. **Start with Phase 1** to assess feasibility
2. **Create parallel Alpine branch** to avoid disrupting current workflow
3. **Consider Ubuntu Minimal** as intermediate step
4. **Maintain both images** initially for gradual migration

## Next Steps

1. Create GitHub issue to track Alpine migration
2. Set up test environment with Alpine 3.22
3. Research package availability in detail
4. Create proof-of-concept Dockerfile
5. Share findings with team for decision

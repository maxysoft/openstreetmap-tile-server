# Migration Plan: Debian Trixie (Testing) trixie-20250929-slim

## Overview
This document outlines the migration plan from Ubuntu 22.04 to Debian Trixie (Testing) using the `trixie-20250929-slim` base image.

## Current State
- Base Image: `ubuntu:22.04`
- PostgreSQL Client: version 18 from PostgreSQL APT repository
- Working system with all components functional

## Target State
- Base Image: `debian:trixie-20250929-slim`
- PostgreSQL Client: version compatible with Debian Trixie
- Same functionality as current system

## Benefits of Migration
1. **Smaller Image Size**: Debian slim images are typically smaller than Ubuntu
2. **Better for Containers**: Debian is often preferred for containerized applications
3. **Modern Packages**: Trixie is Debian Testing, providing newer package versions
4. **Consistency**: Better alignment with PostGIS container (based on Debian)

## Migration Steps

### Phase 1: Base Image Update
1. Change `FROM ubuntu:22.04` to `FROM debian:trixie-20250929-slim`
2. Update package manager commands if needed (apt should work the same)
3. Verify locale settings work with Debian

### Phase 2: Package Compatibility Review
Review all packages installed in the Dockerfile:
- `apache2` - Available in Debian
- `cron` - Available in Debian  
- `dateutils` - Available in Debian
- `fonts-*` packages - Verify availability in Trixie
- `gnupg2` - Available (may be `gnupg` in Debian)
- `gdal-bin` - Available in Debian
- `liblua5.3-dev` - Verify Lua version in Trixie
- `lua5.3` - Verify Lua version in Trixie
- `mapnik-utils` - Verify availability
- `npm` - Available in Debian
- `osm2pgsql` - Available in Debian
- `osmium-tool` - Available in Debian
- `osmosis` - Available in Debian
- `postgresql-client-18` - May need to adjust version
- `python-is-python3` - Available in Debian
- `python3-mapnik` - Verify availability
- `python3-lxml` - Available in Debian
- `python3-psycopg2` - Available in Debian
- `python3-shapely` - Available in Debian
- `python3-pip` - Available in Debian
- `python3-yaml` - Available in Debian
- `python3-requests` - Available in Debian
- `renderd` - Verify availability
- `sudo` - Available in Debian
- `vim` - Available in Debian

### Phase 3: PostgreSQL Repository Setup
Debian Trixie uses different code names. Update repository setup:
```dockerfile
RUN sh -c 'echo "deb http://apt.postgresql.org/pub/repos/apt $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list'
```
Note: Verify that PostgreSQL APT repository supports Debian Trixie. May need to use `trixie-pgdg` or fallback to Debian's native PostgreSQL packages.

### Phase 4: Testing Plan
1. **Build Test**: Verify Dockerfile builds successfully
2. **Import Test**: Test data import with Luxembourg dataset
3. **Render Test**: Verify tile rendering works
4. **Integration Test**: Run full CI workflow
5. **Performance Test**: Compare performance with Ubuntu-based image

### Phase 5: Known Issues and Workarounds

#### Issue 1: PostgreSQL Client Version
Debian Trixie may have a different default PostgreSQL version.
- **Solution**: Explicitly specify `postgresql-client-18` or use Trixie's default version

#### Issue 2: Package Name Changes
Some packages may have different names in Debian vs Ubuntu.
- **Solution**: Check Debian package search and update package names as needed

#### Issue 3: Font Packages
Font package names might differ between distributions.
- **Solution**: Verify all `fonts-*` packages exist in Debian Trixie repositories

#### Issue 4: Renderd Availability
Renderd may not be available in Debian Trixie repositories.
- **Solution**: May need to build from source or use backports

### Phase 6: Rollback Plan
If migration fails:
1. Revert Dockerfile to use `ubuntu:22.04`
2. Document specific incompatibilities found
3. Create issues for packages not available in Debian
4. Consider alternative: Debian Bookworm (stable) instead of Trixie (testing)

## Implementation Timeline

### Week 1: Research and Preparation
- [ ] Verify all packages are available in Debian Trixie
- [ ] Test PostgreSQL repository compatibility
- [ ] Check for any Debian-specific configuration requirements

### Week 2: Initial Migration
- [ ] Update Dockerfile base image
- [ ] Update package installation commands
- [ ] Build and test locally

### Week 3: Testing and Refinement
- [ ] Run comprehensive tests
- [ ] Fix any issues found
- [ ] Document changes and workarounds

### Week 4: CI/CD Integration
- [ ] Update CI workflow if needed
- [ ] Run full test suite in CI
- [ ] Update documentation

## Risk Assessment

### Low Risk
- Base package installation (most packages have same names)
- Apache configuration
- Python packages

### Medium Risk
- PostgreSQL client version compatibility
- Font packages availability
- Renderd package availability

### High Risk
- None identified at this time

## Alternative Approach
If Debian Trixie (testing) proves problematic, consider:
1. **Debian Bookworm**: Use stable release `debian:bookworm-slim`
2. **Alpine Linux**: Consider Alpine-based image (see ALPINE_MIGRATION_PLAN.md)
3. **Ubuntu Minimal**: Use `ubuntu:22.04-minimal` for smaller image size

## Success Criteria
- [x] Docker image builds successfully
- [x] Image size is equal or smaller than current image (1.64GB)
- [ ] All CI tests pass (requires PR merge and CI run)
- [ ] Tile rendering performance is equivalent or better (requires testing)
- [ ] No regressions in functionality (requires testing)
- [x] Documentation is updated

## Migration Completed (October 2025)

The migration to Debian Trixie has been successfully completed with the following changes:

### Implemented Changes
1. **Base Image**: Changed from `ubuntu:22.04` to `debian:trixie-20250929-slim`
2. **Node.js**: Upgraded to 22.20.0 LTS (Jod) from NodeSource repository
3. **npm**: Version 10.9.3 (bundled with Node.js 22.x)
4. **carto**: Already at latest version 1.2.0
5. **Package Adjustments**:
   - Replaced `unrar` with `unrar-free` (Debian native)
   - Replaced `pip install osmium` with `python3-pyosmium` package
   - Combined Node.js setup with package installation to reduce layers

### Build Optimizations
- Reduced Docker layers by combining Node.js repository setup with package installation
- Maintained cache cleanup for npm and temporary files
- Image size: 1.64GB (same as Ubuntu version)

### Testing Status
- [x] Docker build completes successfully
- [x] Node.js and npm versions verified
- [x] All packages install correctly
- [x] Mapnik PostGIS plugin configuration fixed (renderd.conf)
- [ ] Full CI tests (pending PR merge)
- [ ] Tile rendering validation (pending deployment)

### Notes
- PostgreSQL client 18 works correctly with Debian Trixie
- All font packages available in Debian repositories
- Python 3.13 enforces PEP 668, resolved by using Debian native packages
- CI workflow updated to handle new base image tag format
- Fixed renderd.conf to properly configure Mapnik 4.0 plugins_dir (see FIX_NOTES.md)

## References
- Debian Trixie Release Info: https://www.debian.org/releases/trixie/
- PostgreSQL APT Repository: https://wiki.postgresql.org/wiki/Apt
- Debian Package Search: https://packages.debian.org/
- PostGIS Docker Images: https://github.com/postgis/docker-postgis

# CI Workflow Refactor

This document describes the refactoring of the image builder workflow based on the nominatim-docker example.

## Summary of Changes

### File Changes
- **Renamed**: `.github/workflows/build-and-test.yaml` → `.github/workflows/ci.yml`
- **Removed**: `.travis.yml` (deprecated Travis CI configuration)
- **Updated**: `README.md` badge from Travis CI to GitHub Actions

### Workflow Structure

The workflow has been refactored following the nominatim-docker pattern with three distinct jobs:

#### 1. Build Job
- **Purpose**: Build the Docker image once and export it as an artifact
- **Key changes**:
  - Removed multi-architecture matrix (moved to publish job)
  - Simplified to build for testing only
  - Exports image as tar file artifact
  - No longer embeds testing in the build job

#### 2. Test Job
- **Purpose**: Download the built image and run comprehensive tests
- **Key features**:
  - Downloads artifact from build job
  - Loads Docker image from tar file
  - Starts PostgreSQL container
  - Imports Luxembourg test data
  - Starts tile server
  - Downloads and verifies tiles
  - Cleans up containers and volumes
- **Benefits**: Separates testing from building, making the workflow more modular

#### 3. Publish Job
- **Purpose**: Build and push multi-architecture images to registries
- **Key changes**:
  - Renamed from "deploy" to "publish" for clarity
  - Only runs on push to master branch (not on PRs)
  - Builds for both linux/amd64 and linux/arm64/v8
  - Pushes to Docker Hub (if credentials configured) and GHCR
  - Uses GitHub Actions cache for faster builds

### Workflow Triggers

Changed from:
```yaml
on:
  push:
    branches:
    - master
    tags:
    - 'v[0-9]+.[0-9]+.[0-9]+'
  pull_request:
    branches:
    - master
```

To:
```yaml
on:
  push:
  pull_request:
  workflow_dispatch:
```

**Benefits**:
- Simpler trigger configuration
- Runs on all pushes and PRs (not just master branch)
- Added `workflow_dispatch` for manual triggering
- Branch/tag filtering handled in job conditions instead

### Key Improvements

1. **Separation of Concerns**: Build, test, and publish are now separate jobs
2. **Artifact-based Testing**: Build job exports image as artifact, test job imports it
3. **Cleaner Structure**: Following the nominatim-docker pattern for consistency
4. **Standard Naming**: Using `ci.yml` instead of `build-and-test.yaml`
5. **Modern Practices**: Using GitHub Actions cache without scope restrictions
6. **Removed Travis CI**: Eliminated deprecated `.travis.yml` file

### Maintained Features

- ✅ Multi-architecture support (amd64, arm64)
- ✅ GitHub Actions cache
- ✅ PostgreSQL container setup for testing
- ✅ Luxembourg data import test
- ✅ Tile download and verification
- ✅ Docker Hub and GHCR publishing
- ✅ Concurrency control (cancel outdated jobs)
- ✅ Modern action versions (v4, v5)

## Comparison with nominatim-docker

The refactored workflow now follows the same pattern as nominatim-docker:

| Feature | nominatim-docker | openstreetmap-tile-server |
|---------|------------------|---------------------------|
| Workflow name | CI | CI ✅ |
| Build job | Exports artifact | Exports artifact ✅ |
| Test job | Downloads artifact | Downloads artifact ✅ |
| Publish job | Pushes to registries | Pushes to registries ✅ |
| Multi-arch | In publish job | In publish job ✅ |
| Triggers | push/PR/workflow_dispatch | push/PR/workflow_dispatch ✅ |

## Testing

The workflow structure has been validated:
- ✅ YAML syntax is valid
- ✅ All required GitHub Actions are at latest versions
- ✅ Job dependencies are properly configured (test depends on build, publish depends on test)
- ✅ Conditional execution is correct (publish only on push to master)

## Future Enhancements

Potential improvements that could be added later:
- Add matrix testing with different test scenarios (like nominatim-docker)
- Add more comprehensive tile verification
- Add performance benchmarks
- Add security scanning for the Docker image

# Pre-rendering Bounding Box Examples

This document provides bounding box (bbox) coordinates for common regions to use with the `PRERENDER_BBOX` environment variable when pre-rendering tiles.

## What is PRERENDER_BBOX?

The `PRERENDER_BBOX` environment variable defines the geographic area for tile pre-rendering. It uses the format:
```
lon_min,lat_min,lon_max,lat_max
```

Where:
- `lon_min`: Minimum longitude (west)
- `lat_min`: Minimum latitude (south)
- `lon_max`: Maximum longitude (east)
- `lat_max`: Maximum latitude (north)

## Why Use Region-Specific Bounding Boxes?

Using a region-specific bbox instead of the world bbox (`-180,-90,180,90`) significantly reduces:
- **Pre-rendering time**: Only renders tiles for your region of interest
- **Disk space**: Fewer tiles to store
- **Resource usage**: Less CPU and memory needed

For example, pre-rendering the entire world at zoom 0-12 can take many hours, while pre-rendering just Italy might take only 10-30 minutes.

## Common Region Bounding Boxes

### Europe

#### Full Europe
```bash
PRERENDER_BBOX=-10,35,40,70
```

#### Southern Europe
```bash
PRERENDER_BBOX=-10,35,30,50
```

#### Northern Europe
```bash
PRERENDER_BBOX=-10,50,40,70
```

### Individual European Countries

#### Italy
```bash
PRERENDER_BBOX=6.6,35.5,18.5,47.1
```

#### France
```bash
PRERENDER_BBOX=-5.5,41.3,9.6,51.1
```

#### Germany
```bash
PRERENDER_BBOX=5.9,47.3,15.0,55.1
```

#### Spain
```bash
PRERENDER_BBOX=-9.3,35.9,4.3,43.8
```

#### United Kingdom
```bash
PRERENDER_BBOX=-8.6,49.9,1.8,60.8
```

#### Luxembourg (small dataset for testing)
```bash
PRERENDER_BBOX=5.7,49.4,6.5,50.2
```

### Other Regions

#### North America
```bash
PRERENDER_BBOX=-170,15,-50,75
```

#### USA (Continental)
```bash
PRERENDER_BBOX=-125,24,-66,49
```

#### Asia
```bash
PRERENDER_BBOX=25,0,180,80
```

#### Africa
```bash
PRERENDER_BBOX=-18,-35,52,38
```

#### South America
```bash
PRERENDER_BBOX=-82,-56,-34,13
```

#### Australia
```bash
PRERENDER_BBOX=112,-44,154,-10
```

## Usage Examples

### Docker Run Command

```bash
docker run -p 8080:80 \
    -e DOWNLOAD_PBF=https://download.geofabrik.de/europe/italy-latest.osm.pbf \
    -e DOWNLOAD_POLY=https://download.geofabrik.de/europe/italy.poly \
    -e PRERENDER_ZOOMS=0-12 \
    -e PRERENDER_BBOX=6.6,35.5,18.5,47.1 \
    -v osm-tiles:/data/tiles/ \
    --link postgres:postgres \
    -e PGHOST=postgres \
    -d overv/openstreetmap-tile-server
```

### Docker Compose

In your `docker-compose.yml`:

```yaml
services:
  tile-server:
    environment:
      DOWNLOAD_PBF: https://download.geofabrik.de/europe/italy-latest.osm.pbf
      DOWNLOAD_POLY: https://download.geofabrik.de/europe/italy.poly
      PRERENDER_ZOOMS: 0-12
      PRERENDER_BBOX: 6.6,35.5,18.5,47.1  # Italy
```

## Finding Custom Bounding Boxes

If you need a bbox for a region not listed here, you can:

1. **Use OSM Wiki**: Check the [OpenStreetMap Bounding Box page](https://wiki.openstreetmap.org/wiki/Bounding_Box)

2. **Use boundingbox.klokantech.com**: Visit http://boundingbox.klokantech.com/ and:
   - Search for your region
   - Select "CSV" format
   - Copy the coordinates in the order: lon_min,lat_min,lon_max,lat_max

3. **Use Nominatim**: Query the OSM Nominatim API:
   ```bash
   curl "https://nominatim.openstreetmap.org/search?q=Italy&format=json&limit=1" | jq '.[0].boundingbox'
   ```

4. **Manual Selection**: Use https://www.openstreetmap.org/export and draw a box around your region

## Default Behavior

If `PRERENDER_BBOX` is not set, the system defaults to the world bounding box:
```bash
PRERENDER_BBOX=-180,-90,180,90
```

This renders tiles for the entire world, which is appropriate if you've imported the full planet OSM dataset.

## Best Practices

1. **Match Your Import**: Set the bbox to match the region you imported from Geofabrik or other sources
2. **Slightly Larger**: Consider making the bbox slightly larger than your exact region to avoid edge artifacts
3. **Test First**: For large regions, test with a smaller zoom range (e.g., 0-8) before doing a full pre-render
4. **Monitor Resources**: Watch disk space and CPU usage during pre-rendering
5. **Use Geofabrik Extracts**: Use pre-made extracts from https://download.geofabrik.de/ that match common bboxes

## Zoom Level Recommendations by Region Size

| Region Size | Recommended Max Zoom | Disk Space (approx) | Pre-render Time |
|-------------|---------------------|---------------------|-----------------|
| Country (Italy) | 12 | 5-10 GB | 30-60 min |
| Continent (Europe) | 10 | 10-20 GB | 2-4 hours |
| World | 8 | 20-50 GB | 8-12 hours |

*Estimates are approximate and depend on your hardware and data density*

## Troubleshooting

### Pre-rendering Takes Too Long
- Reduce `PRERENDER_ZOOMS` (e.g., 0-10 instead of 0-12)
- Make the bbox smaller to cover only your essential area
- Increase `THREADS` environment variable if you have more CPU cores

### Out of Disk Space
- Reduce the maximum zoom level
- Use a smaller bbox
- Clean up old tiles: `rm -rf /data/tiles/*`

### Tiles Not Rendering for My Region
- Verify your bbox coordinates are correct (lon before lat!)
- Check that you imported the correct PBF file for your region
- Ensure bbox covers your imported data region

## References

- [Tirex Documentation](https://wiki.openstreetmap.org/wiki/Tirex)
- [tirex-batch Command](https://wiki.openstreetmap.org/wiki/Tirex/Commands/tirex-batch)
- [Geofabrik Downloads](https://download.geofabrik.de/)
- [OpenStreetMap Bounding Boxes](https://wiki.openstreetmap.org/wiki/Bounding_Box)

#!/usr/bin/env python3
"""
Prerender tiles for OpenStreetMap tile server.

This script prerenders tiles by making HTTP requests to the tile server.
It can be used to warm up the tile cache for a specific region and zoom level range.
"""

import argparse
import requests
import sys
import time
import math
from concurrent.futures import ThreadPoolExecutor, as_completed


def deg2num(lat_deg, lon_deg, zoom):
    """Convert latitude, longitude to tile numbers at given zoom level."""
    lat_rad = math.radians(lat_deg)
    n = 2.0 ** zoom
    xtile = int((lon_deg + 180.0) / 360.0 * n)
    ytile = int((1.0 - math.asinh(math.tan(lat_rad)) / math.pi) / 2.0 * n)
    return xtile, ytile


def get_tile_bounds(min_lat, min_lon, max_lat, max_lon, zoom):
    """Get tile coordinate bounds for a bounding box at given zoom level."""
    min_x, max_y = deg2num(min_lat, min_lon, zoom)
    max_x, min_y = deg2num(max_lat, max_lon, zoom)
    return min_x, min_y, max_x, max_y


def render_tile(host, port, z, x, y, timeout=60):
    """Render a single tile by making HTTP request."""
    url = f"http://{host}:{port}/tile/{z}/{x}/{y}.png"
    try:
        response = requests.get(url, timeout=timeout)
        if response.status_code == 200:
            return True, f"✓ {z}/{x}/{y}"
        else:
            return False, f"✗ {z}/{x}/{y} (HTTP {response.status_code})"
    except Exception as e:
        return False, f"✗ {z}/{x}/{y} (Error: {str(e)})"


def render_tiles(host, port, min_zoom, max_zoom, bbox=None, threads=4, verbose=False):
    """
    Render tiles for specified zoom levels and bounding box.
    
    Args:
        host: Tile server hostname
        port: Tile server port
        min_zoom: Minimum zoom level
        max_zoom: Maximum zoom level
        bbox: Bounding box as (min_lat, min_lon, max_lat, max_lon), defaults to world
        threads: Number of parallel threads for rendering
        verbose: Print detailed progress
    """
    # Default to world bounds if not specified
    if bbox is None:
        bbox = (-85.0511, -180, 85.0511, 180)
    
    min_lat, min_lon, max_lat, max_lon = bbox
    
    total_tiles = 0
    successful_tiles = 0
    failed_tiles = 0
    
    print(f"Prerendering tiles for zoom levels {min_zoom}-{max_zoom}")
    print(f"Bounding box: lat({min_lat}, {max_lat}), lon({min_lon}, {max_lon})")
    print(f"Using {threads} threads")
    print()
    
    for zoom in range(min_zoom, max_zoom + 1):
        min_x, min_y, max_x, max_y = get_tile_bounds(min_lat, min_lon, max_lat, max_lon, zoom)
        
        # Calculate number of tiles at this zoom level
        tiles_x = max_x - min_x + 1
        tiles_y = max_y - min_y + 1
        zoom_tiles = tiles_x * tiles_y
        total_tiles += zoom_tiles
        
        print(f"Zoom {zoom}: {zoom_tiles} tiles (x: {min_x}-{max_x}, y: {min_y}-{max_y})")
        
        zoom_successful = 0
        zoom_failed = 0
        last_update_time = time.time()
        
        # Create list of tiles to render
        tiles = [(zoom, x, y) for x in range(min_x, max_x + 1) for y in range(min_y, max_y + 1)]
        
        # Render tiles in parallel
        with ThreadPoolExecutor(max_workers=threads) as executor:
            futures = {executor.submit(render_tile, host, port, z, x, y): (z, x, y) 
                      for z, x, y in tiles}
            
            for future in as_completed(futures):
                success, message = future.result()
                if success:
                    zoom_successful += 1
                    successful_tiles += 1
                else:
                    zoom_failed += 1
                    failed_tiles += 1
                
                if verbose or not success:
                    print(message)
                else:
                    # Update progress every 100 tiles or every 5 seconds
                    current_time = time.time()
                    if zoom_successful % 100 == 0 or (current_time - last_update_time) >= 5:
                        percent = (zoom_successful / zoom_tiles * 100) if zoom_tiles > 0 else 0
                        print(f"  Progress: {zoom_successful}/{zoom_tiles} tiles ({percent:.1f}%)", end='\r')
                        last_update_time = current_time
        
        print(f"  Zoom {zoom} complete: {zoom_successful} successful, {zoom_failed} failed")
        print()
    
    print("=" * 60)
    print(f"Prerendering complete!")
    print(f"Total tiles: {total_tiles}")
    print(f"Successful: {successful_tiles}")
    print(f"Failed: {failed_tiles}")
    
    return successful_tiles, failed_tiles


def parse_bbox(bbox_str):
    """Parse bounding box string in format 'min_lat,min_lon,max_lat,max_lon'."""
    try:
        parts = [float(x.strip()) for x in bbox_str.split(',')]
        if len(parts) != 4:
            raise ValueError("Bounding box must have 4 values")
        return tuple(parts)
    except Exception as e:
        raise argparse.ArgumentTypeError(f"Invalid bounding box format: {e}")


# Predefined bounding boxes for common regions
REGIONS = {
    'world': (-85.0511, -180, 85.0511, 180),
    'europe': (35.0, -10.0, 71.0, 40.0),
    'denmark': (54.5, 8.0, 58.0, 15.5),
    'luxembourg': (49.4, 5.7, 50.2, 6.6),
    'germany': (47.0, 5.5, 55.5, 15.5),
    'france': (42.0, -5.5, 51.5, 10.0),
    'uk': (49.5, -8.5, 61.0, 2.0),
    'spain': (36.0, -9.5, 43.8, 4.5),
    'italy': (36.5, 6.5, 47.5, 19.0),
}


def main():
    parser = argparse.ArgumentParser(
        description='Prerender tiles for OpenStreetMap tile server',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=f"""
Examples:
  # Prerender Europe at zoom levels 0-8
  %(prog)s --region europe --min-zoom 0 --max-zoom 8

  # Prerender Denmark at zoom levels 0-14 with 8 threads
  %(prog)s --region denmark --min-zoom 0 --max-zoom 14 --threads 8

  # Prerender custom bounding box
  %(prog)s --bbox "49.4,5.7,50.2,6.6" --min-zoom 0 --max-zoom 12

Available regions: {', '.join(REGIONS.keys())}
"""
    )
    
    parser.add_argument('--host', default='localhost', help='Tile server hostname (default: localhost)')
    parser.add_argument('--port', type=int, default=80, help='Tile server port (default: 80)')
    parser.add_argument('--min-zoom', type=int, required=True, help='Minimum zoom level (e.g., 0)')
    parser.add_argument('--max-zoom', type=int, required=True, help='Maximum zoom level (e.g., 14)')
    parser.add_argument('--region', choices=list(REGIONS.keys()), help='Predefined region to render')
    parser.add_argument('--bbox', type=parse_bbox, help='Custom bounding box: min_lat,min_lon,max_lat,max_lon')
    parser.add_argument('--threads', type=int, default=4, help='Number of parallel threads (default: 4)')
    parser.add_argument('-v', '--verbose', action='store_true', help='Verbose output')
    
    args = parser.parse_args()
    
    # Validate zoom levels
    if args.min_zoom < 0 or args.max_zoom > 20:
        parser.error("Zoom levels must be between 0 and 20")
    if args.min_zoom > args.max_zoom:
        parser.error("min-zoom must be less than or equal to max-zoom")
    
    # Determine bounding box
    if args.bbox:
        bbox = args.bbox
    elif args.region:
        bbox = REGIONS[args.region]
    else:
        parser.error("Either --region or --bbox must be specified")
    
    # Wait for server to be ready
    print(f"Waiting for tile server at {args.host}:{args.port}...")
    max_retries = 30
    for i in range(max_retries):
        try:
            response = requests.get(f"http://{args.host}:{args.port}/", timeout=5)
            if response.status_code in [200, 404]:  # Server is responding
                print("Tile server is ready!")
                break
        except Exception:
            pass
        
        if i < max_retries - 1:
            time.sleep(2)
        else:
            print(f"ERROR: Tile server not responding after {max_retries * 2} seconds", file=sys.stderr)
            return 1
    
    print()
    
    # Render tiles
    successful, failed = render_tiles(
        args.host, args.port, args.min_zoom, args.max_zoom, 
        bbox=bbox, threads=args.threads, verbose=args.verbose
    )
    
    # Return exit code based on results
    if failed > 0:
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())

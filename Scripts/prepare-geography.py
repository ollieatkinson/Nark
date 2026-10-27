#!/usr/bin/env python3
"""Convert pinned public datasets to bounded, offline lookup/rendering resources.
Usage: prepare-geography.py COUNTRY.csv.gz WORLD.geojson
Downloads and attribution are documented in Sources/Geography/Resources/Attribution.txt.
"""
import csv, gzip, hashlib, ipaddress, json, pathlib, sys
out = pathlib.Path(__file__).resolve().parent.parent / 'Sources/Geography/Resources'
source, world = map(pathlib.Path, sys.argv[1:])
assert hashlib.sha1(gzip.decompress(source.read_bytes())).hexdigest() == 'c8ad1dfe98cb29bcacd82a5c3ec361c880e5bb59', 'Unexpected DB-IP release'
assert hashlib.sha256(world.read_bytes()).hexdigest() == '6866c877d39cba9c357620878839b336d569f8c662d3cfab4cb1dbe2d39c977f', 'Unexpected Natural Earth source'
files = {4: bytearray(), 6: bytearray()}
previous = {}
with gzip.open(source, 'rt') as stream:
    for start, end, code in csv.reader(stream):
        a, b = ipaddress.ip_address(start), ipaddress.ip_address(end)
        assert a.version == b.version and int(a) <= int(b) and len(code) == 2
        assert int(a) > previous.get(a.version, -1), 'Overlapping ranges'
        previous[a.version] = int(b)
        files[a.version].extend(a.packed + b.packed + code.encode('ascii'))
for version, content in files.items():
    (out / f'country-v{version}.bin').write_bytes(content)
# Equirectangular country mask, longitude -180...180 and latitude 85...-60.
# Each pixel stores its two-letter country code; ocean is two spaces.
w, h = 720, 290
pixels = bytearray(b'  ' * w * h)
for feature in json.loads(world.read_text())['features']:
    code = feature['properties']['ISO_A2_EH']
    if len(code) != 2: continue
    polygons = feature['geometry']['coordinates']
    if feature['geometry']['type'] == 'Polygon': polygons = [polygons]
    for polygon in polygons:
        # Fill using even-odd scanlines, including holes.
        ys = [p[1] for ring in polygon for p in ring]
        for y in range(max(0, int((85-max(ys))/145*h)), min(h, int((85-min(ys))/145*h)+1)):
            lat = 85-(y+.5)/h*145
            hits = []
            for ring in polygon:
                for a,b in zip(ring, ring[1:]):
                    if (a[1] > lat) != (b[1] > lat): hits.append(a[0]+(lat-a[1])*(b[0]-a[0])/(b[1]-a[1]))
            hits.sort()
            for left,right in zip(hits[::2], hits[1::2]):
                for x in range(max(0, int((left+180)/360*w+.5)), min(w, int((right+180)/360*w+.5))):
                    pixels[(y*w+x)*2:(y*w+x)*2+2] = code.encode('ascii')
(out/'world.bin').write_bytes(pixels)
print({f.name: f.stat().st_size for f in out.glob('*.bin')})
print('Natural Earth source SHA256:', hashlib.sha256(world.read_bytes()).hexdigest())

points = {f['properties']['ISO_A2_EH']: {'latitude': f['properties']['LABEL_Y'], 'longitude': f['properties']['LABEL_X']} for f in json.loads(world.read_text())['features'] if len(f['properties']['ISO_A2_EH']) == 2}
(out/'country-points.json').write_text(json.dumps(points, sort_keys=True, separators=(',', ':')))

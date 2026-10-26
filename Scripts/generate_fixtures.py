#!/usr/bin/env python3
"""Generate original CC0 equirectangular calibration videos; ffmpeg is the only dependency."""
from pathlib import Path
import json
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT/'Fixtures/generated'
GLYPHS = {
 'A':['01110','10001','10001','11111','10001','10001','10001'],
 'B':['11110','10001','10001','11110','10001','10001','11110'],
 'D':['11110','10001','10001','10001','10001','10001','11110'],
 'E':['11111','10000','10000','11110','10000','10000','11111'],
 'F':['11111','10000','10000','11110','10000','10000','10000'],
 'G':['01111','10000','10000','10111','10001','10001','01111'],
 'H':['10001','10001','10001','11111','10001','10001','10001'],
 'I':['11111','00100','00100','00100','00100','00100','11111'],
 'L':['10000','10000','10000','10000','10000','10000','11111'],
 'M':['10001','11011','10101','10101','10001','10001','10001'],
 'N':['10001','11001','10101','10011','10001','10001','10001'],
 'O':['01110','10001','10001','10001','10001','10001','01110'],
 'R':['11110','10001','10001','11110','10100','10010','10001'],
 'S':['01111','10000','10000','01110','00001','00001','11110'],
 'T':['11111','00100','00100','00100','00100','00100','00100'],
 'U':['10001','10001','10001','10001','10001','10001','01110'],
 'V':['10001','10001','10001','10001','10001','01010','00100'],
 'Y':['10001','10001','01010','00100','00100','00100','00100'],
 '0':['01110','10001','10011','10101','11001','10001','01110'],
 '1':['00100','01100','00100','00100','00100','00100','01110'],
 '3':['11110','00001','00001','01110','00001','00001','11110'],
 '6':['01110','10000','10000','11110','10001','10001','01110'],
 '8':['01110','10001','10001','01110','10001','10001','01110'],
}

def image(path, width, height, projection, label, eye):
    background = (86,49,38) if eye == 0 else (25,62,101)
    pixels = bytearray(background * (width*height))
    def put(x,y,color):
        if 0 <= x < width and 0 <= y < height:
            offset = (y*width+x)*3; pixels[offset:offset+3] = bytes(color)
    for y in range(height):
        for x in range(width):
            if x % (width//8) < 2 or y % 64 < 2: put(x,y,(130,130,130))
    def text(value, y, color=(255,255,255), scale=3):
        x = (width-len(value)*6*scale)//2
        for letter in value:
            glyph = GLYPHS.get(letter, ['00000']*7)
            for gy,line in enumerate(glyph):
                for gx,bit in enumerate(line):
                    if bit == '1':
                        for sy in range(scale):
                            for sx in range(scale): put(x+gx*scale+sx,y+gy*scale+sy,color)
            x += 6*scale
    text(projection.upper()+' '+label,height//2-65)
    text('FRONT',height//2-20,(255,255,0))
    text('NORTH',40); text('SOUTH',height-60)
    # Asymmetric corner markers expose vertical inversion and left/right mirroring.
    for y in range(90,110):
        for x in range(30,90): put(x,y,(255,255,255))
    path.write_bytes(f'P6\n{width} {height}\n255\n'.encode()+pixels)

def run(args):
    subprocess.run(args, check=True)

def make_video(projection, layout):
    width, height = (512, 512) if projection == 'vr180' else (1024, 512)
    args = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y']
    eyes = 1 if layout == 'mono' else 2
    for eye in range(eyes):
        label = 'MONO' if eyes == 1 else ('LEFT EYE' if eye == 0 else 'RIGHT EYE')
        ppm = OUT/f'{projection}-{layout}-{eye}.ppm'
        image(ppm,width,height,projection,label,eye)
        args += ['-loop', '1', '-framerate', '30', '-i', str(ppm)]
    args += ['-f', 'lavfi', '-i', 'sine=frequency=440:sample_rate=48000:duration=8']
    filters = []
    for eye in range(eyes):
        filters.append(f"[{eye}:v]drawbox=x={width//2-8}:y={height//2+40}:w=16:h=16:c=lime:t=fill:enable='lt(mod(t,2),1)'[v{eye}]")
    if eyes == 2:
        filters.append(f'[v0][v1]{"hstack" if layout == "sbs" else "vstack"}=inputs=2[out]')
    output = OUT/f'{projection}-{layout}.mp4'
    args += ['-filter_complex', ';'.join(filters), '-map', '[out]' if eyes == 2 else '[v0]', '-map', f'{eyes}:a',
             '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '22', '-pix_fmt', 'yuv420p',
             '-g', '60', '-keyint_min', '60', '-sc_threshold', '0', '-c:a', 'aac', '-b:a', '64k',
             '-movflags', '+faststart', '-t', '8', '-shortest', str(output)]
    run(args)
    target = OUT/'hls'/f'{projection}-{layout}'
    target.mkdir(parents=True, exist_ok=True)
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(output), '-c', 'copy',
         '-hls_time', '2', '-hls_playlist_type', 'vod', '-hls_flags', 'independent_segments',
         '-hls_segment_filename', str(target/'segment-%03d.ts'), str(target/'master.m3u8')])
    return {'name': output.name, 'projection': projection, 'layout': layout,
            'hls': f'hls/{projection}-{layout}/master.m3u8', 'licence': 'CC0-1.0'}

def main():
    if not shutil.which('ffmpeg'): raise SystemExit('Install ffmpeg, then rerun this script.')
    OUT.mkdir(parents=True, exist_ok=True)
    manifest = [make_video(projection, layout) for projection in ['vr180', 'vr360'] for layout in ['mono','sbs','tb']]
    make_controls_demo()
    make_quality_demo()
    make_metadata_demos()
    make_4k_quality_demo()
    make_context_sample()
    make_disparity_samples()
    (OUT/'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
    (OUT/'LICENSE.txt').write_text('Original VisionStream calibration media. Dedicated to the public domain under CC0 1.0 Universal.\nhttps://creativecommons.org/publicdomain/zero/1.0/\n')
    cards = ''.join(f'<section><h2>{item["name"]}</h2><video controls playsinline preload="metadata" width="420"><source src="{item["name"]}" type="video/mp4"></video><p><a href="{item["hls"]}">HLS playlist</a></p></section>' for item in manifest)
    (OUT/'index.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><title>VisionStream CC0 calibration streams</title>
<style>body{font:18px system-ui;margin:40px;color:#eee;background:#18202a}video{max-width:100%}section{display:inline-block;vertical-align:top;margin:16px}</style>
<h1>VisionStream CC0 calibration streams</h1><p>Generated equirectangular grids, 8 seconds, H.264 + AAC. Match projection and eye layout to the filename.</p>
<p><a href="/auth-test">Cookie handoff fixture</a> · <a href="negative.html">Blob negative case</a></p>''' + cards + '''
<h2>Frame source</h2><iframe src="frame.html" width="450" height="350"></iframe>
<h2>Open shadow root</h2><div id="shadow"></div><script>document.querySelector('#shadow').attachShadow({mode:'open'}).innerHTML='<video controls playsinline width="420" src="vr180-sbs.mp4"></video>';</script></html>''')
    (OUT/'frame.html').write_text('<!doctype html><title>Frame video</title><video controls playsinline width="400" src="vr360-mono.mp4"></video>')
    (OUT/'negative.html').write_text('''<!doctype html><title>Blob negative fixture</title><h1>Browser-local MediaSource</h1><p>Expected: no native handoff. A stale fallback source must not be advertised once currentSrc is a blob.</p><video id="v" controls><source src="vr180-sbs.mp4" type="video/mp4"></video><script>if(window.MediaSource){const source=new MediaSource();document.querySelector('#v').src=URL.createObjectURL(source);}</script>''')
    print(f'Generated {len(manifest)} MP4s and {len(manifest)} HLS playlists in {OUT}')

def make_controls_demo():
    # A longer original clip gives a human time to inspect controls before EOF.
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-stream_loop', '3',
         '-i', str(OUT/'vr180-mono.mp4'), '-c', 'copy', '-movflags', '+faststart', str(OUT/'controls-demo.mp4')])
    target = OUT/'hls'/'controls-demo'
    target.mkdir(parents=True, exist_ok=True)
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(OUT/'controls-demo.mp4'),
         '-c', 'copy', '-hls_time', '2', '-hls_playlist_type', 'vod', '-hls_flags', 'independent_segments',
         '-hls_segment_filename', str(target/'segment-%03d.ts'), str(target/'master.m3u8')])
    (OUT/'controls.html').write_text('''<!doctype html><html lang="en"><meta charset="utf-8"><title>VisionStream control check</title>
<style>body{font:20px system-ui;margin:40px;background:#18202a;color:white}video{max-width:90%}</style>
<h1>Complete frame and controls</h1><p>Original CC0 calibration clip, approximately 32 seconds. Choose Screen and Mono in VisionStream, then Watch in VR. Check NORTH/SOUTH and all four corners, pause/resume, seeking, and Return to page.</p>
<video controls playsinline preload="metadata" width="600" src="controls-demo.mp4"></video></html>''')

def make_quality_demo():
    target = OUT/'quality'
    target.mkdir(parents=True, exist_ok=True)
    for name, width, height in [('low', 480, 240), ('high', 1440, 720)]:
        folder = target/name
        folder.mkdir(parents=True, exist_ok=True)
        run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(OUT/'vr180-sbs.mp4'),
             '-vf', f'scale={width}:{height}', '-c:v', 'libx264', '-preset', 'veryfast', '-crf', '20',
             '-g', '60', '-keyint_min', '60', '-sc_threshold', '0', '-c:a', 'aac', '-b:a', '64k',
             '-hls_time', '2', '-hls_playlist_type', 'vod', '-hls_flags', 'independent_segments',
             '-hls_segment_filename', str(folder/'segment-%03d.ts'), str(folder/'index.m3u8')])
    (target/'master.m3u8').write_text('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=300000,RESOLUTION=480x240,CODECS="avc1.64001f,mp4a.40.2"\nlow/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=4000000,RESOLUTION=1440x720,CODECS="avc1.640020,mp4a.40.2"\nhigh/index.m3u8?fixture=published%2Buri\n')
    (OUT/'quality.html').write_text('<!doctype html><title>CC0 VR180 SBS quality test</title><style>body{font:24px system-ui;background:#18202a;color:white}video{width:75%}</style><h1>CC0 VR180 quality calibration</h1><video controls autoplay muted loop playsinline data-projection="vr180" data-stereo="sbs" src="quality/master.m3u8"></video>')

def make_metadata_demos():
    import struct
    def box(kind, payload): return struct.pack('>I', len(payload)+8)+kind+payload
    def children(data):
        offset = 0
        while offset < len(data):
            length, kind = struct.unpack_from('>I4s',data,offset)
            if length < 8 or offset+length > len(data): raise ValueError('Unexpected generated MP4 box')
            yield kind, data[offset+8:offset+length]
            offset += length
    for target, source, stereo, width, height, crop, left in [
            ('opaque-a.mp4','vr180-sbs.mp4','left-right',1024,512,512,256),
            ('opaque-b.mp4','vr360-tb.mp4','top-bottom',1024,512,1024,0)]:
        xml = f'<rdf:SphericalVideo xmlns:rdf="urn:rdf" xmlns:s="http://ns.google.com/videos/1.0/spherical/"><s:Spherical>true</s:Spherical><s:Stitched>true</s:Stitched><s:ProjectionType>equirectangular</s:ProjectionType><s:StereoMode>{stereo}</s:StereoMode><s:FullPanoWidthPixels>{width}</s:FullPanoWidthPixels><s:FullPanoHeightPixels>{height}</s:FullPanoHeightPixels><s:CroppedAreaImageWidthPixels>{crop}</s:CroppedAreaImageWidthPixels><s:CroppedAreaImageHeightPixels>{height}</s:CroppedAreaImageHeightPixels><s:CroppedAreaLeftPixels>{left}</s:CroppedAreaLeftPixels></rdf:SphericalVideo>'.encode()
        atom = box(b'uuid',bytes.fromhex('ffcc8263f8554a938814587a02521fdd')+xml)
        original = (OUT/source).read_bytes()
        roots = list(children(original))
        old_end = sum(len(payload)+8 for kind,payload in roots[:next(i for i,item in enumerate(roots) if item[0]==b'moov')+1])
        def rewrite(data):
            result = b''
            for kind,payload in children(data):
                if kind in [b'moov',b'trak',b'mdia',b'minf',b'stbl']:
                    old = payload
                    payload = rewrite(payload)
                    if kind == b'trak':
                        media = next((v for k,v in children(old) if k==b'mdia'),b'')
                        handler = next((v for k,v in children(media) if k==b'hdlr'),b'')
                        if handler[8:12] == b'vide': payload += atom
                elif kind == b'stco':
                    values = bytearray(payload)
                    for i in range(struct.unpack_from('>I',values,4)[0]):
                        offset = struct.unpack_from('>I',values,8+i*4)[0]
                        if offset >= old_end: struct.pack_into('>I',values,8+i*4,offset+len(atom))
                    payload = bytes(values)
                result += box(kind,payload)
            return result
        (OUT/target).write_bytes(rewrite(original))

def make_4k_quality_demo():
    target = OUT/'quality-4k'
    target.mkdir(parents=True, exist_ok=True)
    ppm = target/'eye.ppm'
    image(ppm,1920,1920,'vr180','MONO',0)
    # A native-resolution original 4K grid, duplicated into two documented eyes.
    run(['ffmpeg','-hide_banner','-loglevel','error','-y','-loop','1','-framerate','30','-i',str(ppm),
         '-f','lavfi','-i','sine=frequency=440:sample_rate=48000:duration=8',
         '-filter_complex',"[0:v]drawbox=x=952:y=1000:w=16:h=16:c=lime:t=fill:enable='lt(mod(t,2),1)',split=2[l][r];[l][r]hstack=inputs=2[out]",
         '-map','[out]','-map','1:a','-c:v','libx264','-preset','veryfast','-crf','20','-level:v','5.1','-pix_fmt','yuv420p',
         '-g','60','-keyint_min','60','-sc_threshold','0','-c:a','aac','-b:a','64k','-t','8',
         '-hls_time','2','-hls_playlist_type','vod','-hls_flags','independent_segments',
         '-hls_segment_filename',str(target/'segment-%03d.ts'),str(target/'high.m3u8')])
    (target/'master.m3u8').write_text('#EXTM3U\n#EXT-X-VERSION:3\n#EXT-X-STREAM-INF:BANDWIDTH=300000,RESOLUTION=480x240,CODECS="avc1.64001f,mp4a.40.2"\n../quality/low/index.m3u8\n#EXT-X-STREAM-INF:BANDWIDTH=6000000,RESOLUTION=3840x1920,CODECS="avc1.640033,mp4a.40.2"\nhigh.m3u8\n')
    (OUT/'quality-4k.html').write_text('<!doctype html><title>CC0 native 4K calibration</title><style>body{background:#18202a;color:white;font:24px system-ui}video{width:75%}</style><h1>Original CC0 VR180 4K grid</h1><video autoplay muted loop playsinline controls data-projection="vr180" data-stereo="sbs" src="quality-4k/master.m3u8"></video>')

def make_context_sample():
    # Original CC0 rich texture with identical packed eyes; no filename cue or
    # spherical tags. Low-frequency texture remains after anti-aliased analysis;
    # pixel-scale noise averaged away into an ambiguous repeating test grid.
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-f', 'lavfi',
         '-i', 'testsrc2=size=64x64:rate=30:duration=8', '-f', 'lavfi',
         '-i', 'sine=frequency=440:sample_rate=48000:duration=8',
         '-filter_complex', '[0:v]noise=alls=100:allf=t+u:all_seed=42,scale=512:512:flags=neighbor,split=2[l][r];[l][r]hstack=inputs=2[out]',
         '-map', '[out]', '-map', '1:a', '-c:v', 'libx264', '-preset', 'veryfast',
         '-crf', '22', '-pix_fmt', 'yuv420p', '-c:a', 'aac', '-movflags', '+faststart',
         '-shortest', str(OUT/'context-sample.mp4')])
    hls = OUT/'unlabelled'; hls.mkdir(parents=True, exist_ok=True)
    run(['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-i', str(OUT/'context-sample.mp4'),
         '-c', 'copy', '-hls_time', '2', '-hls_playlist_type', 'vod',
         '-hls_segment_filename', str(hls/'segment-%03d.ts'), str(hls/'stream.m3u8')])

def make_disparity_samples():
    def texture(x,y):
        v=((x*73856093)&0xffffffff)^((y*19349663)&0xffffffff)
        return (((v^(v>>13))*1274126177)&0xffffffff)&255
    for horizontal,name,size in [(True,'disparity-a','1024:512'),(False,'disparity-b','1024:1024')]:
        w,h=128,64;ew,eh=(64,64) if horizontal else (128,32)
        values=[0]*(w*h)
        for y in range(eh):
            for x in range(ew):
                values[y*w+x]=texture(x,y)
                shift=9 if y<eh//2 else -10;sx,sy=x+shift,y+1
                other=(y+(0 if horizontal else eh))*w+x+(ew if horizontal else 0)
                values[other]=int(texture(sx,sy)*0.7+25.5) if 0<=sx<ew and sy<eh else 0
                if x>=ew*3//4:values[other]=texture(x+551,y+231)
        ppm=OUT/(name+'.ppm');ppm.write_bytes(b'P6\n128 64\n255\n'+bytes(c for v in values for c in (v,v,v)))
        target=OUT/(name+'.mp4')
        run(['ffmpeg','-hide_banner','-loglevel','error','-y','-loop','1','-framerate','30','-i',str(ppm),
             '-f','lavfi','-i','sine=frequency=440:sample_rate=48000:duration=8','-vf','scale='+size+':flags=neighbor',
             '-t','8','-c:v','libx264','-preset','veryfast','-crf','12','-pix_fmt','yuv420p','-c:a','aac','-movflags','+faststart',str(target)])
        folder=OUT/name;folder.mkdir(exist_ok=True)
        run(['ffmpeg','-hide_banner','-loglevel','error','-y','-i',str(target),'-c','copy','-hls_time','2','-hls_playlist_type','vod',
             '-hls_segment_filename',str(folder/'segment-%03d.ts'),str(folder/'stream.m3u8')])

if __name__ == '__main__': main()

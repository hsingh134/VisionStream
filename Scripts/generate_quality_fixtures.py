#!/usr/bin/env python3
"""Original CC0 video-quality patterns. No downloaded footage or extra Python packages."""
from pathlib import Path
import array, json, math, subprocess, tempfile
ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'Fixtures/generated/quality'

def run(args): subprocess.run(['ffmpeg','-hide_banner','-loglevel','error','-y',*args],check=True)
def metadata(path):
    data=json.loads(subprocess.check_output(['ffprobe','-v','error','-show_streams','-show_format','-of','json',str(path)],text=True))
    data.get('format',{}).pop('filename',None)
    stream=data['streams'][0]
    # FFmpeg 9 needs frame colour tags (setparams), not just encoder options.
    # Without them a colr box may contain "unspecified" despite the CLI flags.
    assert stream.get('color_primaries') in {'bt709','bt2020'}, 'Missing encoded colour primaries'
    assert stream.get('color_transfer') in {'bt709','smpte2084','arib-std-b67'}, 'Missing encoded transfer function'
    assert b'colr' in path.read_bytes(), 'Missing container colour information'
    return data
def yuv(path,kind,full=False):
    w,h=512,128
    if kind=='sdr': colors=[(0,0,0),(1,1,1),(1,0,0),(0,1,0),(0,0,1),(1,1,0),(0,1,1),(1,0,1)]
    else: colors=[(v,v,v) for v in [0,.001,.01,.1,.25,.5,.75,1]]
    ys=[];us=[];vs=[]
    for r,g,b in colors:
        Y=.2126*r+.7152*g+.0722*b;U=(b-Y)/1.8556;V=(r-Y)/1.5748
        if kind=='sdr': ys.append(round((0 if full else 16)+(255 if full else 219)*Y));us.append(max(0,min(255,round(128+(255 if full else 224)*U))));vs.append(max(0,min(255,round(128+(255 if full else 224)*V))))
        else:
            if kind=='pq':
                # Normalized luminance up to 1,000 nits; encoded using ST 2084.
                L=Y*.1;m1=2610/16384;m2=2523/32;c1=3424/4096;c2=2413/128;c3=2392/128
                e=((c1+c2*L**m1)/(1+c3*L**m1))**m2
            else:
                a=.17883277;b=1-4*a;c=.5-a*math.log(4*a)
                e=math.sqrt(3*Y) if Y<=1/12 else a*math.log(12*Y-b)+c
            ys.append(round(64+876*e));us.append(512);vs.append(512)
    planes=[]
    for values,width,height in [(ys,w,h),(us,w//2,h//2),(vs,w//2,h//2)]:
        row=[values[min(7,x*8//width)] for x in range(width)]
        if kind=='sdr':planes.append(bytes(row)*height)
        else:
            data=array.array('H',row*height)
            if __import__('sys').byteorder!='little':data.byteswap()
            planes.append(data.tobytes())
    path.write_bytes(b''.join(planes))
    return {'lumaCodes':ys,'reference':colors,'range':'full' if full else 'limited'}

def charts(path):
    w,h=4096,2048;eye=w//2
    from generate_fixtures import GLYPHS
    rows=[]
    for y in range(h):
        row=bytearray()
        for x in range(eye):
            if y<h//4: v=255 if ((x//max(1,1+(y//64)))%2) else 0;c=(v,v,v)
            elif y<h//2: v=255 if ((x+y)%2) else 0;c=(v,v,v)
            elif y<3*h//4: v=round(255*x/(eye-1));c=(v,v,v)
            else: c=(round(255*x/(eye-1)),round(255*(y-3*h//4)/(h//4-1)),128)
            if x%(eye//12)<2 or y%(h//12)<2:c=(0,220,255)
            row.extend(c)
        # Shared fine structure with a small, known horizontal stereo disparity.
        shift=3*3;right=row[shift:]+row[:shift]
        rows.append(row+right)
    for e,label in enumerate(['LEFT EYE FRONT','RIGHT EYE FRONT']):
        for scale,cy in [(2,h//2+20),(4,h//2+60),(8,h//2+140)]:
            start=e*eye+(eye-len(label)*6*scale)//2
            for j,ch in enumerate(label):
                glyph=GLYPHS.get(ch,['00000']*7)
                for gy,bits in enumerate(glyph):
                    for gx,bit in enumerate(bits):
                        if bit=='1':
                            for sy in range(scale):
                                for sx in range(scale):
                                    x=start+j*6*scale+gx*scale+sx;y=cy+gy*scale+sy
                                    rows[y][x*3:x*3+3]=b'\xff\xff\xff'
    path.write_bytes(f'P6\n{w} {h}\n255\n'.encode()+b''.join(rows))

def main():
    OUT.mkdir(parents=True,exist_ok=True);manifest=[]
    with tempfile.TemporaryDirectory(prefix='visionstream-quality-') as temp:
        tmp=Path(temp)
        for name,kind,full in [('709-limited','sdr',False),('709-full','sdr',True),('2020-pq','pq',False),('2020-hlg','hlg',False)]:
            target=OUT/(name+'.mp4');ref=yuv(tmp/'raw.yuv',kind,full)
            pix='yuv420p' if kind=='sdr' else 'yuv420p10le'
            args=['-stream_loop','-1','-f','rawvideo','-pix_fmt',pix,'-s','512x128','-r','30','-i',str(tmp/'raw.yuv'),'-t','2','-an']
            if kind=='sdr':args+=['-c:v','libx264','-preset','fast','-qp','18','-profile:v','high']
            else:args+=['-c:v','libx265','-preset','fast','-x265-params','lossless=1:pools=1:frame-threads=1:log-level=error','-tag:v','hvc1']
            args+=['-vf','setparams=color_primaries='+('bt709' if kind=='sdr' else 'bt2020')+':color_trc='+('bt709' if kind=='sdr' else ('smpte2084' if kind=='pq' else 'arib-std-b67'))+':colorspace='+('bt709' if kind=='sdr' else 'bt2020nc')+':range='+('full' if full else 'limited'),'-color_primaries','bt709' if kind=='sdr' else 'bt2020','-color_trc','bt709' if kind=='sdr' else ('smpte2084' if kind=='pq' else 'arib-std-b67'),'-colorspace','bt709' if kind=='sdr' else 'bt2020nc','-color_range','pc' if full else 'tv','-movflags','+faststart+write_colr',str(target)]
            run(args);manifest.append({'file':target.name,'reference':ref,'probe':metadata(target)})
        chart=tmp/'chart.ppm';charts(chart)
        for name,crf in [('vr180-sbs-chart',14),('vr180-sbs-compressed',40)]:
            target=OUT/(name+'.mp4')
            run(['-loop','1','-framerate','30','-i',str(chart),'-vf',"drawbox=x=1950:y=1800:w=64:h=64:c=lime:t=fill:enable='lt(mod(t,1),0.5)',setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=limited",'-t','8','-an','-c:v','libx264','-preset','fast','-crf',str(crf),'-pix_fmt','yuv420p','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-color_range','tv','-movflags','+faststart+write_colr',str(target)])
            manifest.append({'file':target.name,'probe':metadata(target)})
        target=OUT/'vr360-mono-8k.mp4'
        run(['-f','lavfi','-i','testsrc2=size=8192x4096:rate=30:duration=0.6','-an','-vf','setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=limited','-c:v','libx265','-preset','ultrafast','-crf','18','-x265-params','pools=2:frame-threads=1:log-level=error','-pix_fmt','yuv420p10le','-tag:v','hvc1','-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-color_range','tv','-movflags','+faststart+write_colr',str(target)])
        manifest.append({'file':target.name,'probe':metadata(target)})
        # Full-range Main10 neutral ramp: a native decode test can count actual
        # distinct levels, rather than infer precision from a float pixel format.
        ramp=tmp/'ramp.yuv'
        data=array.array('H',list(range(1024))*128+[512]*(1024*128//2))
        if __import__('sys').byteorder!='little':data.byteswap()
        ramp.write_bytes(data.tobytes());target=OUT/'709-main10-ramp.mp4'
        run(['-stream_loop','-1','-f','rawvideo','-pix_fmt','yuv420p10le','-s','1024x128','-r','30','-i',str(ramp),'-t','2','-an',
             '-vf','setparams=color_primaries=bt709:color_trc=bt709:colorspace=bt709:range=full',
             '-c:v','libx265','-preset','fast','-x265-params','lossless=1:pools=1:frame-threads=1:log-level=error','-tag:v','hvc1',
             '-color_primaries','bt709','-color_trc','bt709','-colorspace','bt709','-color_range','pc','-movflags','+faststart+write_colr',str(target)])
        manifest.append({'file':target.name,'reference':{'lumaCodes':'0 through 1023 inclusive, neutral full-range Main10'},'probe':metadata(target)})
    (OUT/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    (OUT/'LICENSE.txt').write_text('Original VisionStream test patterns, released under CC0 1.0 Universal.\nhttps://creativecommons.org/publicdomain/zero/1.0/\n')
    (ROOT/'Fixtures/generated/quality-audit.html').write_text('<!doctype html><title>Original CC0 quality chart</title><video controls autoplay muted playsinline loop data-projection="vr180" data-stereo="sbs" preload="metadata" src="quality/vr180-sbs-chart.mp4" style="width:95%"></video><p>Original CC0 resolution, text, gradients and stereo alignment chart. VR180 side by side.</p>')
    print(json.dumps({'generated':len(manifest),'licence':'CC0-1.0','sourceFootageDownloaded':False}))
if __name__=='__main__':main()

#!/usr/bin/env python3
"""Build the local-file-only LGPL FFmpeg remux runtime for visionOS; no network/GPL components."""
import argparse,hashlib,json,os,plistlib,shutil,subprocess,tarfile,tempfile
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
VERSION='9.0.2'
SHA='8c3850283eb25fa026482078a04051e0be17347b09ef81a0849bec15a96e002e'
def main():
 p=argparse.ArgumentParser();p.add_argument('--platform',choices=['xros','xrsimulator','all'],default='all');p.add_argument('--jobs',type=int,default=6);args=p.parse_args()
 archive=ROOT/'Vendor/FFmpeg'/f'ffmpeg-{VERSION}.tar.xz'
 if hashlib.sha256(archive.read_bytes()).hexdigest()!=SHA:raise SystemExit('FFmpeg source checksum mismatch')
 task_root=Path(tempfile.gettempdir())/'visionstream-media-v9';task_root.mkdir(exist_ok=True)
 source=task_root/f'ffmpeg-{VERSION}'
 if not source.exists():
  with tarfile.open(archive) as t:t.extractall(task_root,filter='data')
 env=dict(os.environ,DEVELOPER_DIR='/Applications/Xcode.app/Contents/Developer')
 def command(parts,**kwargs):subprocess.run([str(x) for x in parts],env=env,check=True,**kwargs)
 def capture(parts):return subprocess.check_output(parts,env=env,text=True).strip()
 cc=capture(['xcrun','--find','clang'])
 platforms=['xros','xrsimulator'] if args.platform=='all' else [args.platform]
 for platform in platforms:
  sdk=capture(['xcrun','--sdk',platform,'--show-sdk-path'])
  target='arm64-apple-xros26.0'+('-simulator' if platform=='xrsimulator' else '')
  build=task_root/platform;build.mkdir(exist_ok=True);prefix=build/'install'
  flags=f'-target {target} -isysroot {sdk}'
  config=[source/'configure',f'--prefix={prefix}','--target-os=darwin','--arch=aarch64','--enable-cross-compile',f'--cc={cc}',f'--sysroot={sdk}',f'--extra-cflags={flags}',f'--extra-ldflags={flags}',
   '--disable-everything','--disable-autodetect','--disable-programs','--disable-doc','--disable-debug','--disable-network','--disable-shared','--enable-static','--enable-pic','--enable-small','--disable-gpl','--disable-nonfree',
   '--disable-avdevice','--disable-avfilter','--disable-swscale','--disable-swresample','--enable-avformat','--enable-avcodec','--enable-avutil','--enable-protocol=file','--enable-demuxer=mpegts','--enable-muxer=mp4',
   '--enable-parser=h264,hevc,aac','--enable-decoder=h264,hevc,aac','--enable-bsf=aac_adtstoasc,extract_extradata']
  with (build/'configure.log').open('w') as log:command(config,cwd=build,stdout=log,stderr=subprocess.STDOUT)
  with (build/'make.log').open('w') as log:command(['make',f'-j{max(1,min(12,args.jobs))}'],cwd=build,stdout=log,stderr=subprocess.STDOUT);command(['make','install'],cwd=build,stdout=log,stderr=subprocess.STDOUT)
  framework=ROOT/'DerivedData/MediaRuntime'/platform/'VisionStreamMedia.framework';(framework/'Headers').mkdir(parents=True,exist_ok=True);(framework/'Modules').mkdir(exist_ok=True)
  shutil.copy2(ROOT/'Vendor/MediaSource/MediaRemux.h',framework/'Headers/MediaRemux.h')
  (framework/'Modules/module.modulemap').write_text('framework module VisionStreamMedia { umbrella header "MediaRemux.h" export * }\n')
  info={'CFBundleIdentifier':'personal.visionstream.media','CFBundleName':'VisionStreamMedia','CFBundleExecutable':'VisionStreamMedia','CFBundlePackageType':'FMWK','CFBundleVersion':'1','CFBundleShortVersionString':VERSION,'MinimumOSVersion':'26.0','CFBundleSupportedPlatforms':['XRSimulator' if platform=='xrsimulator' else 'XROS']}
  (framework/'Info.plist').write_bytes(plistlib.dumps(info))
  command([cc,'-target',target,'-isysroot',sdk,'-O2','-fPIC','-dynamiclib','-I'+str(prefix/'include'),ROOT/'Vendor/MediaSource/MediaRemux.c',
   '-Wl,-install_name,@rpath/VisionStreamMedia.framework/VisionStreamMedia','-Wl,-exported_symbol,_vs_media_*',
   '-Wl,-force_load,'+str(prefix/'lib/libavformat.a'),'-Wl,-force_load,'+str(prefix/'lib/libavcodec.a'),'-Wl,-force_load,'+str(prefix/'lib/libavutil.a'),'-lm','-o',framework/'VisionStreamMedia'])
  command(['codesign','--force','--sign','-',framework],stdout=subprocess.DEVNULL)
  print(platform,'remux framework built',flush=True)
 destination=ROOT/'Vendor/VisionStreamMedia.xcframework'
 if args.platform=='all':
  if destination.exists():shutil.rmtree(destination)
  command(['xcodebuild','-create-xcframework','-framework',ROOT/'DerivedData/MediaRuntime/xros/VisionStreamMedia.framework','-framework',ROOT/'DerivedData/MediaRuntime/xrsimulator/VisionStreamMedia.framework','-output',destination],stdout=subprocess.DEVNULL)
 shutil.copy2(source/'COPYING.LGPLv2.1',ROOT/'Licenses/FFmpeg-LGPL-2.1.txt')
 (ROOT/'Vendor/FFmpeg/build-manifest.json').write_text(json.dumps({'version':VERSION,'sourceSHA256':SHA,'license':'LGPL-2.1-or-later','GPL':False,'nonfree':False,'network':False,'runtime':'file-only MPEG-TS to MP4, no re-encoding','platforms':platforms},indent=2)+'\n')
if __name__=='__main__':main()

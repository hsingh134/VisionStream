#!/usr/bin/env python3
"""Prepare local submission materials. No account access, uploads or publication."""
import argparse,html,json,plistlib,re,shutil
from pathlib import Path
from urllib.parse import urlsplit
ROOT=Path(__file__).resolve().parents[1]

def valid_url(value):
    try:
        u=urlsplit(value)
        return u.scheme=='https' and u.hostname and '.' in u.hostname and not u.username and not u.password and not u.hostname.endswith(('.invalid','.example','.localhost','.test')) and u.hostname not in ['example.com','example.org','example.net','localhost']
    except ValueError:return False

def configuration(path):
    raw=json.loads(path.read_text()) if path.exists() else {}
    fields=['publisherName','supportEmail','supportURL','privacyURL','appleTeamID','appBundleID','encryptionComplianceCode']
    values={key:str(raw.get(key,'')).strip() for key in fields}
    for key,value in values.items():
        if len(value)>500 or any(c in value for c in ['\n','\r','\x00','$','/*','*/']):raise ValueError('Unsupported configuration value: '+key)
    if values['supportEmail'] and re.fullmatch(r'[^\s@<>]+@[^\s@<>]+\.[^\s@<>]+',values['supportEmail']) is None:raise ValueError('Invalid support email')
    for key in ['supportURL','privacyURL']:
        if values[key] and not valid_url(values[key]):raise ValueError('A real public HTTPS address is required for '+key)
    if values['appleTeamID'] and re.fullmatch(r'[A-Z0-9]{10}',values['appleTeamID']) is None:raise ValueError('Invalid Apple team identifier')
    if values['appBundleID'] and re.fullmatch(r'[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+){2,}',values['appBundleID']) is None:raise ValueError('Invalid reverse-domain app identifier')
    values['usesNonExemptEncryption']=raw.get('usesNonExemptEncryption')
    if values['usesNonExemptEncryption'] is not None and type(values['usesNonExemptEncryption']) is not bool:raise ValueError('Encryption declaration must be true, false or null pending owner classification')
    values['sourceAuthorizations']=raw.get('sourceAuthorizations',[])
    if not isinstance(values['sourceAuthorizations'],list) or any(not isinstance(item,str) for item in values['sourceAuthorizations']):raise ValueError('Source authorizations must be a list of local document paths for owner review')
    return values

def document(title,body,contact):
    return '<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>'+html.escape(title)+'</title><style>body{font:18px/1.65 system-ui;max-width:820px;margin:48px auto;padding:0 24px;color:#122b3a;background:#f6fafb}a{color:#005b72}h1,h2{line-height:1.2}.notice{background:#fff3d9;padding:16px;border-radius:12px}footer{border-top:1px solid #cbdadf;margin-top:36px;padding-top:20px}</style><h1>'+html.escape(title)+'</h1>'+body+'<footer>'+contact+'<p><a href="privacy.html">Privacy</a> · <a href="support.html">Support</a></p></footer></html>'

def main():
    p=argparse.ArgumentParser();p.add_argument('--config',type=Path,default=ROOT/'Config/Publication.json');p.add_argument('--output',type=Path,default=ROOT/'Submission/Prepared');p.add_argument('--write-build-config',action='store_true');args=p.parse_args()
    cfg=configuration(args.config);out=args.output;out.mkdir(parents=True,exist_ok=True)
    site=out/'site';site.mkdir(exist_ok=True)
    missing=[key for key in ['publisherName','supportEmail','supportURL','privacyURL','appleTeamID','appBundleID'] if not cfg[key]]
    if cfg['usesNonExemptEncryption'] is None:missing.append('encryption classification')
    e=html.escape
    contact='<p>'+e(cfg['publisherName'])+'</p>' if cfg['publisherName'] else '<p class="notice">Development draft: publisher details are pending. Do not publish or submit this draft.</p>'
    if cfg['supportEmail']:contact+='<p>Contact: <a href="mailto:'+e(cfg['supportEmail'],quote=True)+'">'+e(cfg['supportEmail'])+'</a></p>'
    policy=(ROOT/'VisionStream/Resources/PrivacyPolicy.txt').read_text()
    paragraphs=policy.split('\n\n')[1:]
    policy_body='<p>Updated 26 October 2026</p>'+''.join('<p>'+e(text).replace('\n','<br>')+'</p>' for text in paragraphs)
    (site/'privacy.html').write_text(document('VisionStream privacy policy',policy_body,contact))
    support='''<p>VisionStream is a general-purpose web browser and immersive video player for Apple Vision Pro running visionOS 26 or later.</p><h2>Watch a video</h2><p>Open a website and press its Play button. A recognised interaction opens compatible video in the native VR viewer automatically. Autoplay alone stays in the webpage. Turn automatic opening off in Browser settings if preferred. If a Play control is not recognised, use Watch in VR on the video bar. Browser options always provides source finding and Playback details. Automatic format uses metadata and image matches; use Video format to correct a doubled or distorted view. Projection and eye layout are separate controls.</p><h2>Saving and the queue</h2><p>Save only media the source permits you to download. Compatible MP4 and unprotected on-demand HLS can be saved. While one saves, Add to queue adds another; Downloads shows waiting items and removal controls. Up to 20 videos can wait, and one saves at a time. Keep the app open. Waiting links clear on quit and may expire. Some websites, codecs and HLS packaging forms are unsupported.</p><h2>Playback or save failed</h2><p>Check that the webpage itself plays, refresh an expired source and complete normal website access steps yourself. Do not send passwords, cookies or signed media links to support. Playback details can produce a technical report; inspect it before sharing because hosts and activity can be sensitive.</p><h2>Privacy and storage</h2><p>Browser settings controls detailed history and diagnostic deletion. Clear website data signs out of websites. Delete bookmarks and saved copies in their respective screens. Diagnostic deletion keeps saved videos. See the privacy policy for retention and report sharing.</p>'''
    (site/'support.html').write_text(document('VisionStream support',support,contact))
    (site/'index.html').write_text(document('VisionStream','<p>A web browser and immersive video player for Apple Vision Pro.</p><p><a href="support.html">Help and support</a></p><p><a href="privacy.html">Privacy policy</a></p>',contact))
    (site/'.nojekyll').write_text('')
    fixtures=ROOT/'Fixtures/generated'
    review_media=[]
    if fixtures.is_dir():
        media=site/'review-media';media.mkdir(exist_ok=True)
        for filename in ['vr180-sbs.mp4','vr360-mono.mp4','LICENSE.txt']:
            source=fixtures/filename
            if source.is_file() and not source.is_symlink():shutil.copyfile(source,media/filename)
        for filename,projection,layout in [('vr180-sbs.mp4','vr180','sbs'),('vr360-mono.mp4','vr360','mono')]:
            if (media/filename).is_file():
                review_media.append(filename)
        review='<p>Original public-domain CC0 calibration patterns. Streaming and saving these clips are explicitly permitted. They test eye assignment/projection; they do not establish real-world depth comfort.</p>'
        for filename in review_media:
            projection,layout=('vr180','sbs') if filename=='vr180-sbs.mp4' else ('vr360','mono')
            review+='<h2>'+e(projection.upper()+' / '+layout.upper())+'</h2><video controls playsinline preload="metadata" width="640" style="max-width:100%" data-projection="'+projection+'" data-stereo="'+layout+'" src="review-media/'+filename+'"></video><p><a download href="review-media/'+filename+'">Download permitted MP4</a></p>'
        review+='<p><a href="review-media/LICENSE.txt">CC0 dedication</a></p>'
        (site/'calibration.html').write_text(document('VisionStream calibration',review,contact))
    metadata={'name':'VisionStream','subtitle':'Immersive video web browser','description':'Browse websites and open compatible videos in the native viewer when you press Play. Watch immersive VR180 or VR360 videos with automatic format detection. VisionStream supports monoscopic, side-by-side and top-bottom video with adjustable format, quality and playback controls.\n\nSave compatible, authorized videos for offline viewing and add up to 20 waiting saves. Import your own MP4 files and export saved MP4 copies.\n\nCompatibility depends on the website, streaming format, access requirements and video codec. Automatic geometry and eye layout are estimates and can be changed manually. VisionStream does not bypass DRM, accounts, payment or website restrictions. Some streams cannot be opened or saved; keep the app open for foreground saving.','keywords':'VR,video,browser,180,360,stereo,immersive,player','privacyPolicyURL':cfg['privacyURL'],'supportURL':cfg['supportURL'],'reviewContactEmail':cfg['supportEmail'],'ageRatingAnswersToVerify':{'unrestrictedWebAccess':True,'curatedPornographicContent':False,'note':'Describe the actual browser and all bundled content; App Store Connect determines the final rating. Do not claim a rating not assigned by Apple.'},'reviewNotes':'General-purpose WebKit browser with native immersive video playback, source detection/discovery, native saving, an in-memory FIFO save queue and local MP4 import/export. All features are the same for reviewers and customers. The embedded Python/yt-dlp source finder is bundled, does not install updates or executable helpers, and has no remote plugins. Clear supported HLS can be saved via native transport and a local-only FFmpeg packet remux library. Explicit source authorization for third-party media saving must be documented before submission; no blanket authorization is asserted. No app account or purchase is required. Use the supplied original CC0 calibration media for deterministic review; see Review-guide.md.','ownerFieldsPending':missing}
    (out/'metadata.json').write_text(json.dumps(metadata,indent=2)+'\n')
    options={'method':'app-store-connect','signingStyle':'automatic','uploadSymbols':True,'stripSwiftSymbols':True,'manageAppVersionAndBuildNumber':False,'destination':'export'}
    if cfg['appleTeamID']:options['teamID']=cfg['appleTeamID']
    (out/'ExportOptions.plist').write_bytes(plistlib.dumps(options))
    if args.write_build_config:
        # Xcode treats // as a comment even inside common URL assignments.
        def xc(value):return value.replace('//','/$()/')
        publication='\n'.join(key+' = '+xc(cfg[field]) for key,field in [('PUBLICATION_PUBLISHER_NAME','publisherName'),('PUBLICATION_SUPPORT_EMAIL','supportEmail'),('PUBLICATION_SUPPORT_URL','supportURL'),('PUBLICATION_PRIVACY_URL','privacyURL')])+'\n'
        (ROOT/'Config/Publication.xcconfig').write_text(publication)
        store=''
        if cfg['appleTeamID']:store+='DEVELOPMENT_TEAM = '+cfg['appleTeamID']+'\n'
        if cfg['appBundleID']:store+='PRODUCT_BUNDLE_IDENTIFIER = '+cfg['appBundleID']+'\n'
        generated=ROOT/'Config/Generated';generated.mkdir(parents=True,exist_ok=True)
        info=plistlib.loads((ROOT/'VisionStream/Info.plist').read_bytes())
        for key,field in [('VisionStreamPublisherName','publisherName'),('VisionStreamSupportEmail','supportEmail'),('VisionStreamSupportURL','supportURL'),('VisionStreamPrivacyPolicyURL','privacyURL')]:info[key]=cfg[field]
        if cfg['usesNonExemptEncryption'] is not None:info['ITSAppUsesNonExemptEncryption']=cfg['usesNonExemptEncryption']
        if cfg['encryptionComplianceCode']:info['ITSEncryptionExportComplianceCode']=cfg['encryptionComplianceCode']
        (generated/'AppStoreInfo.plist').write_bytes(plistlib.dumps(info))
        store+='INFOPLIST_FILE = Config/Generated/AppStoreInfo.plist\n'
        (ROOT/'Config/AppStoreLocal.xcconfig').write_text(store)
    (out/'preparation.json').write_text(json.dumps({'status':'owner-details-pending' if missing else 'prepared-not-submitted','ownerFieldsPending':missing,'published':False,'uploaded':False,'sourceAuthorizationDocumentCount':len(cfg['sourceAuthorizations']),'originalCC0ReviewMedia':review_media},indent=2)+'\n')
    print(json.dumps({'prepared':str(out),'ownerFieldsPending':missing,'published':False,'uploaded':False}))
if __name__=='__main__':main()

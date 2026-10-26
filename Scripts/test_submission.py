#!/usr/bin/env python3
"""Local submission regression checks; no Apple account or network required."""
import json,plistlib,subprocess,sys,tempfile,unittest
from pathlib import Path
import prepare_submission as prepare

class SubmissionTests(unittest.TestCase):
    def test_rejects_reserved_urls_and_build_setting_injection(self):
        for url in ['http://publisher.com/privacy','https://user:password@publisher.com','https://example.com','https://owner.test/privacy','https://owner.invalid']:
            self.assertFalse(prepare.valid_url(url),url)
        with tempfile.TemporaryDirectory() as temp:
            path=Path(temp)/'config.json'
            for value in ['Bad\nOTHER = YES','$(OTHER)','Bad/*comment*/']:
                path.write_text(json.dumps({'publisherName':value}))
                with self.assertRaises(ValueError):prepare.configuration(path)
    def test_missing_encryption_is_not_guessed(self):
        with tempfile.TemporaryDirectory() as temp:
            cfg=prepare.configuration(Path(temp)/'absent.json')
            self.assertIsNone(cfg['usesNonExemptEncryption']);self.assertEqual(cfg['appleTeamID'],'')
    def test_prepared_metadata_and_html_are_safe_local_drafts(self):
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)/'prepared';cfg=Path(temp)/'config.json'
            cfg.write_text(json.dumps({'publisherName':'A & B <Studio>','supportEmail':'help@studio.company'}))
            subprocess.run([sys.executable,str(Path(__file__).with_name('prepare_submission.py')),'--config',str(cfg),'--output',str(out)],check=True,capture_output=True)
            meta=json.loads((out/'metadata.json').read_text())
            self.assertLessEqual(len(meta['subtitle']),30);self.assertLessEqual(len(meta['keywords']),100)
            policy=(out/'site/privacy.html').read_text()
            self.assertIn('A &amp; B &lt;Studio&gt;',policy);self.assertIn('Updated 26 October 2026',policy)
            self.assertIn('appleTeamID',meta['ownerFieldsPending'])
            media=out/'site/review-media'
            if media.exists():
                self.assertEqual(sorted(x.name for x in media.iterdir()),['LICENSE.txt','vr180-sbs.mp4','vr360-mono.mp4'])
                self.assertEqual((media/'vr180-sbs.mp4').read_bytes(),(prepare.ROOT/'Fixtures/generated/vr180-sbs.mp4').read_bytes())
                self.assertIn('data-stereo="sbs"',(out/'site/calibration.html').read_text())
            options=plistlib.loads((out/'ExportOptions.plist').read_bytes())
            self.assertEqual(options['destination'],'export');self.assertNotIn('teamID',options)
    def test_generated_archive_plist_carries_explicit_encryption_and_contact_fields(self):
        original_root,original_argv=prepare.ROOT,sys.argv
        try:
            with tempfile.TemporaryDirectory() as temp:
                root=Path(temp);(root/'Config').mkdir();(root/'VisionStream/Resources').mkdir(parents=True)
                (root/'VisionStream/Info.plist').write_bytes(plistlib.dumps({'CFBundleVersion':'$(CURRENT_PROJECT_VERSION)'}))
                (root/'VisionStream/Resources/PrivacyPolicy.txt').write_text('Policy\nUpdated 26 October 2026\n\nText')
                cfg=root/'Config/Publication.json';cfg.write_text(json.dumps({'publisherName':'Owner','usesNonExemptEncryption':True,'encryptionComplianceCode':'CLASSIFIED-CODE'}))
                prepare.ROOT=root;sys.argv=['prepare_submission.py','--write-build-config']
                prepare.main()
                info=plistlib.loads((root/'Config/Generated/AppStoreInfo.plist').read_bytes())
                self.assertIs(info['ITSAppUsesNonExemptEncryption'],True);self.assertEqual(info['ITSEncryptionExportComplianceCode'],'CLASSIFIED-CODE')
                self.assertEqual(info['VisionStreamPublisherName'],'Owner');self.assertEqual(info['CFBundleVersion'],'$(CURRENT_PROJECT_VERSION)')
                cfg.write_text('{}');prepare.main()
                info=plistlib.loads((root/'Config/Generated/AppStoreInfo.plist').read_bytes())
                self.assertNotIn('ITSAppUsesNonExemptEncryption',info);self.assertNotIn('ITSEncryptionExportComplianceCode',info)
        finally:prepare.ROOT=original_root;sys.argv=original_argv
if __name__=='__main__':unittest.main()

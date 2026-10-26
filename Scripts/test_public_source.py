import tempfile,unittest
from pathlib import Path
from package_public_source import collect
class PublicSourceTests(unittest.TestCase):
    def test_only_source_and_public_config_are_collected(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp)
            allowed=['LICENSE','README.md','Config/Base.xcconfig','Config/Local.xcconfig.example','Tests/Case.swift','VisionStream/App.swift','Submission/README.md']
            denied=['TestResults/report.json','LocalMedia/private.mp4','DerivedData/debug.txt','Config/Local.xcconfig','Config/Publication.json','Config/Generated/AppStoreInfo.plist','Submission/Prepared/site/privacy.html','Fixtures/generated/test.mp4','Tests/Run.xcresult/Info.plist','VisionStream/private.p12','VisionStream/private.key','VisionStream/private.p8','VisionStream/__pycache__/cache.pyc','VisionStream.xcodeproj/xcuserdata/user/state.xcuserstate']
            for name in allowed+denied:
                file=root/name;file.parent.mkdir(parents=True,exist_ok=True);file.write_text('owned test data')
            self.assertEqual({str(p.relative_to(root)) for p in collect(root)},set(allowed))
    def test_linked_files_and_directories_are_not_exported(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);(root/'VisionStream').mkdir();(root/'outside').mkdir();(root/'outside/private.swift').write_text('keep private')
            (root/'VisionStream/linked.swift').symlink_to(root/'outside/private.swift')
            (root/'VisionStream/link').symlink_to(root/'outside',target_is_directory=True)
            self.assertEqual(collect(root),[])
if __name__=='__main__':unittest.main()

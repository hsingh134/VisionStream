import importlib.util
import json
import sys
from pathlib import Path
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "Vendor/ExtractorPackages"))
spec = importlib.util.spec_from_file_location("resolver", ROOT / "VisionStream/Resources/ExtractorPython/visionstream_resolver.py")
resolver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(resolver)


def media(**changes):
    return {"url": "https://cdn.example/video.mp4", "ext": "mp4", "protocol": "https",
            "vcodec": "avc1", "acodec": "mp4a", "width": 2880, "height": 1440, **changes}


class ResolverTests(unittest.TestCase):
    def test_url_validation(self):
        for address in ["file:///tmp/video.mp4", "http://example.com/v.mp4", "https://user:pass@example.com/v.mp4", "https://example.com:invalid/v.mp4", "blob:https://example.com/a"]:
            self.assertFalse(resolver.secure_url(address))
        self.assertTrue(resolver.secure_url("https://example.com/v.mp4?signature=a"))

    def test_mp4_and_hls_are_candidates_without_geometry_guesses(self):
        result = resolver.summarize({"formats": [media(), media(url="https://cdn.example/master.m3u8", protocol="m3u8_native", ext="mp4")]})
        self.assertEqual(result["status"], "ok")
        self.assertEqual(len(result["streams"]), 2)
        self.assertEqual(result["streams"][1]["mimeType"], "application/vnd.apple.mpegurl")
        self.assertTrue(all(s["unavailableReason"] == "" for s in result["streams"]))
        self.assertNotIn("projection", result["streams"][0])

    def test_mesh_declaration_also_blocks_unlabelled_hls_variants(self):
        result = resolver.summarize({"formats": [media(format_note="1440s, mesh"), media(url="https://cdn.example/v.m3u8", protocol="m3u8_native")]})
        self.assertTrue(all(s["unavailableReason"] == "projection" for s in result["streams"]))

    def test_drm_and_playlists_are_not_resolved(self):
        self.assertEqual(resolver.summarize({"has_drm": True, "formats": [media()]})["status"], "protected")
        self.assertEqual(resolver.summarize({"_type": "playlist"})["status"], "individual_video_required")

    def test_header_and_audio_requirements_are_explicit(self):
        self.assertEqual(resolver.summarize(media(acodec="none"))["streams"][0]["unavailableReason"], "separate_audio")
        for name in ["Cookie", "AUTHORIZATION"]:
            result = resolver.summarize({"http_headers": {name: "private"}, "formats": [media()]})
            self.assertEqual(result["streams"][0]["unavailableReason"], "required_headers")
            self.assertNotIn("private", json.dumps(result))

    def test_origin_and_referer_are_advisory_without_exporting_values(self):
        for protocol, extension in [("https", "mp4"), ("m3u8_native", "mp4")]:
            for at_format in [False, True]:
                headers = {"ORIGIN": "https://private.example", "referer": "https://private.example/?secret=token"}
                entry = media(protocol=protocol, ext=extension)
                info = {"formats": [entry]}
                (entry if at_format else info)["http_headers"] = headers
                result = resolver.summarize(info)
                self.assertEqual(result["streams"][0]["unavailableReason"], "")
                self.assertEqual(result["streams"][0]["advisory"], "request_context")
                self.assertNotIn("private.example", json.dumps(result))
                self.assertNotIn("secret", json.dumps(result))
        mixed = resolver.summarize(media(http_headers={"Origin": "private", "Cookie": "private"}))
        self.assertEqual(mixed["streams"][0]["unavailableReason"], "required_headers")
        protected = resolver.summarize(media(has_drm=True, http_headers={"Referer": "private"}))
        self.assertEqual(protected["status"], "protected")

    def test_formats_are_bounded_deduplicated_and_sorted(self):
        formats = [media(url=f"https://cdn.example/{i}.mp4", width=i, height=i) for i in range(70)]
        result = resolver.summarize({"formats": formats + [formats[-1]]})
        self.assertEqual(len(result["streams"]), 32)
        self.assertEqual(result["streams"][0]["width"], 69)
        self.assertEqual(len({s["source"] for s in result["streams"]}), 32)

    def test_shared_parent_keeps_hls_mime_even_if_seen_as_mp4_first(self):
        parent = "https://cdn.example/signed-parent"
        formats = [media(url=parent), media(url="https://cdn.example/child.m3u8", protocol="m3u8_native", manifest_url=parent)]
        for order in [formats, list(reversed(formats))]:
            result = resolver.summarize({"formats": order})
            automatic = next(s for s in result["streams"] if s["adaptive"])
            self.assertEqual(automatic["source"], parent)
            self.assertEqual(automatic["mimeType"], "application/vnd.apple.mpegurl")
            self.assertEqual((automatic["width"], automatic["height"]), (0, 0))

    def test_boolean_dimensions_do_not_break_the_swift_integer_contract(self):
        stream = resolver.summarize(media(width=True, height=False))["streams"][0]
        self.assertIs(type(stream["width"]), int)
        self.assertIs(type(stream["height"]), int)
        self.assertEqual((stream["width"], stream["height"]), (0, 0))

    def test_known_heights_sort_high_quality_first_even_without_widths(self):
        result = resolver.summarize({"formats": [media(url=f"https://cdn.example/{height}.mp4", width=0, height=height)
                                                for height in [240, 480, 720, 1080, 1440]]})
        self.assertEqual([s["height"] for s in result["streams"]], [1440, 1080, 720, 480, 240])
        self.assertTrue(all(s["width"] == 0 for s in result["streams"]))

    def test_private_exception_text_is_not_returned(self):
        with patch.dict("sys.modules", {"yt_dlp": None}):
            result = json.loads(resolver.resolve("https://example.com/video"))
        self.assertEqual(result, {"status": "unavailable", "streams": []})

    def test_published_parent_playlist_is_offered_once_without_url_rewriting(self):
        from yt_dlp import YoutubeDL
        from yt_dlp.extractor.common import InfoExtractor
        parent = "https://cdn.example/signed/master.m3u8?signature=original"
        playlist = '#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=400000,RESOLUTION=1024x512,CODECS="avc1.42c01e,mp4a.40.2"\nlow.m3u8?signature=child\n#EXT-X-STREAM-INF:BANDWIDTH=800000,RESOLUTION=2048x1024,CODECS="avc1.42c01e,mp4a.40.2"\nhigh.m3u8\n'
        with YoutubeDL({"quiet": True, "no_warnings": True, "logger": resolver.SilentLogger()}) as downloader:
            formats, _ = InfoExtractor(downloader)._parse_m3u8_formats_and_subtitles(playlist, parent, "mp4")
        result = resolver.summarize({"formats": formats})
        automatic = [s for s in result["streams"] if s["adaptive"]]
        self.assertEqual(len(automatic), 1)
        self.assertEqual(automatic[0]["source"], parent)
        self.assertEqual((automatic[0]["width"], automatic[0]["height"]), (0, 0))
        self.assertEqual(result["streams"][0], automatic[0])
        children = [s["source"] for s in result["streams"] if not s["adaptive"]]
        self.assertIn("https://cdn.example/signed/high.m3u8", children)
        self.assertNotIn("https://cdn.example/signed/high.m3u8?signature=original", children)

    def test_unsafe_or_missing_parent_urls_are_not_guessed(self):
        for parent in [None, "http://cdn.example/master.m3u8", "file:///tmp/master.m3u8", "https://user:pass@cdn.example/master.m3u8"]:
            result = resolver.summarize(media(protocol="m3u8_native", manifest_url=parent))
            self.assertEqual(len(result["streams"]), 1)
            self.assertFalse(result["streams"][0]["adaptive"])

    def test_shared_parent_retains_protection_and_authentication_restrictions(self):
        parent = "https://cdn.example/master.m3u8"
        for changes, reason in [({"has_drm": True}, "protected"), ({"http_headers": {"Cookie": "private"}}, "required_headers")]:
            formats = [media(protocol="m3u8_native", manifest_url=parent),
                       media(url="https://cdn.example/other.m3u8", protocol="m3u8_native", manifest_url=parent, **changes)]
            for order in [formats, list(reversed(formats))]:
                result = resolver.summarize({"formats": order})
                automatic = next(s for s in result["streams"] if s["adaptive"])
                self.assertEqual(automatic["unavailableReason"], reason)
                self.assertNotIn("private", json.dumps(result))

    def test_hls_variants_do_not_crowd_out_complete_mp4(self):
        formats = [media(url=f"https://cdn.example/{i}.m3u8", protocol="m3u8_native", width=4096, height=2048) for i in range(40)]
        formats.append(media(width=640, height=320))
        result = resolver.summarize({"formats": formats})
        self.assertEqual(result["streams"][0]["mimeType"], "video/mp4")
        self.assertEqual(len(result["streams"]), 32)

    def test_embedded_options_do_not_request_desktop_helpers_or_downloads(self):
        from types import SimpleNamespace
        options = {}

        class Downloader:
            def __init__(self, configuration):
                options.update(configuration)
            def __enter__(self):
                return self
            def __exit__(self, *args):
                pass
            def extract_info(self, address, *, download):
                self_test.assertFalse(download)
                return media()

        self_test = self
        extractor_class = type("Extractor", (), {})
        with patch.dict("sys.modules", {"yt_dlp": SimpleNamespace(YoutubeDL=Downloader),
                                       "yt_dlp.extractor.common": SimpleNamespace(InfoExtractor=extractor_class),
                                       "certifi": SimpleNamespace(where=lambda: "certificates.pem")}):
            self.assertEqual(json.loads(resolver.resolve("https://example.com/video"))["status"], "ok")
        self.assertTrue(options["skip_download"])
        self.assertEqual(options["format"], "best/bestvideo")
        self.assertTrue(options["ffmpeg_location"].endswith("__no_desktop_helpers__"))
        self.assertFalse(Path(options["ffmpeg_location"]).exists())
        self.assertEqual(options["js_runtimes"], {})
        self.assertEqual(options["remote_components"], [])
        self.assertFalse(options["nocheckcertificate"])
        self.assertFalse(options["geo_bypass"])
        self.assertFalse(options["usenetrc"])
        self.assertIsNone(extractor_class()._set_cookie("example.com", "age_verified", "1"))


if __name__ == "__main__":
    unittest.main()

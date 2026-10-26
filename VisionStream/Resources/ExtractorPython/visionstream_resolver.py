"""Resolve public media using bundled yt-dlp; never download media or executable code."""
import json
import os
import sys
from urllib.parse import urlsplit


def _unsupported_subprocess(*args, **kwargs):
    raise NotImplementedError("Desktop helper processes are unavailable on visionOS")


def _ignore_synthetic_cookie(*args, **kwargs):
    # Accept ordinary server-issued cookies, but do not let an extractor invent
    # age-verification, access-state or other cookies on the user's behalf.
    # Continue with ordinary public requests; the server decides whether access
    # is available without those assertions. Do not fabricate a verified state.
    return None


if sys.platform == "visionos":
    # Keep Popen a class because yt-dlp subclasses it. Block construction before
    # any extractor can attempt a helper process on the headset.
    import subprocess
    subprocess.Popen.__init__ = _unsupported_subprocess


class SilentLogger:
    def debug(self, message):
        pass

    def warning(self, message):
        pass

    def error(self, message):
        pass


def secure_url(value):
    if not isinstance(value, str) or len(value) > 16384:
        return False
    try:
        url = urlsplit(value)
        _ = url.port  # Validate malformed port strings without making a request.
        return url.scheme == "https" and bool(url.hostname) and not url.username and not url.password
    except ValueError:
        return False


def summarize(info):
    """Keep source URLs in memory only; do not forward cookies, headers or errors."""
    if not isinstance(info, dict) or info.get("_type") in ("playlist", "multi_video"):
        return {"status": "individual_video_required", "streams": []}
    if info.get("has_drm"):
        return {"status": "protected", "streams": []}
    formats = info.get("formats") or [info]
    declared_mesh = any("mesh" in str(f.get("format_note") or "").lower() for f in formats)
    streams = {}
    severity = {"": 0, "separate_audio": 1, "required_headers": 2, "projection": 3, "protected": 4}

    def add(stream):
        previous = streams.get(stream["source"])
        if previous is None:
            streams[stream["source"]] = stream
            return
        # A shared parent URL must retain restrictions from every associated
        # video format, rather than letting an unprotected entry win by order.
        if severity[stream["unavailableReason"]] > severity[previous["unavailableReason"]]:
            previous["unavailableReason"] = stream["unavailableReason"]
        if stream["advisory"]:
            previous["advisory"] = stream["advisory"]
        if stream["adaptive"]:
            previous.update(adaptive=True, width=0, height=0, mimeType="application/vnd.apple.mpegurl")

    for item in formats[:512]:
        source = item.get("url")
        if not secure_url(source) or item.get("vcodec") == "none":
            continue
        protocol, ext = item.get("protocol", "https"), item.get("ext", "")
        hls = protocol in ("m3u8", "m3u8_native") or urlsplit(source).path.lower().endswith(".m3u8")
        if not hls and (protocol != "https" or ext not in ("mp4", "m4v")):
            continue
        reason = ""
        header_names = {str(k).lower()
                        for headers in [info.get("http_headers") or {}, item.get("http_headers") or {}]
                        for k in headers}
        # Header metadata is not evidence that the media server requires it.
        # Try ordinary AVPlayer requests for Origin/Referer-only candidates;
        # never forward the header values or claim a server rejection is fixed.
        advisory = "request_context" if header_names & {"origin", "referer"} else ""
        projection = str(item.get("projection") or info.get("projection") or "").lower()
        note = str(item.get("format_note") or "").lower()
        if item.get("has_drm"):
            reason = "protected"
        elif declared_mesh or "mesh" in note or projection in ("mesh", "cubemap", "eac", "fisheye"):
            reason = "projection"
        elif not hls and item.get("acodec") == "none":
            reason = "separate_audio"
        elif header_names & {"authorization", "cookie"}:
            reason = "required_headers"
        width, height = item.get("width") or 0, item.get("height") or 0
        width = width if type(width) is int and 0 <= width <= 32768 else 0
        height = height if type(height) is int and 0 <= height <= 32768 else 0
        stream = {"source": source, "mimeType": "application/vnd.apple.mpegurl" if hls else "video/mp4",
                  "width": width, "height": height, "unavailableReason": reason,
                  "advisory": advisory, "adaptive": False}
        add(stream)
        parent = item.get("manifest_url")
        if hls and secure_url(parent) and parent != source:
            # Use only the parent playlist actually reported by the extractor.
            # Do not guess paths, copy tokens between URLs or rewrite manifests.
            add({**stream, "source": parent, "width": 0, "height": 0, "adaptive": True})
    # Keep complete MP4 sources visible even with many higher-resolution HLS
    # variants, then offer native adaptive selection before individual variants.
    ordered = sorted(streams.values(), key=lambda s: (
        bool(s["unavailableReason"]),
        0 if s["mimeType"] == "video/mp4" else (1 if s["adaptive"] else 2),
        # Width is often absent in website metadata. Multiplying by zero used
        # to preserve ascending extractor order and could put 240p before 1440p.
        -s["height"], -s["width"]))
    return {"status": "ok" if ordered else "no_stream", "streams": ordered[:32]}


def resolve(address):
    if not secure_url(address):
        return json.dumps({"status": "invalid_url", "streams": []})
    try:
        import certifi
        from yt_dlp import YoutubeDL
        from yt_dlp.extractor.common import InfoExtractor
        InfoExtractor._set_cookie = _ignore_synthetic_cookie
        options = {"quiet": True, "no_warnings": True, "logger": SilentLogger(),
                   "skip_download": True, "noplaylist": True, "cachedir": False,
                   "socket_timeout": 15, "retries": 0, "extractor_retries": 0,
                   "nocheckcertificate": False, "cacert": certifi.where(),
                   "geo_bypass": False, "usenetrc": False,
                   "js_runtimes": {}, "remote_components": [], "plugin_dirs": [],
                   # Select one existing stream. The default selector probes FFmpeg
                   # to decide whether separate video/audio tracks can be merged.
                   "format": "best/bestvideo",
                   "ffmpeg_location": os.path.join(os.path.dirname(__file__), "__no_desktop_helpers__"),
                   "check_formats": False, "ignore_no_formats_error": True}
        with YoutubeDL(options) as downloader:
            info = downloader.extract_info(address, download=False)
        return json.dumps(summarize(info))
    except Exception:
        # Exception messages can contain signed media URLs or account data.
        return json.dumps({"status": "unavailable", "streams": []})

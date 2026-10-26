# Browser downloads and third-party media

VisionStream is a general-purpose browser. A user navigating to an adult site does not make the application's advertised purpose an adult-content service. The shipping home page, metadata, screenshots and review examples must reflect the general browser honestly. Age rating must disclose unrestricted web access; Apple determines the resulting rating. Do not curate pornography or hide features from review.

Guideline 5.2.3 addresses saving, converting or downloading media from third-party sources without explicit authorization from those sources. Being a browser is not a blanket exemption for source extraction or conversion. An ordinary user-initiated download explicitly offered by a website is a different flow from finding an internal stream and remuxing it; the actual source permission and terms still matter. A user-facing 'I have permission' checkbox alone does not establish source authorization for the publisher.

For the current source finder / HLS-to-MP4 functionality, obtain written source permission that covers the app's actual streaming, saving and conversion behavior, or change the public product's supported save scope before submission. Keep a source-by-source record of the licensor, permitted hosts, media types, allowed operations, relevant terms, evidence date and review notes. Config/Publication.json may list local authorization documents for review; the tool does not automatically approve their sufficiency. No third-party-site authorization has been established during this work.

Safe baseline examples are the original CC0 calibration media, the user's own imports, and content with a verified download licence from its rights holder. Public accessibility alone is not a download licence. Do not bypass login, payment, DRM, geo/access restrictions, invent credentials or rewrite signed links. A working preview does not authorize a full-video download. Existing personal-use saving features were not silently removed by this release; they are fully disclosed in the draft review notes and remain a submission gate.

The app currently rejects encrypted HLS in its foreground fallback, does not fetch keys or decrypt media, and uses the exact source-published resource addresses. It copies packets without re-encoding and validates completed media. These technical controls do not substitute for source permission.

Before distribution, review guideline 5.2.2/5.2.3 and the relevant source terms with the publisher's actual permission evidence. Explain the permitted flows to App Review and provide evidence when requested. Approval cannot be guaranteed by adding disclaimer text.

Source: https://developer.apple.com/app-store/review/guidelines/#intellectual-property (checked 26 October 2026).

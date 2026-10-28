# Project notes

## 20i Reseller API
- Full API blueprint is in `docs/20i.txt` (about 17,000 lines, so search it with Grep instead of reading it all).
- Check it before writing or suggesting any 20i integration code. Headings look like `## Package Add [/reseller/{resellerId}/addWeb]`.
- Never put the 20i API key in the Flutter app. Calls must go through a backend.


# --- pearOS Pi image: build the wallpaper + blur once, not once per wizard page ---
# Every page (about 23) decodes the full wallpaper and blurs it with numpy; on a slow
# CPU (QEMU emulation, Pi Zero/3) that keeps the fullscreen window black for minutes.
# The result is identical: every page uses the same wallpaper and the pixbufs are read-only.
_load_pixbuf_uncached = load_pixbuf
_make_blurred_uncached = make_blurred
_PIXBUF_CACHE = {}
_BLUR_CACHE = {}


def load_pixbuf():
    key = wallpaper.find_wallpaper()
    if key not in _PIXBUF_CACHE:
        _PIXBUF_CACHE[key] = _load_pixbuf_uncached()
    return _PIXBUF_CACHE[key]


def make_blurred(pixbuf):
    key = id(pixbuf)
    if key not in _BLUR_CACHE:
        _BLUR_CACHE[key] = (pixbuf, _make_blurred_uncached(pixbuf))  # keep pixbuf alive: id() stays unique
    return _BLUR_CACHE[key][1]

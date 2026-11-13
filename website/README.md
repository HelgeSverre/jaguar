# website

The vjag home page: static HTML, no build step. Open `index.html`, or serve the folder:

```sh
python3 -m http.server -d website 8765
```

| Path | What |
|---|---|
| `*.html` | the pages; `frames.html` is the frames edition |
| `site.js` | header, navigation and footer (written with `document.write`), jukebox, visitor counter, cursor sparkles, the exploding V link |
| `style.css` | everything visual |
| `media/` | gameplay GIFs and jukebox tracks recorded with `vjag_test run --video/--wav`; the music video and its stills |
| `img/` | screenshots from `docs/screenshots`, 88×31 buttons, tiles and animated bits made with ImageMagick |
| `fonts/` | Press Start 2P (SIL OFL) |

No ROMs. Every GIF is homebrew from `demos/`. To re-record one, e.g. MAW:

```sh
./bin/vjag_test run demos/maw.jag --frames 230 --video out/maw.ppm --video-from 75 --press a@60 --press left@100+20
ffmpeg -framerate 60 -f image2pipe -c:v ppm -i out/maw.ppm \
  -vf "fps=20,split[a][b];[a]palettegen=max_colors=64:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
  website/media/maw.gif
```

# TV videos and a browser gallery

`export.py` turns retained TV-decoded PNG fields into H.264 MP4 videos and
a portable HTML gallery. It does not rerun the RTL simulation. The gallery
has native video controls, looping, scrubbing, playback-speed selection and
download links. Open `out/index.html` in a browser, or unpack
`out/tv-demos.zip` and open its `index.html`.

Run from the repository root, with FFmpeg and FFprobe installed:

```sh
nice ionice uv run --no-cache --offline demos/tv/export.py
```

The output directory must not already exist. Use `--out PATH` for a new
export. Every input sequence must have contiguous numeric field indices
and consistent PNG dimensions. The exporter stages the entire gallery,
checks it, then publishes the local output directory; a failed export
does not leave partial files at the requested destination.

## Current exports, 2026-09-30

| Clip | Fields | Nominal rate | Duration | MP4 size |
| --- | --- | --- | --- | --- |
| Retro console, PAL game | 120 | 50 fps | 2.400 s | 0.59 MB |
| Retro console, PAL effects | 540 | 50 fps | 10.800 s | 7.38 MB |
| Retro console, NTSC effects | 540 | 60000/1001 fps | 9.009 s | 6.01 MB |
| Semiring ring, geometry | 48 | 50 fps | 0.960 s | 0.16 MB |
| Interference, wave engine | 300 | 50 fps | 6.000 s | 2.32 MB |

All five are 768×480, H.264/yuv420p, silent, with MP4 metadata placed first
for streaming. Each retained field becomes one video frame; nothing is
skipped or interpolated. The rates are nominal PAL/NTSC rates, not the
slightly different field rates caused by each prototype's rounded clock
timing. The gallery loops short clips without adding repeated frames to
the files.

The exporter verifies every video frame count, rate, dimension and duration
with FFprobe, then fully decodes each MP4 with FFmpeg's error checking.
The manifest retains every source PNG hash, video hash, source-script
hashes, FFmpeg version and historical encoder command. The command's
temporary input path is an invocation record; rerun `export.py` to rebuild.
The ZIP CRC check passes. An independent cheap subagent reviewed frame
ordering, rates and output checks; its overwrite findings led to staging
the whole output in a fresh directory. A browser was not connected, so
playback UI was not tested here.

Rendered platformer frames are unavailable in the current checkout; the
exporter reports that sequence missing. Its prior full-run evidence is
retained in `prototypes/platformer/results/game.txt`. Regenerate the pin
fields and decode them using that prototype's README before exporting a
platformer clip. Its host-only preview is a separate reference-model path.

## Sharing and live demos

The individual MP4s are ready for a video upload. The ZIP contains the page,
videos, posters and manifest; serving its contents on a static web host
gives the same gallery. Generated media are local outputs ignored by Git;
the exporter and HTML template are committed. No external video upload or
site deployment was performed.

For a live browser demo, the smallest next step is a JavaScript/Canvas port
of a reference model, such as the semiring ring or platformer preview.
That can expose configuration controls or a keyboard without replaying
precomputed frames. It should be labelled as a reference-model preview.
A browser version of the full RTL pin-output and composite-TV path would
also need a simulator and decoder port; neither exists in this repository.

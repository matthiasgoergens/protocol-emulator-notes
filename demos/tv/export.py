"""Export existing TV-decoded PNG fields to MP4s and a portable browser gallery.

Run with uv run --no-cache --offline demos/tv/export.py. Needs ffmpeg/ffprobe;
does not simulate RTL or regenerate unavailable fields.
"""
import argparse
from fractions import Fraction
import hashlib
import html
import json
import pathlib
import re
import shutil
import struct
import subprocess
import tempfile
import zipfile

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
DEMOS = [
    ("platformer", "Tile platformer", "platformer", "game", "50",
     "Generic sequencer, PE row and output port; scripted game input."),
    ("retro-pal-game", "Retro console: PAL game", "retro-console", "frame", "50",
     "Special-purpose console chip; scripted game input."),
    ("retro-pal-effects", "Retro console: PAL effects", "retro-console", "demo", "50",
     "Sprite, scrolling and background demonstrations."),
    ("retro-ntsc-effects", "Retro console: NTSC effects", "retro-console", "reel_ntsc", "60000/1001",
     "The retained NTSC variant of the console effects reel."),
    ("semiring-ring", "Semiring ring: geometry", "semiring-ring", "reel", "50",
     "Sixteen arithmetic cells draw an ellipse, cubic band and moving glows."),
    ("interference", "Interference: wave engine", "wave-engine", "game", "50",
     "A game drawn by summed waves, with an autopilot cancelling invaders."),
]


def run(cmd):
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout


def png_size(path):
    with path.open("rb") as f:
        header = f.read(24)
    if header[:8] != b"\x89PNG\r\n\x1a\n" or header[12:16] != b"IHDR":
        raise ValueError(f"invalid PNG header: {path}")
    return struct.unpack(">II", header[16:24])


def sequence(directory, prefix):
    pattern = re.compile(re.escape(prefix) + r"_([0-9]+)\.png")
    numbered = sorted((int(m[1]), p) for p in directory.glob(prefix + "_*.png")
                      if (m := pattern.fullmatch(p.name)))
    if not numbered:
        return []
    indices = [i for i, _ in numbered]
    if indices != list(range(indices[0], indices[0] + len(indices))):
        raise ValueError(f"missing or duplicated field index in {directory}/{prefix}")
    frames = [p for _, p in numbered]
    sizes = {png_size(p) for p in frames}
    if len(sizes) != 1:
        raise ValueError(f"inconsistent frame dimensions: {sizes}")
    return frames


def encode(demo, frames, out):
    key, title, prototype, prefix, fps, description = demo
    width, height = png_size(frames[0])
    dest = out / f"{key}.mp4"
    if dest.exists():
        raise FileExistsError(f"refusing to overwrite {dest}; choose a fresh --out directory")
    # A temporary contiguous sequence handles arbitrary padding and nonzero starts.
    with tempfile.TemporaryDirectory(prefix="tv-video-") as temp:
        td = pathlib.Path(temp)
        for i, frame in enumerate(frames):
            (td / f"{i:06d}.png").symlink_to(frame.resolve())
        command = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-n",
                   "-threads", "2", "-framerate", fps, "-start_number", "0",
                   "-i", str(td / "%06d.png"), "-frames:v", str(len(frames)),
                   "-an", "-c:v", "libx264", "-threads", "2", "-preset", "slow",
                   "-crf", "18", "-vf", "pad=ceil(iw/2)*2:ceil(ih/2)*2,setsar=1",
                   "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(dest)]
        run(command)
    probe = json.loads(run(["ffprobe", "-v", "error", "-count_frames", "-select_streams", "v:0",
                            "-show_entries", "stream=codec_name,pix_fmt,width,height,avg_frame_rate,nb_read_frames:format=duration",
                            "-of", "json", str(dest)]))
    stream = probe["streams"][0]
    duration = float(probe["format"]["duration"])
    expected_duration = len(frames) / float(Fraction(fps))
    assert int(stream["nb_read_frames"]) == len(frames), stream
    assert stream["codec_name"] == "h264" and stream["pix_fmt"] == "yuv420p", stream
    assert Fraction(stream["avg_frame_rate"]) == Fraction(fps), stream
    assert stream["width"] == width + width % 2 and stream["height"] == height + height % 2, stream
    assert abs(duration - expected_duration) < 0.002, (duration, expected_duration)
    # Decode every output frame to catch damaged files independently of metadata.
    run(["ffmpeg", "-hide_banner", "-v", "error", "-xerror", "-threads", "2",
         "-i", str(dest), "-f", "null", "-"])
    poster = f"{key}.png"
    shutil.copyfile(frames[len(frames) // 2], out / poster)
    inputs = [{"path": str(p.relative_to(ROOT)), "sha256": hashlib.sha256(p.read_bytes()).hexdigest()}
              for p in frames]
    return dict(id=key, title=title, description=description, video=dest.name, poster=poster,
                fields=len(frames), fps=fps, seconds=duration, width=width, height=height,
                bytes=dest.stat().st_size, sha256=hashlib.sha256(dest.read_bytes()).hexdigest(),
                provenance="RTL pin dump → resistor-DAC model → software TV → PNG → H.264",
                timing="One retained field per video frame at the nominal PAL/NTSC field rate; no skipped fields.",
                historical_ffmpeg_command=command, probe=probe, inputs=inputs)


def gallery(rows):
    cards = []
    for r in rows:
        esc = lambda k: html.escape(str(r[k]), quote=True)
        cards.append(f'''<article><h2>{esc("title")}</h2>
<video controls loop playsinline preload="metadata" poster="{esc("poster")}">
<source src="{esc("video")}" type="video/mp4"></video>
<p>{esc("description")}</p>
<p class="meta">{r["fields"]} fields · {r["seconds"]:.2f} s · {r["width"]} × {r["height"]} · silent</p>
<label>Playback speed <select><option value="0.25">¼×</option><option value="0.5">½×</option><option value="1" selected>1×</option><option value="2">2×</option></select></label>
<a href="{esc("video")}" download>Download MP4</a></article>''')
    return (HERE / "gallery.html").read_text().replace("<!-- clips -->", "\n".join(cards))


def package(out, manifest):
    """Rebuild the generated page and bundle after checking media hashes."""
    for row in manifest["clips"]:
        if hashlib.sha256((out / row["video"]).read_bytes()).hexdigest() != row["sha256"]:
            raise ValueError(f"video changed: {row['video']}")
        if png_size(out / row["poster"]) != (row["width"], row["height"]):
            raise ValueError(f"poster dimensions changed: {row['poster']}")
    manifest["source_sha256"] = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                 for p in (HERE / "export.py", HERE / "gallery.html")}
    (out / "index.html").write_text(gallery(manifest["clips"]))
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    with zipfile.ZipFile(out / "tv-demos.zip", "w", compression=zipfile.ZIP_DEFLATED) as bundle:
        for path in sorted(out.iterdir()):
            if path.name != "tv-demos.zip":
                bundle.write(path, path.name)
        if bundle.testzip() is not None:
            raise ValueError("bundle CRC verification failed")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--out", type=pathlib.Path, default=HERE / "out")
    args = parser.parse_args()
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        parser.error("ffmpeg and ffprobe are required")
    if args.out.exists():
        parser.error(f"output directory already exists: {args.out}; choose a fresh --out directory")
    available, missing = [], []
    for demo in DEMOS:
        frames = sequence(ROOT / "prototypes" / demo[2] / "out", demo[3])
        if not frames:
            missing.append(demo[0])
            print(f"Unavailable rendered sequence: {demo[0]}", flush=True)
            continue
        available.append((demo, frames))
    if not available:
        parser.error("no rendered TV PNG sequences found; see the prototype READMEs")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    # Stage the entire gallery beside its destination. Failed encoding or checks
    # remove only these temporary outputs, leaving the requested destination absent.
    with tempfile.TemporaryDirectory(prefix=".tv-export-", dir=args.out.parent) as temp:
        stage = pathlib.Path(temp)
        rows = []
        for demo, frames in available:
            row = encode(demo, frames, stage)
            rows.append(row)
            print(f'{row["id"]}: {row["fields"]} fields, {row["seconds"]:.3f} s, {row["bytes"]} bytes; decoded and checked', flush=True)
        manifest = dict(clips=rows, unavailable=missing,
                        ffmpeg_version=run(["ffmpeg", "-version"]),
                        git_head=run(["git", "rev-parse", "HEAD"]).strip())
        package(stage, manifest)
        if args.out.exists():
            raise FileExistsError(args.out)
        stage.rename(args.out)
    print(f"Gallery: {args.out / 'index.html'}", flush=True)


if __name__ == "__main__":
    main()

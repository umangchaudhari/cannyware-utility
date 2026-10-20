#!/usr/bin/env python3
"""Convert HEIF/HEIC or JPEG to a JPEG no larger than 200 KB by default.

Install: python3 -m pip install Pillow pillow-heif
Run:     python3 compress_photo.py "IMG_1234.HEIC"
         python3 compress_photo.py "photo.jpeg" -o "small.jpg"
         python3 compress_photo.py "photo.heif" --max-kb 100

KB means 1,000 bytes. Output is always JPEG. Compression is lossy and may
reduce dimensions. The original is kept; existing output files are refused.
EXIF (including GPS), XMP and other metadata are omitted. Valid embedded ICC
profiles are used to convert the pixels to sRGB before metadata is removed.
HEIF files produce one still image, not a Live Photo or HDR output.
"""

import argparse
from io import BytesIO
from pathlib import Path
import sys
import warnings

try:
    from PIL import Image, ImageCms, ImageOps
    from pillow_heif import register_heif_opener
except ImportError:
    raise SystemExit(
        "Install dependencies first:\n"
        "  python3 -m pip install Pillow pillow-heif"
    )

register_heif_opener(thumbnails=False)


def load_photo(path):
    """Decode the photo, apply orientation and convert to ordinary RGB."""
    with Image.open(path) as source:
        if source.format not in {"JPEG", "HEIF"}:
            raise ValueError("Input must be a JPEG, HEIC or HEIF image.")

        # pillow-heif opens the primary photo automatically, even when it
        # is not frame zero in a multi-image HEIF container.
        image = ImageOps.exif_transpose(source)
        image.load()
        icc_profile = image.info.get("icc_profile")
        alpha = image.getchannel("A") if "A" in image.getbands() else None

        if icc_profile:
            try:
                # Preserve CMYK mode for CMYK JPEG profiles; strip alpha first.
                color = image if image.mode in {"RGB", "CMYK", "L"} else image.convert("RGB")
                image = ImageCms.profileToProfile(
                    color,
                    ImageCms.ImageCmsProfile(BytesIO(icc_profile)),
                    ImageCms.createProfile("sRGB"),
                    outputMode="RGB",
                )
            except (ImageCms.PyCMSError, OSError, ValueError):
                warnings.warn("Could not read the color profile; colors may differ slightly.")
                image = image.convert("RGB")
        else:
            image = image.convert("RGB")

        if alpha is not None:
            background = Image.new("RGB", image.size, "white")
            background.paste(image, mask=alpha)
            image = background

        image.info.clear()
        return image


def encode_jpeg(image, quality):
    buffer = BytesIO()
    image.save(
        buffer, format="JPEG", quality=quality,
        optimize=True, progressive=True, subsampling=2,
    )
    return buffer.getvalue()


def compress_photo(input_path, output_path=None, max_kb=200):
    """Return (output_path, byte_count, dimensions, JPEG_quality).

    Only write when the encoded bytes meet the size limit. The quality search
    uses levels 45..95; if none fit, resize proportionally and search again.
    """
    if not isinstance(max_kb, int) or max_kb < 1:
        raise ValueError("max_kb must be a positive integer.")
    limit = max_kb * 1000
    source = Path(input_path).expanduser().resolve()
    if not source.is_file():
        raise FileNotFoundError(f"Input image does not exist: {source}")
    target = (
        Path(output_path).expanduser().absolute() if output_path is not None
        else source.with_name(f"{source.stem}_compressed.jpg")
    )
    if target.suffix.lower() not in {".jpg", ".jpeg"}:
        raise ValueError("Output filename must end in .jpg or .jpeg.")
    if target.resolve() == source:
        raise ValueError("Choose a different output filename to keep the original.")
    if target.exists() or target.is_symlink():
        raise FileExistsError(f"Output already exists; choose another filename: {target}")

    original = load_photo(source)
    image = original
    scale = 1.0

    while True:
        best = None
        best_quality = None
        low, high = 45, 95
        while low <= high:
            quality = (low + high) // 2
            data = encode_jpeg(image, quality)
            if len(data) <= limit:
                best, best_quality = data, quality
                low = quality + 1
            else:
                high = quality - 1

        if best is not None:
            # Exclusive creation prevents overwriting even if a file appeared
            # while compression was running. These exact bytes were measured.
            with target.open("xb") as output:
                output.write(best)
            return target, len(best), image.size, best_quality

        if image.size == (1, 1):
            raise ValueError("The requested size is too small for a JPEG file.")

        scale *= 0.85
        size = (
            max(1, int(original.width * scale)),
            max(1, int(original.height * scale)),
        )
        # Always resize from the original to avoid repeated resampling blur.
        image = original.resize(size, Image.Resampling.LANCZOS)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("input", help="Input .heic, .heif, .jpg or .jpeg file")
    parser.add_argument("-o", "--output", help="Output JPEG path (optional)")
    parser.add_argument("--max-kb", type=int, default=200, help="Maximum size in decimal KB (default: 200)")
    args = parser.parse_args()
    try:
        path, size, dimensions, quality = compress_photo(args.input, args.output, args.max_kb)
    except (OSError, ValueError, Image.DecompressionBombError) as exc:
        print(f"Error: {exc}", file=sys.stderr)
        return 1
    print(f"Saved: {path}")
    print(f"Size: {size:,} bytes ({size / 1000:.2f} KB); limit: {args.max_kb:,} KB")
    print(f"Dimensions: {dimensions[0]} x {dimensions[1]}; JPEG quality: {quality}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

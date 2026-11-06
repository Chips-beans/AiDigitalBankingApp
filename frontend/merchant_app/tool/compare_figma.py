"""Build review boards, overlays and diagnostic diffs for Merchant reference frames.

Requires Pillow. Run from merchant_app:
  python tool/compare_figma.py --references .local/figma-change --catalog .local/figma-change/catalog-final --output .local/figma-change/comparison
Reference PNG names are node IDs with ':' replaced by '-'. No network requests.
"""
import argparse
import json
from pathlib import Path
from PIL import Image, ImageChops, ImageDraw, ImageStat


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--references', type=Path, required=True)
    parser.add_argument('--catalog', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(Path(__file__).with_name('merchant_figma_manifest.json').read_text())
    args.output.mkdir(parents=True, exist_ok=True)
    results = []
    for index, frame in enumerate(manifest['frames']):
        reference = args.references / (frame['node'].replace(':', '-') + '.png')
        candidates = sorted(p for p in args.catalog.glob(frame['catalogPrefix'] + '_*.png') if '_Scrolled' not in p.stem and '_2_' not in p.stem)
        if not reference.is_file() or len(candidates) != 1:
            raise RuntimeError(f"Missing/ambiguous capture for {frame['name']}")
        design = Image.open(reference).convert('RGB').resize((393, 852), Image.Resampling.LANCZOS)
        actual = Image.open(candidates[0]).convert('RGB').resize((393, 852), Image.Resampling.LANCZOS)
        # Only native OS status chrome is excluded. Dynamic differences remain visible.
        difference = ImageChops.difference(design, actual)
        difference.paste((0, 0, 0), (0, 0, 393, 44))
        overlay = Image.blend(design, actual, .5)
        name = frame['node'].replace(':', '-')
        overlay.save(args.output / (name + '-overlay.png'))
        difference.save(args.output / (name + '-diff.png'))
        board = Image.new('RGB', (393 * 3, 882), '#e8e8e8')
        draw = ImageDraw.Draw(board)
        for column, (label, capture) in enumerate([('Figma', design), ('Flutter', actual), ('Difference (diagnostic)', difference)]):
            draw.text((column * 393 + 8, 8), label + ' / ' + frame['name'], fill='black')
            board.paste(capture, (column * 393, 30))
        board.save(args.output / (name + '-comparison.jpg'), quality=90)
        results.append({**frame, 'capture': candidates[0].name, 'meanAbsoluteChannelDifference': round(sum(ImageStat.Stat(difference.crop((0, 44, 393, 852))).mean) / 3, 3)})
    (args.output / 'review.json').write_text(json.dumps({'notes': manifest['comparisonNotes'], 'frames': results}, indent=2))
    print(f'Prepared {len(results)} comparison boards; metrics are diagnostic, not acceptance.')


if __name__ == '__main__':
    main()

"""Render TruthLens' code-defined lens/check mark into Android and Play assets."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'release' / 'play-store'

def mark(size):
    scale = 4
    canvas = Image.new('RGB', (size * scale, size * scale), '#102738')
    d = ImageDraw.Draw(canvas)
    def xy(values): return tuple(int(v * size * scale / 512) for v in values)
    d.ellipse(xy((106, 88, 366, 348)), outline='#5DE3D3', width=int(size * scale * 28 / 512))
    d.line([xy((332, 315)), xy((407, 395))], fill='#5DE3D3', width=int(size * scale * 34 / 512))
    d.line([xy((169, 218)), xy((219, 266)), xy((302, 171))], fill='white', width=int(size * scale * 25 / 512), joint='curve')
    return canvas.resize((size, size), Image.Resampling.LANCZOS)

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    mark(512).save(OUT / 'icon-512.png')
    res = ROOT / 'android' / 'app' / 'src' / 'main' / 'res'
    for density, size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
        mark(size).save(res / f'mipmap-{density}' / 'ic_launcher.png')
    im = Image.new('RGB', (1024, 500), '#102738')
    im.paste(mark(300), (660, 100))
    d = ImageDraw.Draw(im)
    fonts = Path('C:/Windows/Fonts')
    title = ImageFont.truetype(str(fonts / 'segoeuib.ttf'), 62)
    sub = ImageFont.truetype(str(fonts / 'segoeui.ttf'), 27)
    d.text((66,135), 'TruthLens', font=title, fill='white')
    d.text((66,208), 'India', font=title, fill='#5DE3D3')
    d.text((70,315), 'News. Evidence. Perspective.', font=sub, fill='#D4E1E8')
    d.text((70,360), 'AI-assisted checks & crisis tracking', font=sub, fill='#D4E1E8')
    im.save(OUT / 'feature-graphic-1024x500.png')
    print('Rendered Android launcher icons and Play listing assets.')

if __name__ == '__main__': main()

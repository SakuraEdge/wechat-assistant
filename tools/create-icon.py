"""Rebuild the original code-drawn application icon (optional maintainer tool: Pillow)."""
from pathlib import Path
from PIL import Image, ImageDraw

root = Path(__file__).resolve().parents[1] / 'assets'
root.mkdir(exist_ok=True)
svg = '''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
<rect x="8" y="8" width="240" height="240" rx="60" fill="#6954d9"/>
<path d="M64 180L50 214L108 188Z" fill="#55c8ef"/>
<rect x="40" y="62" width="176" height="126" rx="42" fill="white"/>
<path d="M76 64L62 32L108 62M148 62L194 32L180 64" fill="white"/>
<rect x="72" y="102" width="28" height="38" rx="14" fill="#6954d9"/>
<rect x="156" y="102" width="28" height="38" rx="14" fill="#6954d9"/>
<path d="M111 151Q128 168 145 151" fill="none" stroke="#6954d9" stroke-width="9" stroke-linecap="round"/>
<path d="M192 203L202 189M210 211L220 197M226 218L236 204" stroke="#55c8ef" stroke-width="8" stroke-linecap="round"/>
</svg>'''
(root / 'clawbot.svg').write_text(svg, encoding='utf-8')
scale = 4
im = Image.new('RGBA', (256*scale, 256*scale))
d = ImageDraw.Draw(im)
def points(items): return [(x*scale,y*scale) for x,y in items]
def rounded(box,r,color): d.rounded_rectangle(tuple(v*scale for v in box), r*scale, fill=color)
rounded((8,8,248,248),60,'#6954d9')
d.polygon(points([(64,180),(50,214),(108,188)]),fill='#55c8ef')
d.polygon(points([(76,64),(62,32),(108,62)]),fill='white')
d.polygon(points([(148,62),(194,32),(180,64)]),fill='white')
rounded((40,62,216,188),42,'white')
for x in (72,156): rounded((x,102,x+28,140),14,'#6954d9')
d.arc((107*scale,136*scale,149*scale,163*scale),10,170,fill='#6954d9',width=9*scale)
for a,b in [((192,203),(202,189)),((210,211),(220,197)),((226,218),(236,204))]:
    d.line(points([a,b]),fill='#55c8ef',width=8*scale)
    for x,y in (a,b): d.ellipse(((x-4)*scale,(y-4)*scale,(x+4)*scale,(y+4)*scale),fill='#55c8ef')
im=im.resize((256,256),Image.Resampling.LANCZOS)
im.save(root/'clawbot.png')
im.save(root/'clawbot.ico',sizes=[(s,s) for s in [16,24,32,48,64,128,256]])
print('Application icon generated')

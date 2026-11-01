from PIL import Image, ImageDraw, ImageFilter
import math, sys
S=2048
def lerp(a,b,t): return tuple(int(a[i]+(b[i]-a[i])*t) for i in range(3))
def gradient(c1,c2):
    im=Image.new("RGB",(S,S)); px=im.load()
    g=Image.linear_gradient("L").rotate(45,expand=True).resize((S,S))
    # diagonal gradient via blend
    a=Image.new("RGB",(S,S),c1); b=Image.new("RGB",(S,S),c2)
    mask=Image.new("L",(S,S))
    md=mask.load()
    for y in range(0,S,4):
        for x in range(0,S,4):
            t=min(1,max(0,(x+y)/(2*S)))
            v=int(255*t)
            for dy in range(4):
                for dx in range(4):
                    md[x+dx,y+dy]=v
    return Image.composite(b,a,mask)
def glow(im,center,r,color,alpha):
    layer=Image.new("RGBA",(S,S),(0,0,0,0)); d=ImageDraw.Draw(layer)
    cx,cy=center; d.ellipse((cx-r,cy-r,cx+r,cy+r),fill=color+(alpha,))
    layer=layer.filter(ImageFilter.GaussianBlur(r*0.45))
    im.alpha_composite(layer)
def cube(d,cx,cy,s,top,left,right):
    h=s*math.sqrt(3)/2
    T=(cx,cy-s); UR=(cx+h,cy-s/2); LR=(cx+h,cy+s/2); B=(cx,cy+s); LL=(cx-h,cy+s/2); UL=(cx-h,cy-s/2); C=(cx,cy)
    d.polygon([T,UR,C,UL],fill=top)
    d.polygon([UL,C,B,LL],fill=left)
    d.polygon([C,UR,LR,B],fill=right)
def sparkle(d,cx,cy,r,fill):
    w=r*0.22
    pts=[]
    for i in range(8):
        ang=math.pi/2*i/2 - math.pi/2
        rad=r if i%2==0 else w
        pts.append((cx+rad*math.cos(ang),cy+rad*math.sin(ang)))
    d.polygon(pts,fill=fill)
def render(kind):
    if kind=="light":
        im=gradient((150,110,255),(52,28,140)).convert("RGBA")
        glow(im,(S*0.5,S*0.55),S*0.33,(255,255,255),70)
        faces=((255,255,255,255),(222,212,255,255),(178,160,255,255)); sp=(255,255,255,255)
    elif kind=="dark":
        im=Image.new("RGBA",(S,S),(14,11,24,255))
        glow(im,(S*0.5,S*0.55),S*0.33,(124,92,255),110)
        faces=((190,172,255,255),(140,112,255,255),(96,66,220,255)); sp=(210,196,255,255)
    else:
        im=Image.new("RGBA",(S,S),(0,0,0,0))
        faces=((255,255,255,255),(200,200,200,255),(150,150,150,255)); sp=(255,255,255,255)
    d=ImageDraw.Draw(im)
    cube(d,S*0.47,S*0.56,S*0.25,*faces)
    sparkle(d,S*0.74,S*0.28,S*0.095,sp)
    sparkle(d,S*0.83,S*0.44,S*0.045,sp)
    return im.resize((1024,1024),Image.LANCZOS)
out=sys.argv[1]
render("light").convert("RGB").save(f"{out}/icon_light.png")
render("dark").convert("RGB").save(f"{out}/icon_dark.png")
t=render("tint"); t.save(f"{out}/icon_tint.png")
# glyph (template): cube outline-ish silhouette on transparent
g=Image.new("RGBA",(S,S),(0,0,0,0)); d=ImageDraw.Draw(g)
cube(d,S*0.47,S*0.56,S*0.36,(0,0,0,255),(0,0,0,190),(0,0,0,130))
sparkle(d,S*0.86,S*0.2,S*0.12,(0,0,0,255))
g.resize((256,256),Image.LANCZOS).save(f"{out}/glyph.png")
prev=Image.new("RGB",(3*1024+80,1024+40),(40,40,40))
from PIL import ImageOps
def rounded(im):
    m=Image.new("L",im.size,0); ImageDraw.Draw(m).rounded_rectangle((0,0,1023,1023),radius=225,fill=255)
    bg=Image.new("RGB",im.size,(40,40,40)); bg.paste(im.convert("RGB"),(0,0),m); return bg
tb=Image.new("RGBA",(1024,1024),(0,0,0,255)); tb.alpha_composite(t)
for i,im in enumerate([Image.open(f"{out}/icon_light.png"),Image.open(f"{out}/icon_dark.png"),tb]):
    prev.paste(rounded(im),(20+i*(1024+20),20))
prev.resize((prev.width//3,prev.height//3)).save(f"{out}/preview.png")

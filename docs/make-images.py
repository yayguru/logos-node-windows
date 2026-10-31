# Renders docs/hero.png and docs/social-preview.png: a mock of the panel with EXAMPLE values only.
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import sys
MONO='/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf'; MONOB='/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'
SANS='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'; SANSB='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
C=dict(bg=(12,12,20),cy=(97,214,214),bl=(59,142,234),dcy=(42,161,179),mg=(214,112,214),dmg=(160,70,170),yl=(229,229,16),
       dy=(193,156,0),gr=(22,198,12),dg=(118,118,118),wh=(204,204,204),rd=(231,72,86),db=(0,55,218),lg=(160,160,160))
BAN=[('   _     ___   ____  ___  ____  ','  _   _  ___  ____  _____ ','cy','mg'),
     ('  | |   / _ \\ / ___|/ _ \\/ ___| ',' | \\ | |/ _ \\|  _ \\| ____|','cy','mg'),
     ('  | |  | | | | |  _| | | \\___ \\ ',' |  \\| | | | | | | |  _|  ','bl','mg'),
     ('  | |__| |_| | |_| | |_| |___) |',' | |\\  | |_| | |_| | |___ ','bl','dmg'),
     ('  |_____\\___/ \\____|\\___/|____/ ',' |_| \\_|\\___/|____/|_____|','dcy','dmg')]
def lines(full=True):
    L=[[]]
    for a,b,ca,cb in BAN: L.append([(a,ca),(b,cb)])
    L.append([('        ',None),('for Windows','yl'),('  -  Logos testnet full node  -  v0.3.4 build 9','dg')])
    L.append([('  '+'='*58,'db')])
    if not full: L.append([('  Mode: ','dcy'),('FULL NODE','gr'),('   Node: ','dcy'),('running','gr'),('   Mining: ','dcy'),('on','gr'),('   Threads: ','dcy'),('4','wh')])
    else: L.append([('  Mode: ','dcy'),('FULL NODE','gr'),('   Threads: ','dcy'),('4 of 8 CPU threads','wh'),('   Node: ','dcy'),('running','gr'),('   Mining: ','dcy'),('on','gr')])
    L.append([('  Sync: ','dcy'),('Online','gr'),('   Height: ','dcy'),('123,456','wh'),('   Peers: ','dcy'),('12','wh'),('   (example values)','dg')])
    L.append([])
    if not full:
        for k,t,c in [('1','Install full node + start mining   (opens P2P port)','gr'),('2','Mine only + start                  (outbound only)','cy'),
                      ('3','Status','wh'),('W','Wallet balance','gr'),('S','Send coins','gr'),('I','Inscribe  (text / image / file on-chain)','mg'),('U','Update  (signed)','dy')]:
            L.append([('   [','dg'),(k,'yl'),('] ','dg'),(t,c)])
        return L
    sec=[('START',[('1','Install full node + start mining   (opens P2P port)','gr'),('2','Mine only + start                  (outbound only, nothing opened)','cy')]),
         ('CONTROL',[('3','Status','wh'),('4','Set mining threads','mg'),('5','Stop mining  (node keeps running)','yl'),('6','Start mining','gr'),('7','Stop node','rd'),('R','Restart node','yl')]),
         ('TOOLS',[('C','Claim rewards','wh'),('W','Wallet balance','gr'),('S','Send coins','gr'),('A','Receive','cy'),('I','Inscribe  (text / image / file on-chain)','mg'),('U','Update  (signed, with rollback)','dy'),('Q','Quit','dg')])]
    for name,items in sec:
        L.append([('   '+name,'dy')])
        for k,t,c in items: L.append([('   [','dg'),(k,'yl'),('] ','dg'),(t,c)])
        L.append([])
    L.append([('  Choose: ','wh'),('_','wh')])
    return L
def window(full, fs, cols):
    f=ImageFont.truetype(MONO,fs); cw=f.getlength('M'); lh=int(fs*1.32)
    L=lines(full); W=int(cw*cols)+40; H=lh*len(L)+70
    im=Image.new('RGB',(W,H),C['bg']); d=ImageDraw.Draw(im)
    d.rectangle([0,0,W,38],fill=(32,32,40))
    tf=ImageFont.truetype(SANS,15); d.text((14,10),'Logos Node for Windows (unofficial)  -  panel.ps1',font=tf,fill=(200,200,210))
    for i,(x,c) in enumerate([(W-120,(90,90,100)),(W-80,(90,90,100)),(W-40,(196,43,28))]): d.rectangle([x,8,x+26,30],fill=c)
    y=52
    for ln in L:
        x=20
        for t,c in ln:
            if c: d.text((x,y),t,font=f,fill=C[c])
            x+=cw*len(t)
        y+=lh
    return im
def glow(size,top,bot):
    g=Image.new('RGB',size,top); d=ImageDraw.Draw(g)
    for yy in range(size[1]):
        t=yy/size[1]; d.line([(0,yy),(size[0],yy)],fill=tuple(int(top[i]*(1-t)+bot[i]*t) for i in range(3)))
    return g
def place(bg,win,xy,radius=12):
    m=Image.new('L',win.size,0); ImageDraw.Draw(m).rounded_rectangle([0,0,win.size[0]-1,win.size[1]-1],radius,fill=255)
    sh=Image.new('L',(win.size[0]+60,win.size[1]+60),0); ImageDraw.Draw(sh).rounded_rectangle([30,30,win.size[0]+30,win.size[1]+30],radius,fill=170)
    sh=sh.filter(ImageFilter.GaussianBlur(16)); bg.paste((0,0,0),(xy[0]-30,xy[1]-14),sh); bg.paste(win,xy,m)
def tag(d,xy,text,fg,bd,font):
    w=d.textlength(text,font=font); x,y=xy; d.rounded_rectangle([x,y,x+w+24,y+34],8,outline=bd,width=2); d.text((x+12,y+6),text,font=font,fill=fg); return x+w+24
# hero
win=window(True,17,86)
W=win.size[0]+120; H=win.size[1]+150
bg=glow((W,H),(24,18,48),(8,10,22)); place(bg,win,(60,110)); d=ImageDraw.Draw(bg)
d.text((60,30),'Logos Node for Windows',font=ImageFont.truetype(SANSB,34),fill=(235,235,245))
tf=ImageFont.truetype(SANSB,15); x=60+int(d.textlength('Logos Node for Windows',font=ImageFont.truetype(SANSB,34)))+24
for t,fg,bd in [('UNOFFICIAL',(255,190,90),(255,170,60)),('TESTNET',(120,220,230),(70,190,210)),('native .exe, no WSL',(200,170,240),(150,110,220))]:
    x=tag(d,(x,34),t,fg,bd,tf)+12
d.text((60,H-32),'Mock-up with example values. Not affiliated with or endorsed by the Logos project.',font=ImageFont.truetype(SANS,14),fill=(140,140,160))
bg.save(sys.argv[1]+'/hero.png',optimize=True)
# social preview 1280x640
sp=glow((1280,640),(28,18,56),(8,10,22)); d=ImageDraw.Draw(sp)
win=window(False,14,66); win=win.crop((0,0,win.size[0],win.size[1]))
place(sp,win,(1280-win.size[0]-36,(640-win.size[1])//2))
d.text((56,150),'Logos Node',font=ImageFont.truetype(SANSB,64),fill=(240,240,250))
d.text((56,228),'for Windows',font=ImageFont.truetype(SANSB,40),fill=(229,229,16))
sf=ImageFont.truetype(SANS,21)
for i,t in enumerate(['Native full node (no WSL, no Docker)','Menu panel: mining, wallet, inscriptions','Signed updates with rollback']):
    d.text((58,305+i*34),'- '+t,font=sf,fill=(200,200,215))
x=56
for t,fg,bd in [('UNOFFICIAL',(255,190,90),(255,170,60)),('TESTNET',(120,220,230),(70,190,210))]:
    x=tag(d,(x,430),t,fg,bd,ImageFont.truetype(SANSB,16))+12
d.text((58,486),'github.com/yayguru/logos-node-windows',font=ImageFont.truetype(MONO,17),fill=(150,150,175))
sp.save(sys.argv[1]+'/social-preview.png',optimize=True)
print(Image.open(sys.argv[1]+'/hero.png').size, sp.size)

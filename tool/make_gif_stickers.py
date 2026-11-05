"""Generate TOMI's small original animated sticker pack (no remote GIF service)."""
from pathlib import Path
from PIL import Image,ImageDraw
import math
OUT=Path(__file__).resolve().parent.parent/'assets/stickers';OUT.mkdir(parents=True,exist_ok=True)
for name in ('heart','wave','party'):
 frames=[]
 for frame in range(16):
  a=frame*math.tau/16;im=Image.new('RGBA',(160,160),(0,0,0,0));d=ImageDraw.Draw(im)
  if name=='heart':
   points=[];scale=3.4+.3*math.sin(a)
   for n in range(80):
    t=n*math.tau/80;points.append((80+scale*16*math.sin(t)**3,79-scale*(13*math.cos(t)-5*math.cos(2*t)-2*math.cos(3*t)-math.cos(4*t))))
   d.polygon(points,fill='#ed6b92');d.ellipse((49,40,64,53),fill='#ffbfd1')
   for n in range(4):
    x=80+66*math.cos(a+n*math.pi/2);y=80+60*math.sin(a+n*math.pi/2);d.ellipse((x-3,y-3,x+3,y+3),fill='#ffda86')
  else:
   offset=round(6*math.sin(a));d.rounded_rectangle((27,28+offset,133,136+offset),radius=44,fill='#c6ecd6',outline='#4fa18c',width=3)
   for x in (59,101):
    if name=='party' and frame%8<2:d.arc((x-7,65+offset,x+7,80+offset),180,355,fill='#225a55',width=4)
    else:d.ellipse((x-5,64+offset,x+5,78+offset),fill='#225a55')
   d.arc((63,80+offset,99,104+offset),0,180,fill='#225a55',width=4)
   if name=='wave':
    y=63+round(12*math.sin(a));d.rounded_rectangle((117,y,150,y+43),radius=14,fill='#e9c781',outline='#977947',width=2)
    for x in (123,130,137,144):d.line((x,y+7,x,y+19),fill='#977947',width=2)
   else:
    d.polygon(((45,39+offset),(80,4+offset),(112,39+offset)),fill='#e694a7');d.ellipse((73,0+offset,85,12+offset),fill='#f8d385')
    for n in range(10):
     x=(19+n*41+frame*3)%156;y=(n*27+frame*7)%156;color=('#eaa3bb','#e9ca75','#7cbcca')[n%3];d.rectangle((x,y,x+4,y+7),fill=color)
  # A fixed palette keeps transparent edges and all animation frames intact.
  image=im.convert('RGB').quantize(colors=127);alpha=im.getchannel('A');image.paste(255,mask=alpha.point(lambda v:255 if v==0 else 0));image.info['transparency']=255;frames.append(image)
 frames[0].save(OUT/f'gif_{name}.gif',save_all=True,append_images=frames[1:],duration=75,loop=0,disposal=2,transparency=255,optimize=False)
 print(name,Image.open(OUT/f'gif_{name}.gif').n_frames,(OUT/f'gif_{name}.gif').stat().st_size)

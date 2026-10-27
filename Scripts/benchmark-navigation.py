#!/usr/bin/env python3
"""Read-only live navigation benchmark in a private Ghostty-style PTY.
Run after installing a signed Nark build. No rules or filter settings are changed.
"""
import argparse, codecs, fcntl, json, math, os, pty, re, select, statistics, struct, subprocess, termios, time

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--binary', default='/Applications/Nark.app/Contents/MacOS/nark')
parser.add_argument('--size', default='140x42')
parser.add_argument('--samples', type=int, default=20)
parser.add_argument('--no-color', action='store_true')
args = parser.parse_args()
W,H = map(int,args.size.split('x')); CW,CH=8,16
if W<70 or H<20 or args.samples<2 or args.samples%2: parser.error('Use at least 70x20 and an even sample count of two or more.')
m,s=pty.openpty()
fcntl.ioctl(s,termios.TIOCSWINSZ,struct.pack('HHHH',H,W,W*CW,H*CH))
env=os.environ.copy()
env.update(TERM='xterm-ghostty',TERM_PROGRAM='ghostty',COLORTERM='truecolor',LANG='en_US.UTF-8')
env.pop('SWIFTTUI_COLLECTION_PROBES',None);env.pop('SWIFTTUI_DIAGNOSTICS',None)
if args.no_color:env['NO_COLOR']='1'
else:env.pop('NO_COLOR',None)
p=subprocess.Popen([args.binary],stdin=s,stdout=s,stderr=s,env=env,start_new_session=True)
os.close(s)
start=time.monotonic();raw=b'';pending='';screen=[[' ']*W for _ in range(H)]
x=y=0;decoder=codecs.getincrementaldecoder('utf8')('replace');frames=[];answered=set()
def feed(data):
 global pending,x,y,screen
 pending+=decoder.decode(data);i=0
 while i<len(pending):
  if pending[i]=='\x1b':
   if i+1>=len(pending):break
   if pending[i+1] in ']_P':
    a=pending.find('\x07',i+2);b=pending.find('\x1b\\',i+2);end=min([z for z in [a,b] if z>=0],default=-1)
    if end<0:break
    i=end+(1 if end==a else 2);continue
   if pending[i+1]=='[':
    q=re.compile(r'\x1b\[([0-?]*)([ -/]*)([@-~])').match(pending,i)
    if not q:break
    params,_,cmd=q.groups();i=q.end()
    if params.startswith(('?','>','<')):continue
    ns=[int(a) if a else 0 for a in params.split(';')] if params else [0];n=ns[0] or 1
    if cmd in 'Hf':y=max(0,min(H-1,n-1));x=max(0,min(W-1,(ns[1] if len(ns)>1 and ns[1] else 1)-1))
    elif cmd=='G':x=max(0,min(W-1,n-1))
    elif cmd=='d':y=max(0,min(H-1,n-1))
    elif cmd=='A':y=max(0,y-n)
    elif cmd=='B':y=min(H-1,y+n)
    elif cmd=='C':x=min(W-1,x+n)
    elif cmd=='D':x=max(0,x-n)
    elif cmd=='J' and ns[0] in (2,3):screen=[[' ']*W for _ in range(H)]
    elif cmd=='K':
     a,b=(0,W) if ns[0]==2 else (0,x+1) if ns[0]==1 else (x,W)
     screen[y][a:b]=[' ']*(b-a)
    elif cmd=='X':screen[y][x:min(W,x+n)]=[' ']*min(n,W-x)
    continue
   i+=2;continue
  c=pending[i];i+=1
  if c=='\r':x=0
  elif c=='\n':y=min(H-1,y+1)
  elif c>=' ':
   if x>=W:x=0;y=min(H-1,y+1)
   screen[y][x]=c;x+=1
 pending=pending[i:]

def lines():return [''.join(row) for row in screen]
def drain(seconds,until=None):
 global raw
 end=time.monotonic()+seconds
 while time.monotonic()<end and p.poll() is None:
  if until and until() and raw.count(b'\x1b[?2026h')==raw.count(b'\x1b[?2026l'):break
  if not select.select([m],[],[],min(.025,max(0,end-time.monotonic())))[0]:continue
  try:data=os.read(m,262144)
  except OSError:break
  raw+=data;frames.extend([time.monotonic()-start]*data.count(b'\x1b[?2026l'));feed(data)
  for q in re.finditer(rb'\x1b\]((?:10|11);\?|4;\d+;\?)\x07|\x1b\[\?1016\$p|\x1b\[\?u|\x1b\[c',raw):
   if q.start() in answered:continue
   answered.add(q.start());t=q.group()
   if t.startswith(b'\x1b]'):
    key=q[1].replace(b'?',b'rgb:1010/1818/2020');response=b'\x1b]'+key+b'\x07'
   elif b'1016' in t:response=b'\x1b[?1016;2$y'
   elif t.endswith(b'?u'):response=b'\x1b[?1u'
   else:response=b'\x1b[?62;22c'
   os.write(m,response)

def report(phase, samples):
 ordered=sorted(samples)
 print(json.dumps({'phase':phase,'median_ms':round(statistics.median(samples),2),
                   'p95_ms':ordered[math.ceil(len(ordered)*.95)-1],
                   'maximum_ms':max(samples),'samples':len(samples)}),flush=True)

try:
 drain(12,lambda:any('LIVE' in l for l in lines()));drain(.3)
 assert any('LIVE' in l for l in lines())
 print(json.dumps({'pid':p.pid,'size':[W,H],'first_frame_ms':frames[0]*1000}),flush=True)
 def selected():return next((i for i,l in enumerate(lines()) if len(l.split('│'))>1 and '▌' in l.split('│')[1]),None)
 def heading():
  parts=lines()[3].split('│')
  return parts[3] if len(parts)>3 else parts[1] if len(parts)>1 else ''
 def measure(key,predicate):
  t=time.monotonic();old=len(frames);os.write(m,key);drain(6,lambda:len(frames)>old and predicate())
  assert predicate(),'Input did not update selection'
  elapsed=max(0,(frames[-1]-(t-start))*1000)
  return round(elapsed,2)
 home=[]
 for i in range(args.samples):
  previous=selected();title=heading()
  home.append(measure(b'\x1b[B' if i%2==0 else b'\x1b[A',lambda:selected()!=previous and heading()!=title))
 report('home',home)
 before_row=selected();before_title=heading()
 os.write(m,(b'\x1b[B'+b'\x1b[A')*10);drain(1)
 assert selected()==before_row and heading()==before_title,'Rapid navigation lost selection or focus'
 print(json.dumps({'rapid_navigation_pairs':10,'selection_and_focus_preserved':True}),flush=True)
 os.write(m,b'l');drain(6,lambda:'[list]' in lines()[0]);drain(.1)
 table=[]
 for i in range(args.samples):
  previous=selected()
  table.append(measure(b'\x1b[B' if i%2==0 else b'\x1b[A',lambda:selected()!=previous))
 report('list',table)
 os.write(m,b'q');drain(3)
 assert p.poll()==0
 assert b'collection.eagerLargeCollection' not in raw
 print(json.dumps({'exit':0,'frames':len(frames)}),flush=True)
finally:
 if p.poll() is None:p.terminate()
 try:p.wait(timeout=3)
 except subprocess.TimeoutExpired:p.kill();p.wait()
 os.close(m)

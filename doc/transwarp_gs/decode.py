#!/usr/bin/env python3
"""XC2064 bitstream -> CLB logic decoder.
Port of Ken Shirriff's obsolete/reverse.py (CLB logic) + html/karnaugh.js (LUT->equation),
plus a reframer that turns the TWGS EPROM-stored serial bitstream into RBT frame lines.
"""
import re, sys

# ---------- karnaugh.js port: truth table -> boolean formula ----------
def _potential(query):
    V=[0xaaaa,0xcccc,0xf0f0,0xff00]
    table=0xffff
    for i in range(4):
        if query[i]==1: table&=V[i]
        elif query[i]==0: table&=(~V[i])&0xffff
    return table&0xffff

def _term(query):
    parts=[]
    for i in range(4):
        if query[i]==0: parts.append('~'+'0123'[i])
        elif query[i]==1: parts.append('0123'[i])
    return ' * '.join(parts)

def formula_string(table):
    table&=0xffff
    if table==0xffff: return '1'
    if table==0: return '0'
    state={'ones':table,'done':False,'result':[]}
    def apply(query):
        pt=_potential(query)
        if pt & (~table & 0xffff):
            return
        if pt & state['ones']:
            state['ones'] &= ~pt & 0xffff
            state['result'].append(_term(query))
            if state['ones']==0: state['done']=True
    def test(query,terms,index):
        if state['done']: return
        if terms+index>4: return
        if terms==0:
            apply(query); return
        for i in range(index,5):          # i==4 is a harmless phantom slot (matches JS)
            query[i]=0; test(query,terms-1,index+1)
            query[i]=1; test(query,terms-1,index+1)
            query[i]=-1
    for terms in range(1,5):
        test([-1,-1,-1,-1,-1],terms,0)
    return ' + '.join(state['result'])

def formula3(n,v0,v1,v2):
    s=formula_string(((n<<8)|n)&0xffff)
    return s.replace('0',v0).replace('1',v1).replace('2',v2)
def formula4(n,v0,v1,v2,v3):
    s=formula_string(n&0xffff)
    return s.replace('0',v0).replace('1',v1).replace('2',v2).replace('3',v3)

# ---------- reframer: EPROM serial stream -> 160 RBT frames ----------
def unpack_lsb_first(data):
    bits=[]
    for byte in data:
        for i in range(8):
            bits.append((byte>>i)&1)
    return ''.join(map(str,bits))

def to_rbt_frames(binpath):
    data=open(binpath,'rb').read()
    bs=unpack_lsb_first(data)
    # find a frame-start offset where 160 consecutive 75-bit windows are '0'+71+'111'
    for start in range(20,80):
        ok=True
        for f in range(160):
            w=bs[start+75*f:start+75*f+75]
            if len(w)!=75 or w[0]!='0' or w[-3:]!='111':
                ok=False;break
        if ok:
            frames=[bs[start+75*f:start+75*f+75] for f in range(160)]
            return frames,start
    raise SystemExit('could not locate 160 valid frames')

# ---------- reverse.py port: CLB decode ----------
yidx={'io1':0,'H':9,'G':27,'buf1':45,'F':47,'E':65,'D':83,'buf2':101,'C':103,'B':121,'A':139,'io2':157}
xidx={'io1':0,'H':4,'G':12,'buf1':20,'F':21,'E':29,'D':37,'buf2':45,'C':46,'B':54,'A':62,'io2':70}

class Reverse:
    def __init__(self):
        self.buf={}
    def read_rbt(self,fname):
        cnt=0
        for line in open(fname):
            m=re.match('0([01]{71})111',line)
            if m:
                self.buf[cnt]=m.group(1); cnt+=1
        assert cnt==160,f'got {cnt} frames'
    def load_frames(self,frames):
        for i,fr in enumerate(frames):
            self.buf[i]=fr[1:-3]
        assert len(self.buf)==160
    def getFormula(self,table,vars):
        n=sum((1<<i) for i,b in enumerate(table) if b)
        if len(table)==8:
            return formula3(n,vars[0],vars[1],vars[2]).replace(' ','')
        else:
            return formula4(n,vars[0],vars[1],vars[2],vars[3]).replace(' ','')
    def processClb(self,name):
        buf=self.buf
        result=[]; xlabel,ylabel=list(name)
        result.append('Editblk %s'%name)
        x0=xidx[xlabel]; y0=yidx[ylabel]
        def active(xo,yo): return 1 if buf[y0+yo][x0+xo]=='0' else 0
        def mux2(a,a0,a1): return a1 if a else a0
        def mux3(a,b,a0b0,a1b0,a0b1):
            assert not a or not b
            return [a0b0,a0b1,a1b0][a*2+b]
        def mux4(a,b,a0b0,a1b0,a0b1,a1b1):
            return [a0b0,a0b1,a1b0,a1b1][a*2+b]
        gtab=[active(0,1),active(0,0),active(0,2),active(0,3),active(0,5),active(0,4),active(0,6),active(0,7)]
        ftab=[active(0,16),active(0,17),active(0,15),active(0,14),active(0,12),active(0,13),active(0,11),active(0,10)]
        fmux=[mux2(active(1,10),'B','A'),mux2(active(1,11),'C','B'),mux3(active(1,16),active(1,17),'Q','C','D')]
        gmux=[mux2(active(1,6),'B','A'),mux2(active(1,5),'C','B'),mux3(active(1,1),active(1,0),'Q','C','D')]
        if active(0,8): base='FG'
        else: base='F' if fmux==gmux else 'FGM'
        result.append('Base %s'%base)
        equate=[]; equation=equationf=equationg=None
        if base in ('FG','FGM'):
            equationf=self.getFormula(ftab,fmux); equationg=self.getFormula(gtab,gmux)
            if equationf!='0': equate.append('Equate F = %s'%equationf)
            if equationg!='0': equate.append('Equate G = %s'%equationg)
        else:
            gtab2=gtab+ftab; fmux2=fmux+['B']
            equation=self.getFormula(gtab2,fmux2)
            equate.append('Equate F = %s'%equation)
            fmux=fmux2
        config='Config X:'+mux3(active(2,7),active(2,6),'Q','F','G')
        config+=' Y:'+mux3(active(2,4),active(2,5),'Q','F','G')
        def valid(entries,eq):
            r=[]
            for i in range(len(entries)):
                if entries[i] in eq and entries[i] not in entries[:i]: r.append(entries[i])
            return r
        if base=='F':
            config+=' F:'+':'.join(valid([fmux[0],fmux[3],fmux[1],fmux[2]],equation))
        else:
            config+=' F:'+':'.join(valid(fmux,equationf))
            config+=' G:'+':'.join(valid(gmux,equationg))
        config+=' Q:'+mux2(active(2,8),'FF','LATCH')
        config+=' SET:'+mux3(active(2,14),active(2,15),'A','F','')
        config+=' RES:'+mux4(active(2,16),active(2,17),'','D','undef','G')
        config+=' CLK:'
        if active(3,14) or active(3,15): config+='K'
        elif active(3,11):
            config+='C' if active(3,13) else 'G'
            if 1^active(3,12)^active(2,8)^active(3,13): config+=':NOT'
        result.append(config); result.extend(equate); result.append('Endblk')
        return result
    def isDefault(self,name):
        buf=self.buf; xlabel,ylabel=list(name)
        x0=xidx[xlabel]; y0=yidx[ylabel]
        for yo in range(18):
            for xo in range(8):
                if (yo==8 and xo in (0,2)) or (xo==2 and yo==15):
                    if buf[y0+yo][x0+xo]=='1': return False
                else:
                    if buf[y0+yo][x0+xo]=='0': return False
        return True
    def all_clbs(self):
        out=[]
        for a in 'ABCDEFGH':
            for b in 'ABCDEFGH':
                name=a+b
                out.append((name,self.isDefault(name),self.processClb(name)))
        return out

if __name__=='__main__':
    cmd=sys.argv[1]
    if cmd=='validate':
        r=Reverse(); r.read_rbt(sys.argv[2])
        # dump a few CLB structural configs to compare to LCA
        for name in sys.argv[3:]:
            print('\n'.join(r.processClb(name)))
    elif cmd=='reframe':
        frames,start=to_rbt_frames(sys.argv[2])
        print(f'frame start bit offset = {start}')
        with open(sys.argv[3],'w') as f:
            for fr in frames: f.write(fr+'\n')
        print(f'wrote {len(frames)} frames to {sys.argv[3]}')
    elif cmd=='decode':
        frames,start=to_rbt_frames(sys.argv[2])
        r=Reverse(); r.load_frames(frames)
        used=0
        for name,isdef,cfg in r.all_clbs():
            if isdef:
                print(f'; CLB {name}: (default/unused)')
            else:
                used+=1
                print('\n'.join(cfg))
        print(f'\n; ---- {used} of 64 CLBs configured ----')

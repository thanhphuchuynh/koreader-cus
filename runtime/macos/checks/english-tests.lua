package.path=assert(arg[1])..'/?.lua;'..package.path
local J=require('json')
local I=require('english_ielts')
local T=require('english_tests')
local function qs(n) local q={} for i=1,n do q[i]={n=i,type='gap',words=1,answer='a'..i} end return q end
local one=J.encode{version=1,title='Alpha',minutes=20,passages={{n=1,from=1,to=6}},questions={{n=1,type='gap',words=1,answer='x'},{n=2,type='choice',answer='TRUE'},{n={3,4},type='multi',answers={'A','C'}},{n=5,type='gap',words=1,answer='y'},{n=6,type='gap',words=1,answer='z'}}}
local three=J.encode{version=1,title='Beta',minutes=60,passages={{n=1,from=1,to=13},{n=2,from=14,to=26},{n=3,from=27,to=40}},questions=qs(40)}
local files={['/t/a.epub']=one,['/t/b.epub']=three,['/t/bad.epub']='{',['/t/nil.epub']=false,['/t/err.epub']='ERR'}
local recs,mt={},{}
reads=0
local io_={list=function() return {'/t/a.epub','/t/b.epub','/t/bad.epub','/t/nil.epub','/t/err.epub'} end,
 stat=function(p) return {size=#(files[p] or ''),mtime=1} end,
 readJson=function(p) reads=reads+1 if files[p]=='ERR' then error('boom') end return files[p] or nil end,
 record=function(p) return recs[p] end,recordMtime=function(p) return mt[p] end}
local function by(items,t) for _,i in ipairs(items) do if i.title==t then return i end end end
local it=T.scan('/t',io_,0);assert(#it==2,'bad/nil/erroring files skipped')
local a,b=by(it,'Alpha'),by(it,'Beta')
assert(a.state=='new' and a.meta=='6 Q · 20 min' and a.total==6 and a.minutes==20 and a.active==0 and a.path=='/t/a.epub')
assert(b.meta=='40 Q · 60 min · 3 passages')
recs['/t/a.epub']={mode='practice',answers={[1]='TRUE',[3]={'A','C'},[99]='zzz'},elapsed=440};mt['/t/a.epub']=100
a=by(T.scan('/t',io_,0),'Alpha');assert(a.state=='progress' and a.answered==3 and a.remaining==760 and a.active==100,'q99 ignored')
recs['/t/a.epub'].mode='study';a=by(T.scan('/t',io_,0),'Alpha');assert(a.remaining==nil and a.state=='progress')
recs['/t/a.epub']={mode='practice',answers={[1]='x',[5]='y'},elapsed=1,finished=true};mt['/t/a.epub']=50
a=by(T.scan('/t',io_,0),'Alpha');local bd,rough=I.band(2,6)
assert(a.state=='done' and a.right==2 and a.band==bd and a.rough==rough,'cache not stale')
recs['/t/b.epub']={mode='practice',answers={[1]='a1'},elapsed=10};mt['/t/b.epub']=200
it=T.scan('/t',io_,0);b=by(it,'Beta')
local s=T.summary(it);assert(s.count==2 and s.finished==1 and s.lastBand==bd)
assert(T.continueItem(it)==b);recs['/t/b.epub']=nil;assert(T.continueItem(T.scan('/t',io_,0))==nil)
recs['/t/b.epub']={answers={},elapsed=0};local o=T.ordered(T.scan('/t',io_,0))
assert(o[1].title=='Beta' and o[2].title=='Alpha' and T.summary({}).lastBand==nil)
local r0=reads;T.scan('/t',io_,0);assert(reads==r0,'cache hit: no re-read')
local st0=io_.stat;io_.stat=function(p) local x=st0(p);x.mtime=2;return x end;T.scan('/t',io_,0);assert(reads>r0,'changed mtime re-reads');io_.stat=st0
assert(#T.scan('/nope',{list=function() error('no dir') end},0)==0)
print('PASS: tests tab scan, status, summary, continue, ordering')

require('setupkoenv')
package.path=assert(arg[1])..'/?.lua;'..package.path
local Cache=require('english_cache')
local cache=Cache.new()
assert(not cache:get('one'))
cache:put('one',{text="I can't give up.",mode='translate',provider='Google Translate',result='Tôi không thể bỏ cuộc.'})
package.loaded.english_cache=nil
cache=require('english_cache').new()
assert(cache:get('one').result=='Tôi không thể bỏ cuộc.','cache survives reopening')
assert(cache:list()[1].text=="I can't give up.")
cache:put('one',{text='Updated',mode='translate',provider='AI',result='New meaning'})
assert(#cache:list()==1 and cache:get('one').provider=='AI')
for i=1,105 do cache:put('entry'..i,{text='Passage '..i,mode='translate',provider='Google',result='Meaning '..i}) end
assert(#cache:list()==100 and not cache:get('one') and cache:get('entry105'),'history must stay bounded')
cache:clear();assert(#cache:list()==0)
print('PASS: real SQLite cache persistence, exact identity, update, bounded history and clear')

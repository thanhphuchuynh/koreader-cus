-- Run with the bundled LuaJIT from its runtime directory, using an isolated KO_HOME.
require('setupkoenv')
local plugin_dir=assert(arg[1])
package.path=plugin_dir..'/?.lua;'..package.path
package.loaded.device={canUseWAL=function()return false end}
local shown={}
package.loaded['ui/uimanager']={show=function(_,v)shown[#shown+1]=v end}
package.loaded['ui/widget/infomessage']={new=function(_,v)return v end}
package.loaded.english_popup={show=function(options)
 local view={options=options,closed=false}
 local function close()view.closed=true end
 view.buttons=options.buttons(close)
 shown[#shown+1]=view
 return view
end}
local Vocab=require('english_vocab')
assert(Vocab.maskSentence('Leave now; leave later, but never cleave.', 'leave')=='____ now; ____ later, but never cleave.')
assert(Vocab.maskSentence("Don't stop; don't worry.", "don't")=="____ stop; ____ worry.")
local vocab=Vocab.new({})
local entry={sentence="She couldn't leave the bridge behind.",definition='To depart from a place.',dictionary='Test dictionary',book_title='Bridge'}
assert(not vocab:isSaved('leave'))
assert(vocab:save('leave',entry))
assert(vocab:isSaved('leave'))
-- Reopen the module/controller: this must be durable, not a per-book flag.
package.loaded.english_vocab=nil
vocab=require('english_vocab').new({})
assert(vocab:isSaved('leave'),'saved status must survive reopening')
vocab:showReview()
local prompt=shown[#shown]
assert(prompt.options.title=='Recall the word' and not prompt.options.text:find('leave',1,true),'cloze must hide the word in both title and sentence')
assert(not prompt.options.text:find(entry.definition,1,true),'meaning must stay hidden until Reveal')
prompt.buttons[1][1].callback()
local revealed=shown[#shown]
assert(prompt.closed and revealed.options.text:find(entry.definition,1,true))
assert(revealed.buttons[1][1].text=='Again' and revealed.buttons[1][2].text=='Remembered')
revealed.buttons[1][2].callback()
local DB=dofile('plugins/vocabbuilder.koplugin/db.lua')
local item=assert(DB:hasWord('leave'))
assert(item.review_count==1 and item.streak_count==1 and item.due_time>os.time(),'review must persist native scheduling')
local due=item.due_time
assert(vocab:save('leave',entry))
assert(DB:hasWord('leave').due_time==due and DB:hasWord('leave').review_count==1,'saving twice must not reset progress')
entry.book_title='Another book';entry.sentence='She decided to leave again.'
assert(vocab:save('leave',entry))
vocab:showReview()
assert(shown[#shown].options.subtitle:find('Another book',1,true) and shown[#shown].options.text:find('____',1,true),'saved sentence and book must stay paired')
assert(DB:hasWord('leave').review_count==1,'refreshing a snapshot preserves scheduling')
-- Dismissing a card must not count as a review.
vocab:showReview()
assert(DB:hasWord('leave').review_count==1)
for i=1,6 do assert(vocab:save('word'..i,entry))end
vocab:showReview()
for i=1,5 do
 local card=shown[#shown]
 assert(card.options.subtitle:find(i..'/5',1,true),'session must be capped at five cards')
 card.buttons[1][1].callback()
 shown[#shown].buttons[1][1].callback()
end
assert(shown[#shown].options.title=='Review complete')
-- Removing a word in native vocabulary must hide its supplemental record too.
DB:remove({word='leave'})
assert(not vocab:isSaved('leave'))
print('PASS: real SQLite persistence, sentence/meaning recall, native scheduling, duplicate saves, five-card limit, native removal')
assert(vocab:save('book',{definition='A written work.',book_title='Test'}))
DB:batchUpdateItems({{word='book',review_count=0,streak_count=0,review_time=os.time(),due_time=0}})
vocab:showReview()
assert(shown[#shown].options.title=='book','missing sentence must use meaning recall, never turn explanatory UI copy into a cloze')
print('PASS: missing book context never produces a fabricated cloze sentence')

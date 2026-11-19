-- Real phrase index shipped in the plugin (built by runtime/build-phrases.py).
local plugin=assert(arg[1])
package.path=plugin..'/?.lua;'..package.path
local M=require('english_phrases')
local p=assert(M.new(plugin..'/english_phrases.tsv'),'phrase index must be installed')
local function at(sentence,word)
 local r=p:find(sentence,sentence:find(word,1,true))
 return r and r.text, r and r.headword
end
local function same(a,b,c,d)assert(a==b and c==d,tostring(a)..' / '..tostring(c))end
same(at('In the second round, the challenger gave up.','gave'),'gave up',select(2,at('In the second round, the challenger gave up.','gave')),'give up')
same(at('In the second round, the challenger gave up.','up'),'gave up',select(2,at('In the second round, the challenger gave up.','up')),'give up')
same(at('Once in a blue moon he calls.','blue'),'Once in a blue moon',select(2,at('Once in a blue moon he calls.','blue')),'once in a blue moon')
same(at('He finally kicked the bucket, aged ninety.','bucket'),'kicked the bucket',select(2,at('He finally kicked the bucket, aged ninety.','bucket')),'kick the bucket')
same(at('We’ll have to break the ice somehow.','ice'),'break the ice',select(2,at('We’ll have to break the ice somehow.','ice')),'break the ice')
assert(not at('They gave. Up the hill they went.','gave'),'phrases never cross punctuation')
assert(select(2,at('Nora made up her mind on the spot.','mind'))=="make up one's mind",'possessive pronouns match one\'s')
assert(select(2,at('The city was getting on her nerves.','nerves'))=="get on someone's nerves",'possessive pronouns match someone\'s')
assert(at('She brought it up at breakfast.','brought')=='brought it up' and select(2,at('She brought it up at breakfast.','brought'))=='bring up','separable phrasal verb with a pronoun object')
assert(not at('The cat sat on the mat.','cat'),'plain words are not idioms')
assert(p:lookup('give up')=='give up' and p:lookup('gave up')=='give up' and not p:lookup('of the') and not p:lookup('zzzz zz'))
assert(M.gloss('v.\n1.\nquit\n— give up in the face of defeat\n“example”')=='give up in the face of defeat')
assert(M.gloss('noun\nA very rare event that happens once.')=='A very rare event that happens once.')
print('PASS: offline idiom index finds the longest phrase with inflections, respects punctuation, extracts a gloss')

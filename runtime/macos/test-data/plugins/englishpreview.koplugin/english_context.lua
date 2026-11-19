-- Sentence and paragraph around a tapped word, from the book's own DOM (EPUB/crengine).
-- KOReader's extendXPointersToSentenceSegment only widens a selection to punctuation;
-- it never grows one word into its sentence, so sentences are cut here.
local M={}

-- Sentence ranges {first,last} (byte offsets). A sentence ends at . ! ? or … plus any
-- closing quotes/brackets, followed by whitespace. ponytail: no abbreviation list ("Mr."
-- splits); add one if it shows up in real books.
function M.sentences(text)
 -- Same-length ASCII stand-ins so byte offsets stay valid: … ” ’ are 3 bytes each.
 local scan=text:gsub('…','...'):gsub('”','"""'):gsub('’',"'''")
 local ranges,first,pos={},1,1
 while true do
  local _,stop,space=scan:find('[%.!%?]["\'%)%]]*()%s+',pos)
  if not stop then break end
  ranges[#ranges+1]={first,space-1}
  first,pos=stop+1,stop+1
 end
 if text:find('%S',first) then ranges[#ranges+1]={first,#text} end
 return ranges
end

local function trim(s)return (s:gsub('^%s+',''):gsub('%s+$',''))end

-- The sentence containing byte offset `at` (1-based), or nil.
function M.at(text,at)
 for _,r in ipairs(M.sentences(text))do
  if at<=r[2] then return trim(text:sub(r[1],r[2])) end
 end
end

-- Paragraph as one sentence per line (for line-by-line translation pairs).
function M.lines(text)
 local out={}
 for _,r in ipairs(M.sentences(text))do
  local s=trim(text:sub(r[1],r[2]));if s~='' then out[#out+1]=s end
 end
 return table.concat(out,'\n'),#out
end

local inline={a=1,span=1,i=1,b=1,em=1,strong=1,u=1,s=1,sup=1,sub=1,small=1,big=1,font=1,abbr=1,
 cite=1,q=1,code=1,mark=1,tt=1,strike=1,del=1,ins=1,label=1,ruby=1,rt=1}
local top={body=1,DocFragment=1,html=1}

-- Block element holding xpointer `xp`: drop the text node, then climb out of inline tags,
-- never up to <body>/<DocFragment> (that would be a whole chapter).
function M.block(xp)
 local node=xp and xp:gsub('/text%(%)[^/]*$','')
 if not node or node==xp then return nil end
 local function tag(p)return p:match('/([%w_]+)[%[%d%]]*$') end
 while inline[tag(node) or ''] do
  local parent=node:gsub('/[^/]+$','')
  if top[tag(parent) or 'body'] then break end
  node=parent
 end
 if top[tag(node) or 'body'] then return nil end
 return node
end

-- {sentence=, paragraph=, text=, at=} for a word selection in a rolling (EPUB) document, or nil.
function M.around(document,pos0)
 local block=M.block(pos0)
 if not block then return nil end
 local text=document:getTextFromXPointer(block)
 local before=document:getTextFromXPointers(block,pos0)
 if type(text)~='string' or not text:find('%S') or type(before)~='string' then return nil end
 local sentence=M.at(text,#before+1)
 if not sentence or sentence=='' then return nil end
 local paragraph,count=M.lines(text)
 -- text/at: raw paragraph and the word's byte offset in it (for idiom detection).
 return {sentence=sentence,paragraph=count>1 and paragraph or nil,text=text,at=#before+1}
end

return M

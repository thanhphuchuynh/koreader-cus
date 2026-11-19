-- Offline idiom / phrasal-verb detection around a tapped word.
-- english_phrases.tsv (built by runtime/build-phrases.py from the en-en dictionary) holds
-- "form<TAB>headword" lines in byte order; lookups binary-search the file with seeks,
-- so nothing is loaded into memory. LuaJIT compares strings bytewise, matching the sort.
local M={}

-- Words with byte ranges and a segment id; punctuation between words starts a new segment,
-- so phrases never span "gave. Up" or a comma.
function M.tokens(text)
 local tokens,segment,last=  {},1,nil
 for first,word,stop in text:gmatch("()([%a][%a'’%-]*)()")do
  if last and text:sub(last,first-1):find('[^%s]') then segment=segment+1 end
  word=word:gsub('’',"'"):lower():gsub("[-']+$",'')
  tokens[#tokens+1]={word=word,first=first,last=stop-1,segment=segment}
  last=stop
 end
 return tokens
end

-- Dictionary idioms use placeholders ("make up one's mind", "get on someone's nerves");
-- real pronouns in the book map onto them.
local POSSESSIVE={my=1,your=1,his=1,her=1,its=1,our=1,their=1}
local OBJECT={me=1,you=1,him=1,her=1,it=1,us=1,them=1}
local REFLEXIVE={myself=1,yourself=1,himself=1,herself=1,itself=1,ourselves=1,yourselves=1,themselves=1}
local function choices(word)
 local list={word}
 if POSSESSIVE[word] then list[#list+1]="one's";list[#list+1]="someone's" end
 if OBJECT[word] then list[#list+1]='someone';list[#list+1]='something' end
 if REFLEXIVE[word] then list[#list+1]='oneself' end
 return list
end
-- Dictionary keys to try for a run of words, exact first.
function M.keys(words)
 local keys={''}
 for i,word in ipairs(words)do
  local next_keys={}
  for _,key in ipairs(keys)do
   for _,choice in ipairs(choices(word))do next_keys[#next_keys+1]=(i>1 and key..' ' or '')..choice end
  end
  keys=next_keys
 end
 -- Separable phrasal verb with a pronoun object: "brought it up" -> "brought up".
 if #words==3 and OBJECT[words[2]] then keys[#keys+1]=words[1]..' '..words[3] end
 return keys
end

function M.new(path)
 local self={}
 local f=io.open(path,'rb')
 if not f then return nil end
 local size=f:seek('end')
 pcall(f.setvbuf,f,'full',256) -- small reads: each probe touches one short line
 -- First complete line starting at or after byte `at`.
 local function lineAt(at)
  if at>0 then f:seek('set',at-1);f:read('*l') else f:seek('set',0) end
  local start=f:seek()
  return start,f:read('*l')
 end
 -- Headword for an exact phrase form, or nil.
 function self:lookup(form)
  local lo,hi=0,size
  while lo<hi do
   local start,line=lineAt(math.floor((lo+hi)/2))
   if not line then hi=math.floor((lo+hi)/2)
   else
    local key,head=line:match('^([^\t]*)\t(.*)$')
    if key==form then return head~='' and head or key
    elseif key<form then lo=start+#line+1
    else hi=math.floor((lo+hi)/2) end
   end
  end
 end
 -- Longest phrase (2-5 words) containing the word at byte `at` of `text`.
 -- Returns {form=matched words, headword=dictionary entry} or nil.
 function self:find(text,at)
  local tokens=M.tokens(text)
  local index
  for i,t in ipairs(tokens)do if at>=t.first and at<=t.last+1 then index=i;break end end
  if not index then return nil end
  for n=math.min(5,#tokens),2,-1 do
   for first=math.max(1,index-n+1),math.min(index,#tokens-n+1)do
    local last=first+n-1
    if tokens[first].segment==tokens[last].segment then
     local words={}
     for i=first,last do words[#words+1]=tokens[i].word end
     for _,form in ipairs(M.keys(words))do
      local head=self:lookup(form)
      if head then return {form=form,headword=head,text=text:sub(tokens[first].first,tokens[last].last)} end
     end
    end
   end
  end
 end
 function self:close()f:close()end
 return self
end

-- First short gloss from a dictionary definition (plain text): the text after WordNet's "—",
-- else the first line that reads like a sentence.
function M.gloss(definition)
 if type(definition)~='string' then return nil end
 local fallback
 for line in definition:gmatch('[^\n]+')do
  line=line:gsub('^%s+',''):gsub('%s+$','')
  local g=line:match('—%s*(.+)$') -- "v. 1. find, ascertain — establish after …"
  if g then return g end
  if not fallback and select(2,line:gsub('%a+',''))>=4 and not line:find('^[“"]') then fallback=line end
 end
 return fallback
end

return M

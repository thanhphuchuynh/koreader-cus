-- Reuse KOReader's vocabulary database and scheduler; own only reading snapshots.
local M={}
function M.maskSentence(sentence,word)
 if not sentence or not word or word=='' then return sentence end
 local lower,needle=sentence:lower(),word:lower()
 local chunks,from={},1
 while true do
  local first,last=lower:find(needle,from,true)
  if not first then chunks[#chunks+1]=sentence:sub(from);break end
  chunks[#chunks+1]=sentence:sub(from,first-1)
  local boundary=not lower:sub(first-1,first-1):match('%w') and not lower:sub(last+1,last+1):match('%w')
  chunks[#chunks+1]=boundary and '____' or sentence:sub(first,last)
  from=last+1
 end
 return table.concat(chunks)
end
function M.new()
 local DB=dofile('plugins/vocabbuilder.koplugin/db.lua')
 local SQL=require('lua-ljsqlite3/init')
 local UI=require('ui/uimanager')
 local Info=require('ui/widget/infomessage')
 local Popup=require('english_popup')
 local self={}
 local function connection(fn)
  local conn=SQL.open(DB.path)
  local ok,result=pcall(fn,conn)
  conn:close()
  if not ok then error(result) end
  return result
 end
 connection(function(conn)conn:exec([[CREATE TABLE IF NOT EXISTS english_word_details (
  word TEXT PRIMARY KEY, sentence TEXT NOT NULL, definition TEXT NOT NULL,
  dictionary TEXT NOT NULL, book_title TEXT NOT NULL
 );]])end)
 function self:isSaved(word)
  return connection(function(conn)
   local stmt=conn:prepare([[SELECT 1 FROM english_word_details e
    INNER JOIN vocabulary v ON v.word=e.word WHERE e.word=?;]])
   stmt:bind(word);local found=stmt:step()~=nil;stmt:close();return found
  end)
 end
 function self:save(word,entry)
  assert(type(word)=='string' and word:find('%S'),'No word to save')
  assert(type(entry)=='table' and type(entry.definition)=='string' and entry.definition:find('%S'),'No meaning to save')
  -- Existing words keep their review progress, even when a snapshot is refreshed.
  if not DB:hasWord(word) then DB:insertOrUpdate{
   word=word,book_title=entry.book_title or 'Dictionary lookup',time=os.time(),
   prev_context=entry.prev_context,next_context=entry.next_context,highlight=entry.highlight,
  }end
  connection(function(conn)
   local stmt=conn:prepare([[INSERT INTO english_word_details (word,sentence,definition,dictionary,book_title)
    VALUES (?,?,?,?,?) ON CONFLICT(word) DO UPDATE SET sentence=excluded.sentence,
    definition=excluded.definition,dictionary=excluded.dictionary,book_title=excluded.book_title;]])
   stmt:bind(word,entry.sentence or '',entry.definition,entry.dictionary or 'Offline dictionary',entry.book_title or 'Dictionary lookup')
   stmt:step();stmt:close()
  end)
  return true
 end
 local function info(text)UI:show(Info:new{text=text})end
 function self:showReview()
  local ok,items=pcall(connection,function(conn)
   local stmt=conn:prepare([[SELECT v.word,e.sentence,e.definition,e.dictionary,e.book_title,
    v.review_count,v.streak_count,v.due_time,v.highlight FROM vocabulary v
    INNER JOIN english_word_details e ON e.word=v.word
    ORDER BY v.due_time ASC,v.word ASC LIMIT 5;]])
   local result={}
   while true do
    local row=stmt:step();if not row then break end
    result[#result+1]={word=row[1],sentence=row[2],definition=row[3],dictionary=row[4],
     book_title=row[5],review_count=tonumber(row[6]),streak_count=tonumber(row[7]),due_time=tonumber(row[8]),highlight=row[9]}
   end
   stmt:close();return result
  end)
  if not ok then info('Could not open saved words. Try again.');return end
  local function show(index,revealed)
   local item=items[index]
   local title,text,subtitle
   if item then
    title=item.word;subtitle=index..'/'..#items..' · '..(item.book_title or 'Dictionary lookup')
    text=item.sentence~='' and item.sentence or 'No book sentence was available for this word.'
    if not revealed and item.sentence~='' then
     local masked=M.maskSentence(text,item.highlight or item.word)
     if masked~=text then text=masked;title='Recall the word' end
    end
    if revealed then text=text..'\n\n'..item.definition..'\n\n'..item.dictionary end
   else
    title=#items==0 and 'Saved words' or 'Review complete'
    text=#items==0 and 'Tap Save word in the dictionary to begin.'
      or #items==1 and '1 word reviewed.' or #items..' words reviewed.'
   end
   return Popup.show{title=title,subtitle=subtitle,text=text,buttons=function(close)
    if not item then return {{{text='Return to book',callback=close}}} end
    if not revealed then return {{{text='Reveal word & meaning',callback=function()close(true);show(index,true)end}}} end
    local graded=false
    local function grade(remembered)
     if graded then return end
     local success=pcall(function()
      local current=assert(DB:hasWord(item.word))
      DB:gotOrForgot(current,remembered);DB:batchUpdateItems({current})
     end)
     if not success then info('Could not save review progress. Try again.');return end
     graded=true;close(true);show(index+1,false)
    end
    return {{
     {text='Again',font_bold=false,callback=function()grade(false)end},
     {text='Remembered',font_bold=false,callback=function()grade(true)end},
    }}
   end}
  end
  return show(1,false)
 end
 return self
end
return M

-- Tests tab data: scan a folder of IELTS test books and report each one's saved progress.
local I=require('english_ielts')
local S=require('english_ielts_session')
local M={}
local cache={} -- path -> {key=size|mtime, t=parsed test}
local records={} -- path -> {mtime=sidecar mtime, rec=record}

local function load(path,io)
  local st=io.stat(path);if not st then return nil end
  local key=st.size..'|'..st.mtime
  local c=cache[path]
  if not c or c.key~=key then
    local ok,text=pcall(io.readJson,path)
    c={key=key,t=ok and type(text)=='string' and I.parse(text) or false}
    cache[path]=c
  end
  return c.t or nil
end

local function item(path,t,io)
  local ok2,at=pcall(io.recordMtime,path)
  at=ok2 and at or nil
  -- ponytail: keyed by sidecar mtime (1-2 s on FAT); add size if a fast re-save is ever missed
  local c=records[path]
  if not c or c.mtime~=at then
    local ok,rec=false,nil
    if at then ok,rec=pcall(io.record,path) end
    c={mtime=at,rec=ok and type(rec)=='table' and rec or nil}
    records[path]=c
  end
  local rec=c.rec
  local answers={}
  if rec and type(rec.answers)=='table' then for n,v in pairs(rec.answers) do if t.byNumber[n] then answers[n]=v end end end
  local r=rec and {mode=rec.mode,answers=answers,elapsed=rec.elapsed,finished=rec.finished}
  local s=S.new(t,{readSetting=function() return r end})
  local it={path=path,title=t.title or path:match('[^/]*$'):gsub('%.epub$',''),total=t.total,minutes=t.minutes,
    answered=s:answered(),active=at or 0,state='new'}
  local L=t.skill=='listening'
  it.folder=I.label(t);it.toeic=t.exam=='toeic';it.part=t.part
  it.meta=(it.toeic and ('Part %d · '):format(t.part) or L and 'Listening · ' or '')..('%d Q'):format(t.total)
    ..(t.minutes and (' · %d min'):format(t.minutes) or '')
    ..(not L and #(t.passages or {})>1 and (' · %d passages'):format(#t.passages) or '')
  if s:finished() then
    it.state='done';it.finishedAt=rec.finished_at or it.active;it.right=I.score(t,answers).right
    if it.toeic then it.percent=I.percent(it.right,t.total) else it.band,it.rough=I.band(it.right,t.total) end
  elseif rec then it.state='progress';it.remaining=not L and s:remaining(0) or nil end -- listening time is the audio's
  return it
end

function M.scan(dir,io)
  local items={}
  local ok,paths=pcall(io.list,dir)
  for _,path in ipairs(ok and type(paths)=='table' and paths or {}) do
    local t=load(path,io)
    if t then -- one malformed test must not hide the others
      local ok2,it=pcall(item,path,t,io)
      if ok2 then items[#items+1]=it end
    end
  end
  return items
end

-- count, finished, lastBand (IELTS: the latest finish), best (TOEIC: highest percent).
function M.summary(items)
  local s={count=#items,finished=0}
  local at=-1
  for _,i in ipairs(items) do
    if i.state=='done' then
      s.finished=s.finished+1
      if i.band and i.finishedAt>at then at=i.finishedAt;s.lastBand=i.band end
      if i.percent and (not s.best or i.percent>s.best) then s.best=i.percent end
    end
  end
  return s
end

-- The items whose folder is `name` ('IELTS Listening', 'IELTS Reading', 'TOEIC Part 5').
function M.inFolder(items,name)
  local out={}
  for _,i in ipairs(items) do if i.folder==name then out[#out+1]=i end end
  return out
end

function M.continueItem(items)
  local best
  for _,i in ipairs(items) do if i.state=='progress' and (not best or i.active>best.active) then best=i end end
  return best
end

local RANK={new=1,progress=2,done=3}
function M.ordered(items)
  local o={table.unpack(items)}
  table.sort(o,function(a,b) if a.state~=b.state then return RANK[a.state]<RANK[b.state] end return a.title<b.title end)
  return o
end

function M.defaultIO()
  local lfs=require('libs/libkoreader-lfs')
  return {
    list=function(dir)
      local out={}
      if lfs.attributes(dir,'mode')~='directory' then return out end
      for f in lfs.dir(dir) do if f:lower():match('%.epub$') then out[#out+1]=dir..'/'..f end end
      return out
    end,
    stat=function(p) local a=lfs.attributes(p);return a and {size=a.size,mtime=a.modification} end,
    readJson=function(p)
      local r=require('ffi/archiver').Reader:new()
      if not r:open(p) then return nil end
      local ok,data=pcall(function() for e in r:iterate() do if e.path=='META-INF/leaf-ielts.json' then break end end return r:extractToMemory('META-INF/leaf-ielts.json') end);r:close()
      return ok and data or nil
    end,
    record=function(p) return require('docsettings'):open(p):readSetting('leaf_ielts') end,
    recordMtime=function(p)
      local f=require('docsettings'):findSidecarFile(p);local a=f and lfs.attributes(f)
      return a and a.modification
    end,
  }
end

return M

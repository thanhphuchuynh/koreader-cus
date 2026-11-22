-- Tests tab data: scan a folder of IELTS test books and report each one's saved progress.
local I=require('english_ielts')
local S=require('english_ielts_session')
local M={}
local cache={} -- path..size..mtime -> parsed test (records are re-read every scan)

local function load(path,io)
  local st=io.stat(path);if not st then return nil end
  local key=path..st.size..st.mtime
  if cache[key]==nil then
    local ok,text=pcall(io.readJson,path)
    local t=ok and type(text)=='string' and I.parse(text) or false
    cache[key]=t
  end
  return cache[key] or nil
end

local function item(path,t,io)
  local ok,rec=pcall(io.record,path)
  if not ok or type(rec)~='table' then rec=nil end
  local answers={}
  if rec and type(rec.answers)=='table' then for n,v in pairs(rec.answers) do if t.byNumber[n] then answers[n]=v end end end
  local r=rec and {mode=rec.mode,answers=answers,elapsed=rec.elapsed,finished=rec.finished}
  local s=S.new(t,{readSetting=function() return r end})
  local ok2,at=pcall(io.recordMtime,path)
  local it={path=path,title=t.title or path:match('[^/]*$'):gsub('%.epub$',''),total=t.total,minutes=t.minutes,
    answered=s:answered(),active=ok2 and at or 0,state='new'}
  it.meta=('%d Q · %d min'):format(t.total,t.minutes)..(#t.passages>1 and (' · %d passages'):format(#t.passages) or '')
  if s:finished() then
    it.state='done';it.right=I.score(t,answers).right;it.band,it.rough=I.band(it.right,t.total)
  elseif rec then it.state='progress';it.remaining=s:remaining(0) end
  return it
end

function M.scan(dir,io)
  local items={}
  local ok,paths=pcall(io.list,dir)
  for _,path in ipairs(ok and type(paths)=='table' and paths or {}) do
    local t=load(path,io)
    if t then items[#items+1]=item(path,t,io) end
  end
  return items
end

function M.summary(items)
  local s={count=#items,finished=0}
  local at=-1
  for _,i in ipairs(items) do
    if i.state=='done' then s.finished=s.finished+1;if i.active>at then at=i.active;s.lastBand=i.band end end
  end
  return s
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
  local DS=require('docsettings')
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
      local ok,data=pcall(r.extractToMemory,r,'META-INF/leaf-ielts.json');r:close()
      return ok and data or nil
    end,
    record=function(p) return DS:open(p):readSetting('leaf_ielts') end,
    recordMtime=function(p)
      local f=DS:findSidecarFile(p);local a=f and lfs.attributes(f)
      return a and a.modification
    end,
  }
end

return M

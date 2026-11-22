-- IELTS reading session: answers, mode, timer. Persisted whole in doc_settings under "leaf_ielts".
local M={}
M.__index=M
local KEY='leaf_ielts'

function M.new(test,store)
  local s=setmetatable({test=test,store=store,startedAt=nil},M)
  local r=store:readSetting(KEY)
  s.rec=type(r)=='table' and r or {}
  s.rec.answers=s.rec.answers or {}
  s.rec.elapsed=s.rec.elapsed or 0
  return s
end

function M:save() self.store:saveSetting(KEY,self.rec) end
function M:mode() return self.rec.mode end
function M:setMode(m) self.rec.mode=m;self:save() end
function M:audioPos() return self.rec.audio_pos or 0 end -- listening: seconds into the audio
function M:setAudioPos(p) self.rec.audio_pos=p;self:save() end
function M:checkLeft() return self.rec.check_left end -- listening exam: seconds of check time left after the audio ended
function M:setCheckLeft(v) self.rec.check_left=v;self:save() end
function M:answer(n) return self.rec.answers[n] end
function M:setAnswer(n,v) self.rec.answers[n]=v;self:save() end

function M:answered()
  local c=0
  for n,v in pairs(self.rec.answers) do
    if type(v)=='string' then if v~='' then c=c+1 end
    elseif type(v)=='table' then
      local q=self.test.byNumber[n]
      c=c+math.min(#v,type(q and q.n)=='table' and #q.n or 1)
    end
  end
  return c
end

function M:start(now) if not self.startedAt then self.startedAt=now end end
function M:pause(now)
  if not self.startedAt then return end
  self.rec.elapsed=self.rec.elapsed+now-self.startedAt;self.startedAt=nil;self:save()
end

function M:elapsed(now) return self.rec.elapsed+(self.startedAt and now-self.startedAt or 0) end
function M:remaining(now)
  if self.rec.mode~='practice' then return nil end
  return math.max(0,self.test.minutes*60-self:elapsed(now))
end

function M:footer(now)
  local f=('Q %d/%d'):format(self:answered(),self.test.total)
  local r=self:remaining(now)
  if r then f=f..(' · %02d:%02d'):format(math.floor(r/60),r%60) end
  return f
end

function M:timeUpNoticed() return self.rec.timeUp==true end
function M:noteTimeUp() self.rec.timeUp=true;self:save() end
function M:finish() self.rec.finished=true;self:save() end
function M:finished() return self.rec.finished==true end
-- Test bars' height already added to the book's page margins (once per book, kept across Retry).
function M:marginsAdded() return self.rec.margins_added==true end
function M:setMarginsAdded() self.rec.margins_added=true;self:save() end
function M:reset()
  self.rec={mode=self.rec.mode,margins_added=self.rec.margins_added,answers={},elapsed=0}
  self.startedAt=nil;self:save()
end

return M

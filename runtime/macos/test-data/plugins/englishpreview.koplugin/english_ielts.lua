local M={}
local json=require('json')

-- Same quote/dash/whitespace folding as make-ielts-test.py norm(); byte-level because strings are UTF-8.
function M.fold(s)
  for from,to in pairs{['’']="'",['‘']="'",['“']='"',['”']='"',['–']='-',['—']='-',['\194\160']=' '} do s=s:gsub(from,to) end
  return (s:gsub('%s+',' '))
end
-- Edge punctuation is stripped except the apostrophe, so "farmers'" keeps its possessive.
local EDGE='[%s!-&(-/:-@%[%\\%]%^_`{-~]+'
function M.normalize(s) return (M.fold(s):lower():gsub('^'..EDGE,''):gsub(EDGE..'$','')) end

local function numbers(q) return type(q.n)=='table' and q.n or {q.n} end

function M.parse(text)
  local ok,t=pcall(json.decode,text)
  if not ok or type(t)~='table' then return nil,'invalid json' end
  if t.version~=1 then return nil,'unsupported version' end
  if type(t.questions)~='table' or #t.questions==0 then return nil,'no questions' end
  t.byNumber,t.total={},0
  for _,q in ipairs(t.questions) do
    local n=q.n
    if not (type(n)=='number' or type(n)=='table' and #n>0) then return nil,'question without n' end
    if (q.type=='choice' or q.type=='gap') and q.answer==nil or q.type=='multi' and type(q.answers)~='table' then return nil,'question without answer' end
    for _,n in ipairs(numbers(q)) do t.byNumber[n]=q;t.total=t.total+1 end
  end
  return t
end

function M.passageOf(t,n)
  for _,p in ipairs(t.passages or {}) do if n>=p.from and n<=p.to then return p end end
end

function M.overLimit(q,answer)
  local c=0;for _ in M.fold(answer):gmatch('%S+') do c=c+1 end
  return c>q.words
end

local function gapOk(q,a)
  a=M.normalize(a)
  if a==M.normalize(q.answer) then return true end
  for _,x in ipairs(q.accept or {}) do if a==M.normalize(x) then return true end end
end

function M.score(t,answers)
  local rows={}
  for _,q in ipairs(t.questions) do
    local ns=numbers(q)
    if q.type=='multi' then
      local picked,seen={},{}
      for _,l in ipairs(answers[ns[1]] or {}) do l=M.normalize(l);if not seen[l] then seen[l]=true;picked[#picked+1]=l end end
      local want={};for _,l in ipairs(q.answers) do want[M.normalize(l)]=true end
      for i,n in ipairs(ns) do
        local p=picked[i]
        rows[#rows+1]={n=n,answer=p and p:upper() or '',correct=q.answers[i],ok=p~=nil and want[p]==true}
      end
    else
      local a=answers[ns[1]] or ''
      local ok=q.type=='gap' and gapOk(q,a) or q.type=='choice' and M.normalize(a)==M.normalize(q.answer)
      rows[#rows+1]={n=ns[1],answer=a,correct=q.answer,ok=ok==true}
    end
  end
  table.sort(rows,function(a,b) return a.n<b.n end)
  local r={right=0,total=#rows,passages={},rows=rows}
  local by={}
  for _,p in ipairs(t.passages or {}) do by[p.n]={n=p.n,right=0,total=0};r.passages[#r.passages+1]=by[p.n] end
  for _,row in ipairs(rows) do
    if row.ok then r.right=r.right+1 end
    local p=M.passageOf(t,row.n);p=p and by[p.n]
    if p then p.total=p.total+1;if row.ok then p.right=p.right+1 end end
  end
  return r
end

local BANDS={{39,9},{37,8.5},{35,8},{33,7.5},{30,7},{27,6.5},{23,6},{19,5.5},{15,5},{13,4.5},{10,4},{8,3.5},{6,3},{4,2.5}}
function M.band(right,total)
  local rough=total~=40
  if rough then right=math.floor(right*40/total) end
  for _,b in ipairs(BANDS) do if right>=b[1] then return b[2],rough end end
  return 2,rough
end

return M

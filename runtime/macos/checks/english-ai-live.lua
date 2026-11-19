-- Explicit live smoke test: synthetic text only, free OpenRouter models only.
-- Supply a key through LEAF_TEST_API_KEY; never print or persist it.
require('setupkoenv')
-- Headless test identity only; keep the real native network stack.
package.loaded.device={model='Mac network smoke test'}
require('socketutil')
local json=require('json')
local socket=require('socket')
local http=require('socket.http')
local Client=dofile(arg[1])
local model=arg[2]
assert(model=='openrouter/free' or model:match(':free$'),'Only free model IDs are allowed')
local key=os.getenv('LEAF_TEST_API_KEY')
assert(type(key)=='string' and key:match('^sk%-or%-v1%-') and not key:find('%s'),'Supply an OpenRouter key privately')
local report={model=model,tests={}}
local original=http.request
local observed
http.request=function(request)
 local sink=request.sink
 local chunks={}
 request.sink=function(chunk,err)
  if chunk then chunks[#chunks+1]=chunk end
  return sink(chunk,err)
 end
 local a,b,c,d=original(request)
 observed.http_status=tonumber(b)
 local ok,data=pcall(json.decode,table.concat(chunks))
 if ok and type(data)=='table' then
  local choice=type(data.choices)=='table' and data.choices[1]
  if type(choice)=='table' then
   local known={stop=true,length=true,error=true,content_filter=true,tool_calls=true}
   observed.finish_reason=known[choice.finish_reason] and choice.finish_reason or nil
  end
  local error=type(data.error)=='table' and data.error or type(choice)=='table' and type(choice.error)=='table' and choice.error
  if error then observed.provider_error_code=type(error.code)=='number' and error.code or nil end
  if type(data.usage)=='table' then
   observed.completion_tokens=tonumber(data.usage.completion_tokens)
   local details=data.usage.completion_tokens_details
   observed.reasoning_tokens=type(details)=='table' and tonumber(details.reasoning_tokens) or nil
  end
 end
 return a,b,c,d
end
for _,mode in ipairs({'phrase','explain','translate'}) do
 observed={mode=mode}
 local started=socket.gettime()
 local ok,result=pcall(Client.request,{base_url='https://openrouter.ai/api/v1',model=model},key,'She decided to put off the meeting until Monday.',mode)
 observed.seconds=math.floor((socket.gettime()-started)*100)/100
 observed.success=ok and type(result)=='table' and type(result.text)=='string' and #result.text>0 or false
 if ok and type(result)=='table' then
  -- Only the client's fixed, sanitized errors; never raw transport/provider errors.
  observed.error=result.error
  observed.answer_bytes=type(result.text)=='string' and #result.text or nil
 else observed.error='Client raised an exception (details withheld).' end
 report.tests[#report.tests+1]=observed
 print(json.encode(observed));io.stdout:flush()
 if not observed.success then break end -- No automatic retry or model switching.
end
print('REPORT '..json.encode(report))

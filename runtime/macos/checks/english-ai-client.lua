local client=dofile(arg[1])
assert(client.validate{base_url='https://provider.example/v1',model='my-model'})
for _,url in ipairs({'http://provider.example/v1','https://user:secret@provider.example/v1','https://provider.example/v1?key=secret','https://provider.example/v1#x','https://127.0.0.1/v1','https://provider.example:99999/v1'}) do
 assert(not client.validate{base_url=url,model='model'},'unsafe URL accepted')
end
assert(not client.validate{base_url='https://provider.example/v1',model=' '})
assert(client.matchesHost('api.example.com',{'api.example.com'}))
assert(client.matchesHost('api.example.com',{'*.example.com'}))
assert(not client.matchesHost('other.example.com',{'api.example.com'}))
assert(not client.matchesHost('a.b.example.com',{'*.example.com'}))
assert(not client.matchesHost('example.com',{'*.example.com'}))
assert(not client.matchesHost('evil.com',{'*.com'}))
local json=require('json')
local captured,code,body,fail
local certificateName='provider.example'
package.loaded['socketutil']={set_timeout=function()end,reset_timeout=function()end}
package.loaded['ssl.https']={tcp=function(options)
 assert(options.verify=='peer' and options.cafile=='data/ca-bundle.crt','certificate-chain verification must be enabled')
 return function()return {
  connect=function()return 1 end,
  sock={close=function()end,getpeercertificate=function()return {
   extensions=function()return {['2.5.29.17']={dNSName={certificateName}}}end,
  }end},
 }end
end}
package.loaded['socket.http']={request=function(req)
 captured=req
 local connection=req.create()
 local connected=connection:connect('provider.example',443)
 if not connected then return nil,'TLS error' end
 if fail then error('transport failure with secret material') end
 local ok=req.sink(body);if not ok then return nil,'too large' end
 return 1,code
end}
local config={base_url='https://provider.example/v1',model='my-model'}
local key='test-key-not-a-real-secret'
code=200;body=json.encode{choices={{message={content='Buổi trưa.'}}}}
local result=client.request(config,key,'By noon, the road had narrowed.','translate')
assert(result.text=='Buổi trưa.')
assert(captured.url=='https://provider.example/v1/chat/completions' and captured.redirect==false)
assert(captured.headers.Authorization=='Bearer '..key)
local requestBody=captured.source();local payload=json.decode(requestBody)
assert(payload.messages[2].content=='By noon, the road had narrowed.' and payload.stream==false)
assert(not requestBody:find(key,1,true))
certificateName='wrong.example'
assert(client.request(config,key,'Sentence','translate').error:find('Connection failed'))
certificateName='provider.example'
code=401;assert(client.request(config,key,'Sentence','translate').error=='API key rejected.')
code=429;assert(client.request(config,key,'Sentence','translate').error:find('limit'))
code=200;body='invalid json';assert(client.request(config,key,'Sentence','translate').error:find('unsupported'))
body=json.encode{choices={{message={content=''}}}};assert(client.request(config,key,'Sentence','translate').error)
for _,invalid in ipairs({{choices=1},{choices={1}},{choices={{message=1}}}}) do
 body=json.encode(invalid);assert(client.request(config,key,'Sentence','translate').error)
end
body=string.rep('x',524289);assert(client.request(config,key,'Sentence','translate').error)
fail=true;local failure=client.request(config,key,'Sentence','translate');assert(failure.error and not failure.error:find('secret'))
assert(client.request(config,'','Sentence','translate').error)
assert(client.request(config,key,string.rep('x',16001),'translate').error)
print('PASS: config, TLS names, request shape, errors and response limits; no network')
fail=false;code=200;body=json.encode{choices={{message={content='Nghĩa theo ngữ cảnh.'}}}}
assert(client.request(config,key,'She gave up.','context','gave').text)
local contextual=json.decode(captured.source())
local passage=json.decode(contextual.messages[2].content)
assert(passage.word=='gave' and passage.sentence=='She gave up.','context request must separate word and sentence from instructions')
assert(contextual.messages[1].content:find('context',1,true))
assert(client.request(config,key,'put up with','phrase').text)
assert(json.decode(captured.source()).messages[1].content:find('idiom',1,true),'phrase mode must study expressions')
assert(client.request(config,key,'Sentence','context','').error,'empty contextual focus must be rejected')
assert(client.request(config,key,'Sentence','unknown').error)
print('PASS: explicit context and phrase prompts; structured word/context input; unknown modes rejected')

-- Free-model failures must remain errors and must never become cached answers.
code=200;fail=false
body=json.encode{error={code=429,message='private provider text'}}
assert(client.request(config,key,'put up with','phrase').error:find('rate limit'), 'HTTP-200 error envelope must retain rate-limit diagnosis')
body=json.encode{choices={{finish_reason='length',message={content='',reasoning='private reasoning'}}}}
local exhausted=client.request(config,key,'Sentence','explain')
assert(exhausted.error:find('token limit') and not exhausted.text,'reasoning-only token exhaustion needs an actionable error')
body=json.encode{choices={{finish_reason='length',message={content='Incomplete explanation'}}}}
assert(not client.request(config,key,'Sentence','explain').text,'truncated answers must not be shown or cached as complete')
body=json.encode{choices={{finish_reason='error',error={code=503,message='private provider text'},message={content='partial'}}}}
local unavailable=client.request(config,key,'Sentence','phrase')
assert(unavailable.error:find('unavailable') and not unavailable.text,'choice-level failures must reject partial text')
body=json.encode{choices={{finish_reason='content_filter',message={content='partial'}}}}
assert(client.request(config,key,'Sentence','explain').error:find('blocked'))
body=json.encode{choices={{message={content={{type='text',text='Nghĩa.'},{type='reasoning',text='private reasoning'}}}}}}
assert(client.request(config,key,'Sentence','phrase').text=='Nghĩa.','text parts must be supported without exposing reasoning')
body=json.encode{error={code=999,message='private provider text'}}
local unknown=client.request(config,key,'Sentence','explain')
assert(unknown.error and not unknown.error:find('private') and not unknown.text)
for _,status in ipairs({402,408,502,503}) do
 code=status;body='private provider text'
 local failed=client.request(config,key,'Sentence','phrase')
 assert(failed.error and not failed.error:find('private'))
end
print('PASS: free-model errors, token exhaustion, incomplete answers, text parts and safe error messages; no network')

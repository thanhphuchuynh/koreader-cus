local chooser={exclude_files={'^metadata%.calibre$'}}
package.loaded['ui/widget/filechooser']=chooser
local function visible(name)
 for _,pattern in ipairs(chooser.exclude_files)do if name:match(pattern)then return false end end
 return true
end
local patch=assert(arg[1])
assert(loadfile(patch))()
for _,process in ipairs({'pillowd','mesquite','wifilocker','framework','otaupd','reader_helper'})do
 for _,suffix in ipairs({'.txt','.tgz','.txt.asc','.tgz.asc'})do
  assert(not visible(process..'_123_001-juno_cava_bellatrix-455678_crash_Sep_02_10.27.19_2026'..suffix),'Kindle diagnostic must be hidden')
 end
end
for _,name in ipairs({'crash.log','reader.LOG','reader.log.1','reader.log.2026-10-27','reader.log.old','reader.log.gz','process.core','process.dmp','._book.epub'})do
 assert(not visible(name),'Diagnostic or macOS metadata must stay out of Library: '..name)
end
for _,name in ipairs({'My Clippings.txt','Educated.epub','notes.txt','crash-course.txt','chapter_1_the_crash_essay.txt','The Crash.epub','pillowd_notes.txt','book.pdf'})do
 assert(visible(name),'Books and user text must stay visible: '..name)
end
assert(not visible('metadata.calibre'),'Native exclusions must remain')
print('PASS: crash diagnostics hidden; ebooks, text notes, clippings and native filters preserved')

-- Diagnostics can be readable text; exclude them even when "show unsupported" is on.
local FileChooser=require('ui/widget/filechooser')
local exclusions={
 '^%._', -- macOS resource-fork metadata, never book contents
 '%.[lL][oO][gG]$',
 '%.[lL][oO][gG]%.%d[%d%.%-]*$',
 '%.[lL][oO][gG]%.[oO][lL][dD]$',
 '%.[lL][oO][gG]%.[gG][zZ]$',
 '%.[cC][oO][rR][eE]$',
 '%.[dD][mM][pP]$',
}
-- Match the Kindle PID + numeric build prefix, not arbitrary books about crashes.
for _,suffix in ipairs({'%.txt$','%.tgz$','%.txt%.asc$','%.tgz%.asc$'})do
 exclusions[#exclusions+1]='^[%w_%-]+_%d+_%d+%-[%w_%-]+_crash_.+'..suffix
end
for _,pattern in ipairs(exclusions)do
 table.insert(FileChooser.exclude_files,pattern)
end

-- Presentation only: keep KOReader's paths, version and data identity intact.
local FileManager = require('apps/filemanager/filemanager')
FileManager.title = 'Leaf'
local info = require('ui/elements/common_info_menu_table')
info.about.text = 'About Leaf'
info.about.callback = function()
    require('ui/uimanager'):show(require('ui/widget/infomessage'):new{
        text = 'Leaf\n\nRead. Understand. Remember.\n\nPowered by KOReader '
            .. require('version'):getCurrentRevision()
            .. '\n\nLicensed under Affero GPL v3. All dependencies are free software.\n\nhttps://koreader.rocks',
        icon = 'koreader',
    })
end

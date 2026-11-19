from calibre.devices.scanner import DeviceScanner
from calibre_extensions import libmtp
from pathlib import Path
import json
out=Path('/Users/tphuc/coding/kindle/runtime/kindle/device-audit')
s=DeviceScanner();s.scan()
items=[d for d in s.devices if d.vendor_id==0x1949]
if len(items)!=1:raise SystemExit('Expected exactly one Amazon USB device')
d=items[0]
dev=libmtp.Device(d.busnum,d.devnum,d.vendor_id,d.product_id,d.manufacturer or "",d.product or "",d.serial or "")
report={'model':dev.model_name,'version':dev.device_version,'storage':dev.storage_info,'root_entries':[]}
for storage in dev.storage_info:
 entries,errors=dev.get_filesystem(storage['id'],lambda entry,level:False)
 report['root_entries']+=entries
 report['errors']=[{'code':e[0],'message':str(e[1])} for e in errors]
(out/'inventory-private.json').write_text(json.dumps(report,indent=2))
summary={
 'model':report['model'],'version':report['version'],
 'storage':[{'capacity':x.get('capacity'),'free':x.get('freespace_bytes'),'name':x.get('name')} for x in report['storage']],
 'root_directories':[x['name'] for x in report['root_entries'] if x.get('is_folder')],
 'root_file_count':sum(not x.get('is_folder') for x in report['root_entries']),
 'error_count':len(report.get('errors',[])),
}
(out/'summary.json').write_text(json.dumps(summary,indent=2))
print('Device inventory saved')

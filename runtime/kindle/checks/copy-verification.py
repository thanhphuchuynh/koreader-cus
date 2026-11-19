"""Exercise deployment verification without importing or running device operations."""
from pathlib import Path
import ast, hashlib, tempfile
source=Path(__file__).resolve().parents[1]/'install-custom.py'
tree=ast.parse(source.read_text())
functions=ast.Module(body=[node for node in tree.body if isinstance(node,ast.FunctionDef)],type_ignores=[])
scope={'hashlib':hashlib}
exec(compile(functions,str(source),'exec'),scope)
with tempfile.TemporaryDirectory() as directory:
    path=Path(directory)
    (path/'reader.lua').write_text('reader')
    expected=scope['manifest'](path)
    (path/'._reader.lua').write_bytes(b'\x00\x05\x16\x07metadata')
    scope['verify_copy'](path,expected)
    assert not (path/'._reader.lua').exists()
    for name,content in [('extra.txt',b'unexpected'),('._bad',b'not metadata')]:
        extra=path/name;extra.write_bytes(content)
        try:scope['verify_copy'](path,expected)
        except AssertionError:pass
        else:raise AssertionError('Unexpected files accepted')
        assert extra.exists();extra.unlink()
    (path/'reader.lua').write_text('broken')
    try:scope['verify_copy'](path,expected)
    except AssertionError:pass
    else:raise AssertionError('Changed program bytes accepted')
print('PASS: verified bytes required; only recognized extra AppleDouble files removed')

"""Run portable Lua checks using the system Lua 5.4 shared library.

No game code or Kenshi DLL is loaded. Each test suite gets its own Lua state.
"""
import ctypes as C
import ctypes.util
import sys
from pathlib import Path

L = C.CDLL(ctypes.util.find_library('lua5.4') or 'liblua5.4.so.0')
L.luaL_newstate.restype = C.c_void_p
L.luaL_openlibs.argtypes = [C.c_void_p]
L.luaL_loadbufferx.argtypes = [C.c_void_p, C.c_char_p, C.c_size_t, C.c_char_p, C.c_char_p]
L.lua_pcallk.argtypes = [C.c_void_p, C.c_int, C.c_int, C.c_int, C.c_longlong, C.c_void_p]
L.lua_tolstring.argtypes = [C.c_void_p, C.c_int, C.POINTER(C.c_size_t)]
L.lua_tolstring.restype = C.c_char_p
L.lua_close.argtypes = [C.c_void_p]

def run(code, name, execute=True):
    state = L.luaL_newstate()
    try:
        L.luaL_openlibs(state)
        rc = L.luaL_loadbufferx(state, code, len(code), str(name).encode(), None)
        if not rc and execute:
            rc = L.lua_pcallk(state, 0, -1, 0, 0, None)
        if rc:
            raise RuntimeError(L.lua_tolstring(state, -1, None).decode())
    finally:
        L.lua_close(state)

if __name__ == '__main__':
    import json
    root = Path(__file__).resolve().parents[2]
    files = list((root/'KenshiShop/scripts').rglob('*.lua'))
    for path in files:
        run(path.read_bytes(), path, False)
    print('Lua syntax OK:', len(files), 'files', flush=True)
    suites = sys.argv[1:] or ['runtime', 'controller', 'duty', 'service86', 'native87', 'native88', 'post89']
    for name in suites:
        path = root/'Development/tests'/f'{name}.lua'
        code = ('arg={' + json.dumps(str(root/'KenshiShop/scripts')) + '}\n').encode() + path.read_bytes()
        run(code, name)

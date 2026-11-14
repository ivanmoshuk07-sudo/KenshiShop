-- KenshiShop 0.3.0-alpha.16: expose console diagnostics before starting Core.
-- No keyDown handler, no custom UI; commands run in KenshiLua's existing console.
local Log = require('Diagnostics')
local consoleOK, Console = pcall(require, 'KenshiLuaConsole')
if consoleOK then
    local ok, err = pcall(Console.start)
    if not ok then Log.error('CONSOLE_START_ERROR '..tostring(err)) end
else
    Log.error('CONSOLE_REQUIRE_ERROR '..tostring(Console))
end
local coreOK, Core = pcall(require, 'Core')
if not coreOK then
    Log.error('CORE_REQUIRE_ERROR '..tostring(Core))
    if consoleOK then Console.setCoreStatus('require failed',Core) end
else
    local started, err = pcall(Core.start)
    if not started then
        Log.error('CORE_START_ERROR '..tostring(err))
        if consoleOK then Console.setCoreStatus('start failed',err) end
    elseif consoleOK then
        Console.setCoreStatus('started')
    end
end

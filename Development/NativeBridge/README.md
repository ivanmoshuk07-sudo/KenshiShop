# KenshiShopNative — узлы через штатную фабрику

Небольшое дополнение для KenshiLua SDK ABI v1, GPL-3.0. DLL загружается через `package.loadlib` из `KenshiShop/native/`. Заменять KenshiLua.dll/KenshiLib.dll и править RE_Kenshi.json не требуется.

`createNode` вызывает экспортированный `RootObjectFactory::createLocationNode` из уже загруженной KenshiLib.dll и передаёт результат штатному SDK `pushObject` как `RootObject`. В предоставленном EXE RTTI подтверждает: LocationNode → RootObject → RootObjectBase, оба смещения базы — 0. Координаты остаются локальными. Числовые RVA, чтение/запись по смещениям и игровые хуки не используются. Все действия NPC исполняет родной GOAP. График и смена узла задаются Lua только при изменении роли/смены/30-минутного интервала.

Поддержаны прежние шаблоны узлов 0/1/2; Lua проверяет `is node` перед вызовом. SDK заголовок скопирован без изменений из Genpretz/KenshiLua, commit `53a7e4d1dc544a6b51872d03990f97af5dded94e`. В предоставленной KenshiLua.dll есть `KenshiLua_GetApi`, размер таблицы ABI v1 — 328 байт; этот размер дополнительно проверяется компилятором.

Сборка в x64 Native Tools Command Prompt:

```
cl /nologo /LD /MT /EHsc /std:c++17 /O2 /W4 /WX /DNDEBUG Development\NativeBridge\KenshiShopNative.cpp /link /OUT:KenshiShop\native\KenshiShopNative.dll
```

Нужна существующая папка вывода. Используется статический CRT; готовая DLL импортирует только KERNEL32.dll. Исходники и полный SDK-заголовок включены в FULL.zip, лицензия — в LICENSE.

Windows workflow `.github/workflows/native-bridge.yml` дополнительно собирает отдельные тестовые DLL: минимальную таблицу SDK и фабрику с исходной C++-сигнатурой. Probe проверяет загрузку модуля, точное имя экспорта, передачу this/Vector3/Quaternion/std::string, тип обёртки и отклонение неверных аргументов. Тестовые DLL не попадают в мод. Проверка не исполняет и не имитирует Kenshi AI.

Готовая DLL собрана и проверена запуском Actions `43674084623` из commit `372c46904c8391dfb32e30d3f8e933bbf0d2aca7`. Изменения README после сборки не меняют код DLL. Проверка в настоящей игре всё ещё обязательна; отсутствие моста или ошибка API сохраняют прежний пакет/посты и явно записываются в лог.

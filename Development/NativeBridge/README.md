# KenshiShopNative — SDK-модуль, GPL-3.0

Модуль загружается `package.loadlib` из `KenshiShop/native`. Используются уже установленные KenshiLua SDK ABI v1 и KenshiLib. Подмена оригинальных DLL и изменение RE_Kenshi.json не требуются.

`createNode` сохраняет реализацию alpha.89: вызов публичного RootObjectFactory.createLocationNode и обёртка результата через SDK как RootObject. Начиная с alpha.91, `protectLimbs` / `unprotectLimbs` добавляют адресную регистрацию MedicalSystem 14 кастомных рас. Точные stringID проверяет Lua, C++ дополнительно проверяет белый список. MedicalSystem.amputate/crushLimb блокируются только для зарегистрированных объектов и четырёх допустимых enum конечностей; остальные вызовы передаются исходной функции. Деструктор и notifyRaceChange удаляют регистрацию. Нативные перехватчики работают без Lua, под SRW-блокировкой; модуль закреплён в процессе, реестр живёт до выхода процесса. Не изменяются здоровье, медицинские части, повреждения или ИИ.

Все игровые функции берутся через GetProcAddress из KenshiLib.dll; их настоящие адреса — через GetRealAddress. Перехватчики устанавливает KenshiLib.AddHook (MinHookEx). Смещения полей/игровые RVA не зашиты. Дополнительные API при старом DLL возвращают явную ошибку, а не успех.

SDK-заголовок из Genpretz/KenshiLua, commit `53a7e4d1dc544a6b51872d03990f97af5dded94e`, ABI v1 — 328 байт. Сборка из x64 Native Tools Command Prompt (папка вывода должна существовать):

```
cl /nologo /LD /MT /EHsc /std:c++17 /O2 /W4 /WX /DNDEBUG Development\NativeBridge\KenshiShopNative.cpp /link /OUT:KenshiShop\native\KenshiShopNative.dll
```

Используется статический CRT; DLL импортирует только KERNEL32.dll. Workflow `.github/workflows/native-bridge.yml` выполняет Windows ABI probe с отдельными тестовыми KenshiLua/KenshiLib DLL. Он проверяет исходную фабрику узлов, новое ограничение по расам, подавление четырёх конечностей, передачу обычных вызовов и очистку реестра. Тестовые DLL в мод не попадают; игровое поведение эти тесты не имитируют и не сертифицируют.

Текущая DLL собрана из commit `41784e47d66e85e274613300ad9f869c591a7da5`, Windows run `43729190574`. Хеши DLL и исходников: Development/references/native_no_sever91.json. Реальный игровой тест обязателен. Исторические проверки data89/data90 относятся к прежним бинарным файлам; текущая проверка — data91.py.

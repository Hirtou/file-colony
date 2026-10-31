# Правила для Claude

- Отвечай коротко.
- Делай только то, что просят.
- Правь файлы точечно (Edit), не переписывай целиком.
- Не читай весь проект без нужды.
- В конце ответа одной строкой пиши, как запустить.
- Реальные файлы диска НЕ читать и НЕ удалять (дерево папок только фейковое).
- Не добавлять анимации, графику, клики, удаление, пока не попросят.

# Проект
2D игра, Godot 4.7 (GDScript), вид сверху. Файловая система как мир:
диск = планета, папка с подпапками = город, папка только с файлами = дом, файл = житель (кружок).

# Godot
- GODOT = C:\Godot\godot.exe (редактор/игра, Godot 4.7.2)
- GODOT_CONSOLE = C:\Godot\godot_console.exe (для команд, печатает вывод в консоль)
- GUT 9.7.1 в addons/gut (для Godot 4.7)

# Команды
- Один раз: `setup.bat` (распаковывает GUT, ставит субагента в .claude/agents)
- Тесты (без окна): `run_tests.bat`
- Скриншот: `screenshot.bat` -> screenshots/latest.png
- Игра: `C:\Godot\godot.exe --path .`
- Проверка всего: субагент `tester`

# Файлы
- scripts/game.gd — автозагрузка Game: режим (мои диски / песочница), настройки, кэш миров, буфер
- scripts/menu.gd — главное меню (2D-планета: scripts/planet.gd + shaders/planet.gdshader)
- scripts/space.gd — космос в 3D: камера-орбита, солнце, перелёт между дисками; scripts/globe.gd + shaders/globe.gdshader — 3D-планета
- scripts/sun.gd, scripts/stars.gd — далёкое солнце и звёзды (параллакс)
- scripts/fake_tree.gd — FakeTree.generate(seed) -> дерево Folder (выдуманное)
- scripts/city_sites.gd — где на 3D-планете стоят города и что вокруг (океан, сухость)
- scripts/world_layout.gd — карта города (build_city): деревня, дома, мебель, мастерские, озёра, река, океан, поля, мостки
- scripts/world_map.gd — рисование карты, посёлки, удаление/вставка файлов
- scripts/residents.gd — жители посёлка (дела, болтовня, сон); scripts/pawn.gd — человечек
- scripts/hunt.gd — удаление: киллеры, погоня, выстрел
- scripts/continent.gd + continent_ui.gd — материк и его интерфейс; scripts/family_tree.gd — семейное древо (родословная сверху вниз)
- scripts/i18n.gd — языки RU/EN: словарь EN, I18n.t("русская строка") для строк с %s/%d
- scripts/tiles.gd — текстуры и TileSet; tools/make_textures.py — генератор текстур
- старое (первый этап, держат тесты test_map): main.gd, map_layout.gd, map_view.gd, scenes/main.tscn
- tests/ — тесты GUT; export_presets.cfg — сборка build/FileColony.exe

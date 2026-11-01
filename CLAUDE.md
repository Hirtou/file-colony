# Правила для Claude

- Отвечай коротко.
- Делай только то, что просят.
- Правь файлы точечно (Edit), не переписывай целиком.
- Не читай весь проект без нужды.
- В конце ответа одной строкой пиши, как запустить.
- «Мои диски» читают с настоящих дисков ТОЛЬКО имена и размеры (scripts/disk_scan.gd). Файлы НЕ читать, НЕ менять и НЕ удалять; открыть (не программу) или показать в проводнике — только по клику игрока. Скриншоты и тесты — на выдуманных дисках.
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
- scripts/menu.gd — главное меню на 3D-фоне (Globe + небо космоса); scripts/planet.gd — старая 2D-планета (форматы размеров)
- scripts/space.gd — космос в 3D: камера-орбита, солнце, перелёт между дисками; scripts/globe.gd + shaders/globe.gdshader — 3D-планета
- scripts/sun.gd, scripts/stars.gd — далёкое солнце и звёзды (параллакс)
- scripts/fake_tree.gd — FakeTree.generate(seed) -> дерево Folder (выдуманное); scripts/disk_scan.gd — DiskScan.scan(диск) -> такое же дерево с настоящего диска
- scripts/trash_view.gd — окно «Корзина» (Game.trash: удалённые жители, вернуть/очистить)
- scripts/city_sites.gd — где на 3D-планете стоят города и что вокруг (океан, сухость)
- scripts/world_layout.gd — карта города (build_city): деревня, дома, мебель, мастерские, озёра, река, океан, поля, мостки
- scripts/world_map.gd — рисование карты, посёлки, удаление/вставка файлов
- scripts/residents.gd — жители посёлка (дела, болтовня, сон); scripts/pawn.gd — человечек
- scripts/wildlife.gd — круги от рыб, дым кузницы; shaders/terrain.gdshader — мягкая земля и вода; shaders/cloud_shadows.gdshader — тени облаков
- scripts/hunt.gd — удаление: киллеры, погоня, выстрел
- scripts/continent.gd + continent_ui.gd — материк и его интерфейс (тема make_theme, мини-карта, легенда); scripts/family_tree.gd — семейное древо (родословная сверху вниз)
- scripts/stats_view.gd — окно «Статистика города» (I); scripts/help_view.gd — справка по клавишам (F1)
- scripts/weather.gd — дождь над картой (сила — continent.rain_of); scripts/sfx.gd — звуки из чисел (дождь, выстрел, копирование, вставка)
- scripts/i18n.gd — языки RU/EN: словарь EN, I18n.t("русская строка") для строк с %s/%d
- scripts/tiles.gd — текстуры и TileSet; tools/make_textures.py — генератор текстур
- старое (первый этап, держат тесты test_map): main.gd, map_layout.gd, map_view.gd, scenes/main.tscn
- tests/ — тесты GUT; export_presets.cfg — сборка build/FileColony.exe

class_name I18n
extends RefCounted
## Языки игры: русский (строки в коде) и английский (словарь EN: русская строка -> английская).
## Простые надписи кнопок и меток Godot переводит сам, строки с %s/%d — через I18n.t() до подстановки.

const LANGS := ["ru", "en"]
const LANG_NAMES := ["Русский", "English"]

static var _lang := "ru"
static var _tr: Translation

## Включить язык: "ru", "en" или "" — по языку системы.
static func use(code: String) -> void:
	if code == "":
		code = "ru" if OS.get_locale_language() in ["ru", "uk", "be", "kk", "ky"] else "en"
	_lang = code
	if _tr == null:
		_tr = Translation.new()
		_tr.locale = "en"
		for k in EN:
			_tr.add_message(k, EN[k])
	# в русском перевода нет совсем (иначе Godot подставит английский как запасной)
	TranslationServer.remove_translation(_tr)
	if code == "en":
		TranslationServer.add_translation(_tr)
	TranslationServer.set_locale(code)

static func lang() -> String:
	return _lang

static func en() -> bool:
	return _lang == "en"

## Перевод строки (ключ — русский текст); нет в словаре — как есть.
static func t(s: String) -> String:
	if _lang == "ru":
		return s
	return EN.get(s, s)

const EN := {
	# меню
	"Файловая колония": "File Colony",
	"ФАЙЛОВАЯ\nКОЛОНИЯ": "FILE\nCOLONY",
	"твои папки — города, файлы — жители": "your folders are towns, your files are colonists",
	"Мои диски": "My disks",
	"Песочница": "Sandbox",
	"Настройки": "Settings",
	"Выход": "Quit",
	"Все диски, папки и файлы выдуманные — настоящие файлы не читаются и не меняются.": "All disks, folders and files are made up — no real files are read or changed.",
	"Выдуманный мир по зерну: одно и то же зерно — один и тот же мир. Зерно — число или любое слово.": "A made-up world from a seed: the same seed always gives the same world. A seed is a number or any word.",
	"Зерно:": "Seed:",
	"Случайное": "Random",
	"Планет:": "Planets:",
	"Создать мир": "Create world",
	"Планеты: ": "Planets: ",
	"Полный экран": "Fullscreen",
	"Вертикальная синхронизация": "V-Sync",
	"Показывать FPS": "Show FPS",
	"Смена дня и ночи": "Day and night cycle",
	"Тени от домов и деревьев": "Shadows of houses and trees",
	"Скорость камеры": "Camera speed",
	"Музыка": "Music",
	"Скорость времени": "Time speed",
	"Готово": "Done",
	# космос
	"Меню": "Menu",
	"Войти": "Land",
	"Диск C:": "Disk C:",
	"Посадка на «%s»…": "Landing on “%s”…",
	"Перетаскивание — крутить камеру · колёсико — ближе/дальше · ←/→ — другой диск": "Drag — rotate the camera · wheel — zoom · ←/→ — another disk",
	"Б": "B", "КБ": "KB", "МБ": "MB", "ГБ": "GB", "ТБ": "TB",
	# материк
	"Планета %s · %s": "Planet %s · %s",
	"Строим мир «%s»…": "Building world “%s”…",
	"Космос": "Space",
	"Назад": "Back",
	"Семейное древо": "Family tree",
	"Родня выбранного файла или папки  (T)": "Relatives of the selected file or folder  (T)",
	"День %d · %02d:%02d · %s": "Day %d · %02d:%02d · %s",
	"утро": "morning", "день": "day", "вечер": "evening", "ночь": "night",
	"Поиск файла или папки…  (Ctrl+F)": "Search for a file or folder…  (Ctrl+F)",
	"Все типы": "All types",
	"Любой размер": "Any size",
	"Все города": "All towns",
	"до 1 МБ": "up to 1 MB", "1–100 МБ": "1–100 MB", "100 МБ–1 ГБ": "100 MB–1 GB", "больше 1 ГБ": "over 1 GB",
	"Ничего не нашлось": "Nothing found",
	"Найдено: %d%s — подсвечены на карте": "Found: %d%s — highlighted on the map",
	" (показаны первые %d)": " (showing first %d)",
	"Одежда = тип файла\nклик — найти на карте": "Clothes = file type\nclick to find on the map",
	"Показать на карте все файлы типа «%s»": "Show all “%s” files on the map",
	"В буфере (Ctrl+V — вставить в дом):": "In clipboard (Ctrl+V — paste into a house):",
	"Вырезан (Ctrl+V — переселить в дом):": "Cut (Ctrl+V — move into a house):",
	"Жители дома (%d):": "Residents (%d):",
	"Имя": "Name", "Тип": "Type", "Файлов": "Files", "Размер": "Size", "Глубина": "Depth",
	"Дом": "House", "Семья": "Family", "Сейчас": "Now", "На улице": "Outside",
	"файл (%s)": "file (%s)",
	"город": "town", "дом": "house", "хижина": "hut", "хижина (пустая папка)": "hut (empty folder)",
	"дом «%s»": "house “%s”",
	"%s «%s»": "%s of “%s”",
	"%s «%s», детей %d": "%s of “%s”, %d children",
	"%d из %d": "%d of %d",
	# типы файлов
	"картинка": "image", "документ": "document", "видео": "video", "музыка": "music", "архив": "archive",
	"программа": "program", "другое": "other", "таблица": "spreadsheet", "презентация": "slides",
	"код": "code", "3D-модель": "3D model", "шрифт": "font", "книга": "book", "сохранение": "save",
	" - копия": " - Copy",
	# меню по правой кнопке и сообщения
	"Копировать": "Copy",
	"Вырезать (переселить)": "Cut (move)",
	"Переселить «%s» в этот дом": "Move “%s” into this house",
	"Вставить «%s» в этот дом": "Paste “%s” into this house",
	"Переселить «%s» сюда": "Move “%s” here",
	"Вставить «%s» сюда": "Paste “%s” here",
	"Вставить (буфер пуст)": "Paste (clipboard is empty)",
	"Удалить": "Delete",
	"Открыть": "Open",
	"Подсветка типов выключена": "Type highlight is off",
	"Файлов типа «%s» на этой планете нет": "No “%s” files on this planet",
	"«%s»: %d файлов в %d домах — ищи метки на карте": "“%s”: %d files in %d houses — look for the markers on the map",
	"Скопировано: %s": "Copied: %s",
	"Вырезано: %s — выбери дом и вставь (Ctrl+V)": "Cut: %s — pick a house and paste (Ctrl+V)",
	"Буфер пуст — сначала скопируйте файл": "Clipboard is empty — copy a file first",
	"Вставлять можно только в дом": "You can only paste into a house",
	"Он и так живёт в этом доме": "It already lives in this house",
	"Нельзя: за ним уже пришли киллеры": "Too late: the killers are already after it",
	"«%s» переезжает в «%s»": "“%s” is moving to “%s”",
	"Вставлено в «%s»: %s": "Pasted into “%s”: %s",
	"За «%s» выехали киллеры…": "Killers are on their way to “%s”…",
	"Удалено: %s": "Deleted: %s",
	"Файл удалён": "File deleted",
	# выбор города и карта города
	"◀ К планетам": "◀ To planets",
	"жителей: %d": "residents: %d",
	"Выбери город — клик по нему · перетаскивание — крутить планету · Esc / ПКМ — назад": "Pick a town — click it · drag — rotate the planet · Esc / right click — back",
	"Посадка в город «%s»…": "Landing in “%s”…",
	"Строим город «%s»…": "Building town “%s”…",
	"«%s» живёт в другом городе — «%s». Вернись на планету и выбери его.": "“%s” lives in another town — “%s”. Go back to the planet and pick it.",
	"Переселять можно только в пределах одного города": "Files can only move within one town",
	"Кузница": "Smithy", "Столярная": "Carpentry", "Лавка": "Shop", "Пекарня": "Bakery", "Рынок": "Market",
	"идёт в кузницу": "going to the smithy",
	"идёт в столярную мастерскую": "going to the carpentry",
	"идёт в лавку": "going to the shop",
	"идёт в пекарню": "going to the bakery",
	"раздувает горн": "working the forge bellows",
	"куёт подкову": "forging a horseshoe",
	"остужает железо в бочке": "quenching iron in a barrel",
	"строгает доски": "planing boards",
	"колет дрова": "chopping firewood",
	"мастерит табурет": "making a stool",
	"выбирает товар": "browsing the goods",
	"расплачивается у прилавка": "paying at the counter",
	"покупает квас": "buying kvass",
	"печёт хлеб": "baking bread",
	"месит тесто": "kneading dough",
	"таскает мешки с мукой": "hauling flour sacks",
	"торгуется за овощи": "haggling over vegetables",
	"приценивается к зельям": "pricing potions",
	"покупает яблоки": "buying apples",
	"идёт в поле": "going to the field",
	"пропалывает грядки": "weeding the beds",
	"собирает урожай": "harvesting",
	"поливает капусту": "watering the cabbage",
	"копает картошку": "digging potatoes",
	"идёт на рыбалку к воде": "going fishing",
	"идёт на рыбалку к океану": "going fishing at the ocean",
	"рыбачит с мостков": "fishing from the pier",
	"закидывает удочку с берега": "casting a line from the shore",
	# жители
	"дома": "at home",
	"идёт гулять": "going for a walk",
	"гуляет по улице": "walking down the street",
	"идёт домой": "going home",
	"за ним пришли киллеры": "the killers came for it",
	"идёт к колодцу": "going to the well",
	"набирает воду у колодца": "drawing water at the well",
	"идёт на рынок": "going to the market",
	"торгуется у лавки с овощами": "haggling at the vegetable stall",
	"разглядывает зелья в лавке": "browsing potions at the stall",
	"идёт в гости к «%s»": "visiting “%s”",
	"стучится к соседям «%s»": "knocking on the door of “%s”",
	"спит": "sleeping",
	"хлопочет по дому": "doing chores",
	"ходит по дому": "walking around the house",
	"переезжает в «%s» с вещами": "moving to “%s” with its things",
	"спешит домой — темнеет": "hurrying home — it's getting dark",
	"болтает с %s": "chatting with %s",
	"стоит на улице": "standing outside",
	"идёт на площадь": "going to the square",
	"отдыхает на площади": "resting in the square",
	"идёт прогуляться": "going for a stroll",
	"в доме (за «+N»)": "indoors (in “+N”)",
	"сидит за столом": "sitting at the table",
	"греется у очага": "warming up by the hearth",
	"читает книгу у полки": "reading by the bookshelf",
	"роется в сундуке": "rummaging in the chest",
	"выбирает одежду в шкафу": "picking clothes from the wardrobe",
	"поливает цветок": "watering a plant",
	"заправляет кровать": "making the bed",
	"накрывает на стол": "setting the table",
	"черпает воду из бочки": "scooping water from the barrel",
	"разбирает ящик": "unpacking a crate",
	"убегает от киллеров": "running from the killers",
	"бежит прятаться": "running to hide",
	"затаился в углу дома": "hiding in a corner of the house",
	"попался киллерам": "caught by the killers",
	"удалён": "deleted",
	# семейное древо
	"дедушка": "grandfather", "бабушка": "grandmother", "отец": "father", "мать": "mother",
	"брат": "brother", "сестра": "sister", "сын": "son", "дочь": "daughter",
	"родоначальник": "founder of the family",
	"◀ Весь род": "◀ Whole family",
	"Снова показать всё дерево диска  (Backspace)": "Show the whole disk tree again  (Backspace)",
	"Найти в роду…  (Ctrl+F)": "Find in the family…  (Ctrl+F)",
	"Свернуть всё": "Collapse all",
	"Развернуть всё": "Expand all",
	"Свёрнутые ветки раскрываются «+» под папкой": "Collapsed branches open with “+” under a folder",
	"Всё дерево в кадр": "Fit whole tree",
	"Закрыть  (Esc)": "Close  (Esc)",
	"Колёсико — приблизить · перетаскивание — двигать · клик — выбрать · «−/+» — свернуть ветку · ↑ родитель · ↓ дети · ←/→ братья и сёстры · Enter — на карту": "Wheel — zoom · drag — pan · click — select · “−/+” — fold a branch · ↑ parent · ↓ children · ←/→ siblings · Enter — show on map",
	"Показать на карте": "Show on map",
	"Только эта ветка": "This branch only",
	"Показать дерево только этой папки": "Show the tree of this folder only",
	"↑ К родителю": "↑ To parent",
	"папка · детей %d": "folder · %d children",
	"сыновей %d, дочерей %d": "%d sons, %d daughters",
	"всего потомков-файлов: %d": "file descendants in total: %d",
	"братьев и сестёр: %d": "siblings: %d",
	"род: ": "line: ",
	"нет": "none",
	"%s · детей %d": "%s · %d children",
	"ещё %d…": "%d more…",
	"Поколение %d": "Generation %d",
}

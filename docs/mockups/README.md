# UI mockups v1

Черновые портретные экраны для обсуждения визуального направления «реализм + казуальная читаемость, немного ближе к реализму».

## Файлы

- `portrait-core-screens-v1.png` — главное меню, карта и событие.
- `portrait-progression-screens-v1.png` — персонаж, дела/учёба и медицинский выезд.

Оба листа созданы встроенным инструментом генерации изображений. Это композиционные концепты: интерфейс, весь текст, иконки и карты для игры будут собираться нативными компонентами Godot.

Сами PNG являются историческими черновиками и не перегенерируются ради новых подписей. Они не фиксируют принятые позднее старт `01.09.1980`, валюту «арден», нижнюю навигацию и единую пиктографическую систему; актуальны только исправленные промпты и обязательный [UI/UX-стандарт](../UI_UX_STANDARD.md).

Экран персонажа на втором листе создан до фиксации стартовой модели. В актуальной версии он должен показывать Силу, Харизму, Интеллект и Удачу числами `1–10`; при создании герой получает ровно 18 очков на четыре характеристики. Полярности остаются отдельным результатом поступков, а не стартовыми ползунками.

## Что проверяем

- один визуальный язык для старта 1980 года и более поздних десятилетий;
- читаемую портретную иерархию;
- пять постоянных показателей состояния;
- разделение карты, события, развития, долгосрочных дел и мини-игры;
- вкладку «Дела» вместо анахроничного игрового смартфона.

## Известные вопросы

- пять показателей могут быть слишком плотными на небольшом телефоне;
- архитектура и машина скорой помощи пока выглядят слишком восточноевропейскими — вымышленной стране потребуется собственная визуальная идентичность;
- портрет героя является временным примером, а не зафиксированным главным персонажем;
- палитра и шрифт ещё не утверждены.

## Финальные промпты

### Лист 1

```text
Use case: ui-mockup
Asset type: portrait Android game UI concept board, first visual draft for the game "Бомжара"
Primary request: create one polished mid-fidelity landscape presentation sheet showing THREE separate portrait mobile game screens side by side: main menu, city map, and text event. This is practical product UI, not concept art.
World: a fictional country; every new life begins on 1 September 1980 and can continue toward the present. The interface is a timeless meta-interface, not an in-world smartphone.
Visual direction: halfway between realism and casual mobile clarity, slightly closer to realism. Grounded urban atmosphere, restrained and humane, serious but accessible. Muted asphalt gray, weathered paper beige, dark municipal green, rust orange, and calm informational blue. Realistic illustrated scene panels, simplified shapes, large touch targets, strict surfaces with one small 4 dp corner radius, fine paper/map texture. No glossy toy look.
Composition/framing: horizontal 16:9 design board on a neutral warm-gray backdrop; three tall portrait screens fully visible and equally sized; crisp readable hierarchy; no hands and no phone hardware frames.

Screen 1 — main menu: exact title "БОМЖАРА"; subdued illustrated background of a worn fictional-city railway overpass and bus stop, visually compatible with 1980 but not tied to a real country; buttons "ПРОДОЛЖИТЬ", "НОВАЯ ЖИЗНЬ", "ХРОНИКИ", "НАСТРОЙКИ"; small autosave indicator.
Screen 2 — city: header "1 СЕНТЯБРЯ 1980 · 08:20", age "18", money "0" followed by the original arden pictogram: a diamond split by a vertical gap into two slightly offset halves; state indicators "ЗДОРОВЬЕ", "ГОЛОД", "ЭНЕРГИЯ", "НАПРЯЖЕНИЕ", "МОРАЛЬ"; map "СТАРЫЙ ВОКЗАЛ" with a player dot, route and location markers; navigation "МЕСТО", "КАРТА", "ГЕРОЙ", "ВЕЩИ", "ДЕЛА".
Screen 3 — event: same header; shop unloading illustration; title "РАЗГРУЗКА"; text "У магазина рассыпались ящики. Продавец пытается спасти товар."; buttons "ПОМОЧЬ С ЯЩИКАМИ", "ПОПРОСИТЬ ЕДУ", "УЙТИ"; no locked answers.

Constraints: Russian UI text only; no real-country currency or currency symbol; use one custom monochrome vector pictogram language inspired by 1980s urban wayfinding and technical manuals, with visible Russian labels; no emoji or mixed icon kits; no logos, trademarks, watermark, neon, fantasy, cyberpunk, candy gradients, excessive gloss, tiny clutter, or imitation of the old reference game's skin; Android-friendly spacing and accessibility.
```

### Лист 2

```text
Use case: ui-mockup
Asset type: second portrait Android game UI concept board for "Бомжара"
Input images: Image 1 is STYLE REFERENCE ONLY. Create a new sheet and match its grounded palette, paper cards, municipal green, rust accents, hierarchy, spacing and realistic-casual illustration treatment.
Primary request: one polished mid-fidelity landscape presentation sheet with THREE portrait screens: character development, affairs/education, and an emergency medical mission.

Screen 1 — character: title "ГЕРОЙ"; ordinary 18-year-old portrait; "ВОЗРАСТ 18"; five state indicators; system cards "СИЛА", "ХАРИЗМА", "ИНТЕЛЛЕКТ", "УДАЧА" with paired labels "МОЩЬ — ВЫНОСЛИВОСТЬ", "ДАВЛЕНИЕ — АВТОРИТЕТ", "СОСРЕДОТОЧЕНИЕ — ОБЗОР", "РАЗВЕДКА — ОСВОЕНИЕ"; section "НАВЫКИ", "ПОКА НЕТ"; same bottom navigation.
Screen 2 — affairs: title "ДЕЛА"; tabs "РАБОТА", "УЧЁБА", "ЖИЛЬЁ"; weekly schedule; cards "ВЕЧЕРНЯЯ ШКОЛА", "ПОДАТЬ ЗАЯВЛЕНИЕ", "НУЖНЫ ДОКУМЕНТЫ"; "КУРСЫ ПЕРВОЙ ПОМОЩИ", "6 НЕДЕЛЬ"; "ГРУЗЧИК", "СЕГОДНЯ · 4 ЧАСА".
Screen 3 — later-life mission: header "17 СЕНТЯБРЯ 1997 · 14:35", age "35"; title "ВЫЗОВ: ДТП"; urban accident without gore; cards "ПОСТРАДАВШИЙ 1", "ПОСТРАДАВШИЙ 2", "ПОСТРАДАВШИЙ 3"; supply counters; buttons "ОСМОТРЕТЬ", "СТАБИЛИЗИРОВАТЬ", "ТРАНСПОРТИРОВАТЬ".

Constraints: Russian UI only; no real-country currency or currency symbol; one custom monochrome vector pictogram family inspired by 1980s wayfinding and technical manuals, always paired with visible Russian labels; no emoji, mixed icon kits, logos, trademarks, watermark, gore, neon, cyberpunk, mascots, glossy toy UI, modern smartphone metaphor or excessive clutter; accessible button sizes and strong contrast.
```

# M3A — UI-архитектура

Статус: реализация завершена 23 июля 2026 года; формальная приёмка ожидает закрытия [Android-gate G0](G0_ANDROID_BASELINE.md).

M3A заменяет монолитную точку входа модульной UI-платформой. `ui/main.tscn` теперь открывает постоянный `AppShell`, а главное меню, создание героя, настройки, локация, выбор и результат оформлены самостоятельными сценами. Старый событийный UX M2 не считается продуктовым образцом; его проверенная логика временно доступна через совместимый адаптер.

## Наблюдаемый результат

- приложение запускается в новом главном меню и создаёт попытку через отдельный экран характеристик;
- экран локации показывает место, время, деньги, пять интерактивных показателей и доступные действия;
- `StatusGlyph` раскрывает точное значение, объяснение и прогноз, а изменение состояния поддерживает направленную анимацию;
- нижняя панель использует контракт `Место / Карта / Герой / Вещи / Дела`; M3B активировал вкладки места и карты, а остальные остаются видимыми до своих этапов;
- настройки увеличивают текст до 200%, отключают декоративное движение и меняют интенсивность психического фильтра только у окружения;
- Back, pause и пятиминутный таймер передаются координатору как intents сохранения и навигации.

M3A создал платформу, поверх которой M3B добавил свободный старт без обязательного события, рабочую карту и отдельные координаторы локальных действий и поездок. Реализованные границы продолжения описаны в [M3B — Location-first sandbox](M3B_LOCATION_SANDBOX.md).

## Поток данных и ответственности

```text
RunState / FirstDaySession
→ FirstDaySessionAdapter
→ UiCoordinator
→ UiScreenPresenter + UiModelFactory
→ AppShell
→ Screen.present(view_model)
→ типизированный intent-сигнал
→ UiCoordinator
→ session-команда и сохранение
```

| Узел | Ответственность |
|---|---|
| `GameSession` | UI-независимый контракт `base_location`, `active_activity` и read-model оболочки/локации |
| `FirstDaySessionMigration` | доменная миграция полной цепочки legacy-сессии без обратной зависимости `game → app` |
| `FirstDaySessionAdapter` | временный фасад над M2 без чтения legacy-полей экранными сценами |
| `UiCoordinator` | маршруты, выполнение intent-команд, Back, lifecycle и границы сохранения |
| `SessionPersistence` / `SaveSlot` | внедряемый доступ к слоту и защита от параллельной записи |
| `UiModelFactory` | чистое преобразование доменных моделей в русский UI-read-model |
| `UiScreenPresenter` | создание сцены, подключение сигналов и вызов `present(model)` |
| `AppShell` | safe area, `ScreenHost`, фон, оверлей уведомлений, нижняя навигация и переходы |
| `ui/screens/*` | только представление модели и отправка intent-сигналов |
| `ui/components/*` | повторяемые `GameHeader`, `StatusGlyph`, `ActionRow`, `BottomNavigation`, stepper и toast |
| `m3_ui_theme.tres` / `palette.gd` | единые визуальные токены и type variations |

Экранные сцены не импортируют `RunState`, не выбирают случайный контент и не пишут сохранение. Композиция хранится в `.tscn` и `Container`-узлах; психический шейдер применяется только к фону.

## Контракт сессии и миграция

В M3A версии envelope, `FirstDaySession` и `RunState` подняты до `2`. Миграция цепочки `v1 → v2`:

- работает на глубокой копии и не изменяет исходный payload при ошибке;
- переносит `location` в `base_location`;
- преобразует legacy-фазу в `active_activity { kind, id, snapshot }`;
- отвергает расхождение между legacy- и новым контрактом;
- проверяется реальным fixture `tests/fixtures/m2_first_day_v1.json`;
- не перезаписывает исходный файл до успешного восстановления и явного нового сохранения.

`active_activity` хранит прерываемое занятие, а не текущую вкладку UI. Пустая активность имеет форму `{ kind: "none", id: "", snapshot: {} }`.

## Адаптивность и motion

- safe area рассчитывается из `DisplayServer.get_display_safe_area()` с базовым полем 16 логических единиц; соответствие физическим dp входит в незакрытый G0;
- контент ограничен шириной 680 dp и сохраняет вертикальный скролл между фиксированными областями;
- интерактивные цели проверяются на минимум `48×48`;
- smoke-матрица включает `360×640`, `540×960`, `432×936` и масштаб текста 200%;
- reduced motion прекращает декоративное движение и завершает активный переход без промежуточного состояния;
- экранный переход занимает около 200–220 мс, изменение `StatusGlyph` — 360 мс.
- input-gate удерживает повторную доменную команду 250 мс; направление последней дельты остаётся видимым, но её анимация проигрывается только один раз.

### Эталонные рендеры

- [Главное меню, 360×640](qa/m3a/menu_360x640.png)
- [Создание героя, 360×640](qa/m3a/creation_360x640.png)
- [Локация, 360×640](qa/m3a/location_360x640.png)
- [Локация, 540×960](qa/m3a/location_540x960.png)

Это tracked QA-артефакты для ручного визуального ревью и сравнения регрессий. Они не являются runtime-ассетами и не загружаются игрой.
Каталог `docs/qa` закрыт от импортера Godot через `.gdignore`.

## Переходные границы

`ui/main.gd` больше не подключён к главной сцене, но остаётся legacy-источником до подтверждения функционального паритета и удаления в M3F.

M3B выполнил переходную границу M3A: продуктовый фасад вынесен в `SandboxSessionAdapter`, локальные действия — в `LocationFlowCoordinator`, поездки — в `MapFlowCoordinator`, настройки — в `PreferenceFlowCoordinator`, а lifecycle и сохранение — в `SessionLifecycleCoordinator`. Корневой `UiCoordinator` связывает эти потоки, но не содержит их доменные правила или разметку экранов. Compatibility-слой M2 удаляется вместе с legacy UI после функционального паритета в M3F.

## Автоматическая проверка

```powershell
godot --headless --path . --script res://tests/test_runner.gd
godot --headless --path . --script res://tests/m2_test_runner.gd
godot --headless --path . --script res://tests/m3a_session_test_runner.gd
godot --headless --path . --script res://tests/ui/ui_model_factory_test.gd
godot --headless --path . --script res://tests/ui/ui_coordinator_flow_test.gd
godot --headless --path . --script res://tests/ui/safe_area_layout_test.gd
godot --headless --path . --script res://tests/ui/app_shell_lifecycle_test.gd
godot --headless --path . --script res://tests/ui/location_screen_smoke.gd
godot --headless --path . --script res://tests/ui/app_shell_smoke.gd
godot --headless --path . --script res://ui/ui_render_runner.gd
```

Headless- и desktop-render-проверки подтверждают контракты, компоновку и регрессию, но не заменяют safe area, Back, suspend/kill/restore и производительность на физическом Android-устройстве. Поэтому код M3A реализован, а формальная приёмка остаётся заблокированной открытым G0.

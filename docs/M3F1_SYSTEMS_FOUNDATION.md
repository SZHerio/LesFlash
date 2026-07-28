# M3F.1 — системный фундамент недели

Статус: завершён 27 июля 2026 года.

M3F.1 переводит решения M3F.0 в проверяемые runtime-контракты. Этап не добавляет новый обязательный сюжет и не расширяет legacy-событийный UX: он создаёт данные и атомарные правила, на которых M3F.2 строит свободную семидневную sandbox-петлю.

## Наблюдаемый результат

- новая жизнь начинается `01.09.1980 08:00`, в 18 лет, без денег и предметов;
- шкала `morale` заменена на `mental_state` во всём актуальном runtime и контенте;
- существующее сохранение 1970 года загружается с исходными календарём, датой рождения и RNG;
- новая жизнь получает пять районных показателей, три факта и процесс `process_recycling_inspection` на стадии `latent`;
- одна session-команда атомарно меняет героя, время, отношения, репутацию, память, обязательства, мир и сохраняемый запас магазина;
- отложенная мутация мира срабатывает только после подтверждённого продвижения игрового времени;
- Event Director получает один снимок героя, объективного мира и социальных состояний, а authored world/social effects исполняются через общую транзакцию;
- поставка магазина детерминирована seed попытки, магазином, эпохой и номером поставки; повторное открытие не генерирует новый ассортимент.

## Версии и миграции

| Уровень | Предыдущая версия | Текущая версия | Изменение |
|---|---:|---:|---|
| `RunState` | 3 | 4 | `morale → mental_state` |
| standalone save envelope | 2 | 3 | новый `RunState` |
| `RunSession` | 4 | 5 | `WorldState`, `SocialState`, ledger команд, вложенный `EventContext v2` |
| first-day envelope | 4 | 5 | новый session payload |
| `GameSession` | 3 | 4 | мир, социальное состояние и ledger |
| `EventContext` | 1 | 2 | объективный мир, typed relationships, память и обязательства |
| event catalog | 1 | 2 | family/occurrence/NPC/causal metadata, бюджет до 100 карточек |
| stock snapshot | 0 | 1 | версия поставки и детерминированные offers |

Миграторы работают на глубокой копии. Коллизия старого и нового имени шкалы отклоняется; исходный файл при ошибке не перезаписывается. Fixtures предыдущих версий находятся в `tests/fixtures/m3f1_session_v4.json`, `tests/fixtures/run_state_envelope_v2.json` и `game/commerce/data/fixtures/stock_snapshot_v0.json`.

## Доменные границы

- `core/world/` хранит только объективное состояние мира, очередь и чистые read-model projections.
- `core/social/` хранит отношения `trust/respect/affinity/fear`, scoped reputation, typed memory и commitments.
- `game/content/` содержит отдельные versioned catalogs знаний, NPC, репутаций, работы и мира, а также межкаталожную проверку ссылок.
- `game/commerce/` разделяет authored products/stores, цену, генерацию поставки, snapshot и кандидаты покупки/продажи.
- `game/session/session_command_transaction.gd` является общей commit-границей. UI и карточки не правят `RunState`, `WorldState` или `SocialState` напрямую.
- `WorldReadModel.rules` доступен правилам, а `observed` показывает UI только открытые игроком следы; чтение обоих представлений не расходует RNG и не меняет время.

Три постоянных NPC имеют стабильные ID `npc_viktor_koren`, `npc_lidia_maren`, `npc_tamara_roven`. Первая работа — `job_recycling_sorter`; три магазина — `store_market_food_row`, `store_clinic_pharmacy_window`, `store_station_commission`.

## Проверки этапа

- каталоги контента: 9 сценариев;
- торговля и поставки: 9 сценариев;
- миграции всех уровней и вложенных encounter contexts: 7 сценариев;
- мир, социальное состояние, EventContext, глобальная история событий и общая транзакция: 9 сценариев;
- headless editor scan и регрессии M1–M3E;
- JSON parse, `git diff --check` и проверка отсутствия реальных валютных знаков выполняются перед commit.

Физическое Android-устройство, Android SDK и `adb` по-прежнему недоступны. Поэтому G0 остаётся открытым, а headless/render проверки не считаются device QA.

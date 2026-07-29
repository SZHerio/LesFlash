class_name DistrictContent
extends RefCounted

## Data-only catalog for the first playable day.
##
## The catalog deliberately returns plain Dictionaries and Arrays. Conditions
## and effects are constructed through the M1 rules API, so the same content can
## later be moved to JSON without changing the session flow.

const DISTRICT_ID := "riverside_central"
## The places a run opens with. The other two districts are in the catalog but
## not in this list: a run has to be complete inside Riverside alone, or a hero
## who never finds the bus is playing a broken game rather than a harder one.
const REQUIRED_LOCATION_IDS := CityPlaces.RIVERSIDE_PLACE_IDS


static func district() -> Dictionary:
	return {
		"id": DISTRICT_ID,
		"title": "Приречный район",
		"description": "Старый район между вокзалом и рекой: шумный рынок, дворы учреждений и несколько мест, где можно переждать ночь.",
		"location_ids": REQUIRED_LOCATION_IDS.duplicate(),
	}


## Every district in the city, home one first. What the hero may see of this is
## decided elsewhere: one he has not heard of is absent from his map.
static func districts() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for district_id: String in CityPlaces.district_ids():
		result.append({
			"id": district_id,
			"title": CityPlaces.district_title(district_id),
			"location_ids": CityPlaces.ids_in(district_id),
			"knowledge_id": CityPlaces.knowledge_for(district_id),
		})
	return result


static func locations() -> Dictionary:
	return {
		"underpass": {
			"id": "underpass",
			"district_id": DISTRICT_ID,
			"title": "Подземный переход",
			"description": "Сырой переход под проспектом. Здесь тепло от труб, но каждый угол уже кем-то замечен.",
			"background_id": "riverside_underpass_day",
			"background_key": "riverside_underpass_day",
			"tags": ["улица", "укрытие", "людно"],
			"routes": [
				_route("market", 18),
				_route("station_square", 12),
				_route("clinic_yard", 28, 8, 9),
			],
		},
		"market": {
			"id": "market",
			"district_id": DISTRICT_ID,
			"title": "Рынок",
			"description": "Торговые ряды, разгрузочные ворота и контейнеры, которые вывозят только вечером.",
			"background_id": "riverside_market_day",
			"background_key": "riverside_market_day",
			"tags": ["торговля", "еда", "работа"],
			"routes": [
				_route("underpass", 18),
				_route("station_square", 16),
				_route("recycling_point", 24),
				_route("freight_yard", 26, 9, 10),
				_route("courtyard_blocks", 19),
				_route("embankment", 34, 10, 12),
			],
		},
		"station_square": {
			"id": "station_square",
			"district_id": DISTRICT_ID,
			"title": "Вокзальная площадь",
			"description": "Поток пассажиров, киоски и служебные двери. Здесь легко затеряться и трудно долго оставаться незамеченным.",
			"background_id": "riverside_station_square_day",
			"background_key": "riverside_station_square_day",
			"tags": ["транспорт", "людно", "подработка"],
			"routes": [
				_route("underpass", 12),
				_line("bus_depot", "bus", "Автобус в Завокзальный", 35, 24, 6 * 60, 23 * 60),
				_route("freight_yard", 14),
				_route("market", 16),
				_route("clinic_yard", 32, 8, 10),
				_route("embankment", 26),
			],
		},
		"recycling_point": {
			"id": "recycling_point",
			"district_id": DISTRICT_ID,
			"title": "Пункт вторсырья",
			"description": "Навес, весы и тесный склад. Хозяину часто нужны руки для сортировки и разгрузки.",
			"background_id": "riverside_recycling_point_day",
			"background_key": "riverside_recycling_point_day",
			"tags": ["работа", "вторсырьё", "склад"],
			"routes": [
				_route("market", 24),
				_route("freight_yard", 16),
				_route("clinic_yard", 20),
				_route("embankment", 22),
			],
		},
		"clinic_yard": {
			"id": "clinic_yard",
			"district_id": DISTRICT_ID,
			"title": "Двор поликлиники",
			"description": "Тихий служебный двор со скамейкой, аптечным окном и тёплой вентиляционной решёткой.",
			"background_id": "riverside_clinic_yard_day",
			"background_key": "riverside_clinic_yard_day",
			"tags": ["здоровье", "тихо", "укрытие"],
			"routes": [
				_route("underpass", 28, 8, 9),
				_route("station_square", 32, 8, 10),
				_route("recycling_point", 20),
				_route("embankment", 18),
				_route("courtyard_blocks", 11),
			],
		},
		"embankment": {
			"id": "embankment",
			"district_id": DISTRICT_ID,
			"title": "Набережная",
			"description": "Длинная прогулочная полоса у холодной воды. Днём здесь спокойно, к ночи ветер становится опасным.",
			"background_id": "riverside_embankment_day",
			"background_key": "riverside_embankment_day",
			"tags": ["река", "тихо", "вторсырьё"],
			"routes": [
				_route("market", 34, 10, 12),
				_route("station_square", 26),
				_route("recycling_point", 22),
				_route("clinic_yard", 18),
				_route("courtyard_blocks", 22),
				_line("cathedral_steps", "tram", "Трамвай на Соборную", 28, 18, 6 * 60 + 30, 22 * 60 + 30),
			],
		},
		"freight_yard": {
			"id": "freight_yard",
			"district_id": DISTRICT_ID,
			"title": "Товарный двор",
			"description": "Тупиковые пути, поддоны и сторожка. Днём здесь разгружают, ночью двор пустеет и становится тише вокзала.",
			"background_id": "riverside_freight_yard_day",
			"background_key": "riverside_freight_yard_day",
			"tags": ["работа", "поиск", "риск"],
			"routes": [
				_route("station_square", 14),
				_route("recycling_point", 16),
				_route("market", 26, 9, 10),
			],
		},
		"courtyard_blocks": {
			"id": "courtyard_blocks",
			"district_id": DISTRICT_ID,
			"title": "Жилые дворы",
			"description": "Пятиэтажки, бельевые верёвки и лавки у подъездов. Здесь живут, а не проходят мимо, и чужого замечают сразу.",
			"background_id": "riverside_courtyard_blocks_day",
			"background_key": "riverside_courtyard_blocks_day",
			"tags": ["жильё", "люди", "тихо"],
			"routes": [
				_route("clinic_yard", 11),
				_route("market", 19),
				_route("embankment", 22),
			],
		},
		"bus_depot": {
			"id": "bus_depot",
			"district_id": CityPlaces.ZAVOKZALNY,
			"title": "Автобусный парк",
			"description": "Кольцо маршрутов, мойка и вечная очередь у диспетчерской. Здесь всегда кому-то не хватает рук на час.",
			"background_id": "zavokzalny_bus_depot_day",
			"background_key": "zavokzalny_bus_depot_day",
			"tags": ["транспорт", "работа", "людно"],
			"routes": [
				_line("station_square", "bus", "Автобус в Приречный", 35, 24, 6 * 60, 23 * 60),
				_route("night_canteen", 14),
				_route("workshop_row", 20),
			],
		},
		"night_canteen": {
			"id": "night_canteen",
			"district_id": CityPlaces.ZAVOKZALNY,
			"title": "Ночная столовая",
			"description": "Работает, пока ходят автобусы. Кормят дёшево и не спрашивают, откуда вы пришли.",
			"background_id": "zavokzalny_night_canteen_day",
			"background_key": "zavokzalny_night_canteen_day",
			"tags": ["еда", "тепло", "ночь"],
			"routes": [
				_route("bus_depot", 14),
				_route("workshop_row", 16),
			],
		},
		"workshop_row": {
			"id": "workshop_row",
			"district_id": CityPlaces.ZAVOKZALNY,
			"title": "Мастерские",
			"description": "Ряд гаражей, где чинят всё подряд. Инструмент чужой, но за помощь иногда дают им пользоваться.",
			"background_id": "zavokzalny_workshop_row_day",
			"background_key": "zavokzalny_workshop_row_day",
			"tags": ["ремонт", "работа", "инструмент"],
			"routes": [
				_route("bus_depot", 20),
				_route("night_canteen", 16),
			],
		},
		"cathedral_steps": {
			"id": "cathedral_steps",
			"district_id": CityPlaces.SOBORNAYA,
			"title": "Соборные ступени",
			"description": "Широкая паперть, где раздают и просят. Тут запоминают всех, кто пришёл второй раз.",
			"background_id": "sobornaya_cathedral_steps_day",
			"background_key": "sobornaya_cathedral_steps_day",
			"tags": ["люди", "подаяние", "тихо"],
			"routes": [
				_line("embankment", "tram", "Трамвай в Приречный", 28, 18, 6 * 60 + 30, 22 * 60 + 30),
				_route("almshouse", 12),
				_route("pawn_row", 18),
			],
		},
		"almshouse": {
			"id": "almshouse",
			"district_id": CityPlaces.SOBORNAYA,
			"title": "Богадельня",
			"description": "Ночлежка при приходе. Мест мало, порядки строгие, но крыша настоящая.",
			"background_id": "sobornaya_almshouse_day",
			"background_key": "sobornaya_almshouse_day",
			"tags": ["ночлег", "порядок", "тепло"],
			"routes": [
				_route("cathedral_steps", 12),
				_route("pawn_row", 20),
			],
		},
		"pawn_row": {
			"id": "pawn_row",
			"district_id": CityPlaces.SOBORNAYA,
			"title": "Ломбардный ряд",
			"description": "Витрины с чужими вещами. Здесь берут почти всё и дают за это меньше, чем оно стоит.",
			"background_id": "sobornaya_pawn_row_day",
			"background_key": "sobornaya_pawn_row_day",
			"tags": ["торговля", "деньги", "риск"],
			"routes": [
				_route("cathedral_steps", 18),
				_route("almshouse", 20),
			],
		},
	}


static func location(location_id: String) -> Dictionary:
	var value: Variant = locations().get(location_id, {})
	return value.duplicate(true) if value is Dictionary else {}


static func routes_from(location_id: String) -> Array:
	var place := location(location_id)
	var routes: Variant = place.get("routes", [])
	return routes.duplicate(true) if routes is Array else []


static func start_situations() -> Array:
	return [
		{
			"id": "start_station_rain",
			"title": "Под холодным дождём",
			"text": "Вы приходите в себя у края вокзальной площади. Куртка промокла, вокруг спешат люди, а впереди нет ни денег, ни знакомых.",
			"journal_message": "Первый день начался под дождём у вокзала.",
			"location_id": "station_square",
			"severity": 4,
			"weights_by_luck": _luck_weights([12, 11, 9, 7, 5, 3, 2, 1, 0, 0]),
			"opening_event_id": "station_first_minutes",
			"opening_card_id": "station_first_minutes",
			"conditions": [],
			"initial_effects": [Effect.change_state(&"energy", -12), Effect.change_state(&"tension", 18)],
			"effects": [Effect.change_state(&"energy", -12), Effect.change_state(&"tension", 18)],
		},
		{
			"id": "start_underpass_bench",
			"title": "Скамья в переходе",
			"text": "Утро начинается на холодной скамье в подземном переходе. Рядом открываются киоски, и место быстро наполняется людьми.",
			"journal_message": "Первое утро прошло на скамье в переходе.",
			"location_id": "underpass",
			"severity": 3,
			"weights_by_luck": _luck_weights([8, 8, 8, 7, 6, 5, 4, 3, 2, 1]),
			"opening_event_id": "underpass_first_minutes",
			"opening_card_id": "underpass_first_minutes",
			"conditions": [],
			"initial_effects": [Effect.change_state(&"energy", -8), Effect.change_state(&"mental_state", -8)],
			"effects": [Effect.change_state(&"energy", -8), Effect.change_state(&"mental_state", -8)],
		},
		{
			"id": "start_market_awning",
			"title": "До открытия рынка",
			"text": "Вы встречаете утро под навесом рынка. Торговцы только поднимают ставни, и несколько минут можно спокойно осмотреться.",
			"journal_message": "Первый день начался у ещё закрытого рынка.",
			"location_id": "market",
			"severity": 2,
			"weights_by_luck": _luck_weights([3, 4, 5, 6, 7, 8, 8, 8, 7, 6]),
			"opening_event_id": "market_city_rumors",
			"opening_card_id": "market_city_rumors",
			"conditions": [],
			"initial_effects": [Effect.change_state(&"hunger", 8), Effect.change_state(&"tension", 6)],
			"effects": [Effect.change_state(&"hunger", 8), Effect.change_state(&"tension", 6)],
		},
		{
			"id": "start_clinic_quiet",
			"title": "Тихий двор",
			"text": "Вы просыпаетесь на скамейке во дворе поликлиники. Ночь была сухой, поблизости есть вода, а служебный вход пока закрыт.",
			"journal_message": "Первое утро началось в тихом дворе поликлиники.",
			"location_id": "clinic_yard",
			"severity": 1,
			"weights_by_luck": _luck_weights([0, 1, 2, 3, 4, 6, 8, 10, 12, 14]),
			"opening_event_id": "clinic_notice_board",
			"opening_card_id": "clinic_notice_board",
			"conditions": [],
			"initial_effects": [Effect.change_state(&"energy", -3), Effect.change_state(&"mental_state", 4)],
			"effects": [Effect.change_state(&"energy", -3), Effect.change_state(&"mental_state", 4)],
		},
	]


static func event_cards() -> Dictionary:
	var cards: Dictionary = {}
	for card in _event_list():
		cards[String(card["id"])] = card
	return cards


static func events_for_location(location_id: String) -> Array:
	var result: Array = []
	for card in event_cards().values():
		if String(card.get("location_id", "")) == location_id:
			result.append(card.duplicate(true))
	result.sort_custom(_sort_by_id)
	return result


static func job() -> Dictionary:
	return {
		"id": "recycling_sorter",
		"location_id": "recycling_point",
		"title": "Сортировка и разгрузка вторсырья",
		"description": "Короткая смена во дворе пункта приёма: принять тележку, разнести материал и не испортить весы.",
		"entry_conditions": [
			Condition.with_reason(Condition.state(&"energy", 30), "Слишком мало сил для смены"),
			Condition.with_reason(Condition.state(&"hunger", 85, Condition.LESS_OR_EQUAL), "На таком голоде тяжёлая работа опасна"),
		],
		"conditions": [
			Condition.with_reason(Condition.state(&"energy", 30), "Слишком мало сил для смены"),
			Condition.with_reason(Condition.state(&"hunger", 85, Condition.LESS_OR_EQUAL), "На таком голоде тяжёлая работа опасна"),
		],
		"duration_minutes": 120,
		"minigame": {
			"type": "sorting_shift",
			"rounds_to_draw": 6,
			"prompts": [
				{
					"id": "cart_at_gate",
					"text": "Гружёная тележка застряла у ворот.",
					"choices": [
						_job_choice("pull_alone", "Вытащить её одним рывком", 3, [Condition.stat(&"strength", 7)]),
						_job_choice("shift_load", "Переложить часть груза и освободить колесо", 2, [Condition.stat(&"intelligence", 5)]),
						_job_choice("ask_owner", "Позвать хозяина и тянуть вместе", 1),
					],
				},
				{
					"id": "mixed_plastic",
					"text": "В мешке перемешаны разные виды пластика.",
					"choices": [
						_job_choice("read_markings", "Сверяться с маркировкой на каждой вещи", 3, [Condition.stat(&"intelligence", 6)]),
						_job_choice("use_experience", "Сортировать по виду и плотности", 3, [Condition.skill(&"city_navigation", 1)]),
						_job_choice("separate_obvious", "Отложить только то, в чём нет сомнений", 1),
					],
				},
				{
					"id": "jammed_press",
					"text": "Ручной пресс заедает на середине хода.",
					"choices": [
						_job_choice("inspect_press", "Найти перекос и поправить направляющую", 3, [Condition.skill(&"repair", 1)]),
						_job_choice("force_press", "Дожать рычаг силой", 2, [Condition.stat(&"strength", 6)]),
						_job_choice("leave_press", "Отложить тюк и сообщить о поломке", 1),
					],
				},
				{
					"id": "glass_crate",
					"text": "Ящик со стеклом нужно перенести через тесный проход.",
					"choices": [
						_job_choice("balanced_carry", "Перехватить ящик и пройти без остановки", 3, [Condition.skill(&"cargo_handling", 1)]),
						_job_choice("clear_path", "Сначала расчистить проход", 2, [Condition.stat(&"intelligence", 4)]),
						_job_choice("small_batches", "Переносить стекло небольшими партиями", 1),
					],
				},
				{
					"id": "weight_argument",
					"text": "Постоянный клиент спорит с показанием весов и мешает очереди.",
					"choices": [
						_job_choice("explain_scale", "Спокойно объяснить порядок взвешивания", 3, [Condition.stat(&"charisma", 6)]),
						_job_choice("check_scale", "Провести контрольное взвешивание", 3, [Condition.skill(&"trade", 1)]),
						_job_choice("call_owner", "Передать спор хозяину", 1),
					],
				},
				{
					"id": "last_bundle",
					"text": "До конца смены остаётся тяжёлый мокрый тюк картона.",
					"choices": [
						_job_choice("finish_fast", "Поднять тюк и закончить разгрузку", 3, [Condition.stat(&"strength", 8)]),
						_job_choice("use_pallet", "Собрать простой рычаг из поддона", 3, [Condition.skill(&"repair", 1)]),
						_job_choice("drag_bundle", "Перетащить тюк по земле", 1),
					],
				},
			],
		},
		"result_tiers": [
			{
				"id": "rough_shift",
				"min_score": 0,
				"max_score": 8,
				"label": "Тяжёлая смена",
				"effects": [
					Effect.advance_time(120, "Смена на пункте вторсырья"),
					Effect.change_state(&"energy", -32),
					Effect.change_state(&"hunger", 22),
					Effect.change_money(100),
					Effect.mastery(1),
				],
			},
			{
				"id": "steady_shift",
				"min_score": 9,
				"max_score": 14,
				"label": "Надёжная смена",
				"effects": [
					Effect.advance_time(120, "Смена на пункте вторсырья"),
					Effect.change_state(&"energy", -28),
					Effect.change_state(&"hunger", 20),
					Effect.change_money(180),
					Effect.practice_skill(&"cargo_handling", &"legacy_shift_hard"),
					Effect.mastery(2),
				],
			},
			{
				"id": "clean_shift",
				"min_score": 15,
				"max_score": 18,
				"label": "Чистая работа",
				"effects": [
					Effect.advance_time(120, "Смена на пункте вторсырья"),
					Effect.change_state(&"energy", -24),
					Effect.change_state(&"hunger", 18),
					Effect.change_money(260),
					Effect.practice_skill(&"cargo_handling", &"legacy_shift_clean"),
					Effect.knowledge(&"recycling_rules", 1, &"unlock"),
					Effect.mastery(3),
				],
			},
		],
	}


static func shelters() -> Dictionary:
	return {
		"underpass_niche": {
			"id": "underpass_niche",
			"location_id": "underpass",
			"title": "Ниша у тёплой трубы",
			"description": "Бесплатно и относительно сухо, но шум не прекращается до утра.",
			"risk": 4,
			"quality": 1,
			"conditions": [],
			"effects": [Effect.advance_time(480, "Ночь в подземном переходе"), Effect.change_state(&"energy", 42), Effect.change_state(&"hunger", 24), Effect.change_state(&"tension", 14), Effect.change_state(&"mental_state", -6)],
		},
		"station_waiting_room": {
			"id": "station_waiting_room",
			"location_id": "station_square",
			"title": "Зал ожидания",
			"description": "Теплее улицы, если получится убедительно объяснить, почему вы ждёте ночной поезд.",
			"risk": 2,
			"quality": 2,
			"conditions": [Condition.with_reason(Condition.stat(&"charisma", 5), "Нужно убедительно поговорить с дежурным")],
			"effects": [Effect.advance_time(420, "Ночь в зале ожидания"), Effect.change_state(&"energy", 52), Effect.change_state(&"hunger", 20), Effect.change_state(&"tension", 4)],
		},
		"clinic_boiler_entry": {
			"id": "clinic_boiler_entry",
			"location_id": "clinic_yard",
			"title": "Тамбур у котельной",
			"description": "Неприметный тёплый тамбур, о котором знают только те, кто изучил служебный двор.",
			"risk": 1,
			"quality": 3,
			"conditions": [Condition.with_reason(Condition.knowledge(&"clinic_back_gate"), "Вы ещё не знаете, когда открывается служебная калитка")],
			"effects": [Effect.advance_time(450, "Ночь у котельной поликлиники"), Effect.change_state(&"energy", 60), Effect.change_state(&"hunger", 18), Effect.change_state(&"tension", -8), Effect.change_state(&"mental_state", 5)],
		},
		"embankment_boathouse": {
			"id": "embankment_boathouse",
			"location_id": "embankment",
			"title": "Навес лодочной станции",
			"description": "От ветра защищает только стенка, зато ночью сюда почти никто не приходит.",
			"risk": 3,
			"quality": 2,
			"conditions": [Condition.with_reason(Condition.item(&"cardboard_sheet"), "Нужен картон, чтобы изолироваться от холодного бетона")],
			"effects": [Effect.advance_time(450, "Ночь под навесом лодочной станции"), Effect.change_state(&"energy", 48), Effect.change_state(&"hunger", 22), Effect.change_state(&"tension", 2), Effect.change_state(&"health", -3)],
		},
	}


static func _event_list() -> Array:
	return [
		_card(
			"underpass_first_minutes", "orientation", "underpass",
			"Первые минуты", "Переход просыпается вместе с городом. Нужно понять, куда идти, пока охрана не попросила освободить скамью.",
			[
				_choice(
					"underpass_first_minutes.study_flow", "Понаблюдать за потоком людей",
					"Вы замечаете, откуда идут работники рынка и где расположен вокзал.",
					[Condition.with_reason(Condition.stat(&"intelligence", 5), "Нужно лучше анализировать обстановку")],
					[Effect.advance_time(10, "Наблюдение в переходе"), Effect.knowledge(&"district_landmarks", 1, &"unlock"), Effect.shift_polarity(&"attention_distribution", -3)]
				),
				_choice(
					"underpass_first_minutes.ask_kiosk", "Спросить дорогу у продавца киоска",
					"Продавец коротко объясняет, где рынок и дешёвая столовая.",
					[Condition.with_reason(Condition.stat(&"charisma", 5), "Нужно расположить к себе занятого продавца")],
					[Effect.advance_time(8, "Разговор у киоска"), Effect.knowledge(&"cheap_canteen", 1, &"unlock"), Effect.shift_polarity(&"influence_style", 3)]
				),
				_choice(
					"underpass_first_minutes.move_on", "Подняться на улицу",
					"Вы не задерживаетесь и выходите к проспекту.", [],
					[Effect.advance_time(5, "Выход из перехода"), Effect.change_state(&"tension", -2)]
				),
			]
		),
		_card(
			"underpass_rain_crowd", "weather", "underpass",
			"Все прячутся от дождя", "Ливень загоняет в переход прохожих. В проходе тесно, у лестницы застряла детская коляска.",
			[
				_choice(
					"underpass_rain_crowd.lift_stroller", "Помочь поднять коляску",
					"Коляска оказывается тяжёлой, но проход быстро освобождается.",
					[Condition.with_reason(Condition.stat(&"strength", 5), "Не хватает силы безопасно поднять коляску")],
					[Effect.advance_time(10, "Помощь у лестницы"), Effect.change_state(&"energy", -5), Effect.change_state(&"mental_state", 6), Effect.mastery(1)]
				),
				_choice(
					"underpass_rain_crowd.find_passage", "Пройти по сухой стороне",
					"Вы используете боковой коридор и не попадаете в давку.",
					[Condition.with_reason(Condition.skill(&"city_navigation", 1), "Нужен навык ориентирования в городе")],
					[Effect.advance_time(8, "Обход толпы"), Effect.change_state(&"tension", -4), Effect.shift_polarity(&"execution_style", 3)]
				),
				_choice(
					"underpass_rain_crowd.wait", "Переждать у стены",
					"Толпа редеет, но сырой воздух пробирает до костей.", [],
					[Effect.advance_time(25, "Ожидание конца ливня"), Effect.change_state(&"energy", -4), Effect.deferred(&"cold_symptoms", 180, {"health": -5}, &"underpass_rain_cold", &"underpass_rain_crowd")]
				),
			]
		),
		_card(
			"underpass_sleeping_place", "territory_conflict", "underpass",
			"Занятое место", "В глубине перехода лежит сухой картон. Мужчина у стены говорит, что это место уже занято.",
			[
				_choice(
					"underpass_sleeping_place.talk", "Договориться о правилах",
					"Разговор проходит без дружбы, но теперь вы знаете, когда ниша свободна.",
					[Condition.with_reason(Condition.stat(&"charisma", 7), "Нужно говорить спокойно и уверенно")],
					[Effect.advance_time(15, "Разговор о месте"), Effect.knowledge(&"underpass_rules", 1, &"unlock"), Effect.deferred(&"local_recognition", 240, {"location_id": "underpass"}, &"underpass_recognition", &"underpass_sleeping_place")]
				),
				_choice(
					"underpass_sleeping_place.stand_ground", "Не отступать",
					"Вы выдерживаете тяжёлый взгляд, но спокойнее от этого не становится.",
					[Condition.with_reason(Condition.stat(&"strength", 8), "Вас не воспримут всерьёз без внушительной силы")],
					[Effect.advance_time(8, "Спор за место"), Effect.change_state(&"tension", 12), Effect.change_state(&"mental_state", 2), Effect.shift_polarity(&"influence_style", -5)]
				),
				_choice(
					"underpass_sleeping_place.leave", "Не спорить и уйти",
					"Вы оставляете картон на месте и избегаете конфликта.", [],
					[Effect.advance_time(5, "Отказ от спора"), Effect.change_state(&"mental_state", -4), Effect.change_state(&"tension", -3)]
				),
			]
		),
		_card(
			"underpass_nightfall", "evening_shelter", "underpass",
			"Перед закрытием киосков", "Свет в киосках гаснет. Через час переход опустеет, и нужно решить, готовиться ли здесь ко сну.",
			[
				_choice(
					"underpass_nightfall.prepare", "Подготовить сухое место",
					"Вы складываете несколько листов картона подальше от сквозняка.",
					[Condition.with_reason(Condition.stat(&"intelligence", 5), "Нужно оценить сквозняки и движение охраны")],
					[Effect.advance_time(20, "Подготовка места в переходе"), Effect.add_item(&"cardboard_sheet"), Effect.knowledge(&"underpass_niche", 1, &"unlock"), Effect.shift_polarity(&"attention_distribution", -3)]
				),
				_choice(
					"underpass_nightfall.notice_niche", "Заметить нишу за лестницей",
					"За лестницей действительно есть сухой угол, невидимый от входа.",
					[Condition.with_reason(Condition.stat(&"luck", 6), "Нужна удача, чтобы случайно заметить укрытие")],
					[Effect.advance_time(8, "Осмотр перехода"), Effect.knowledge(&"underpass_niche", 1, &"unlock"), Effect.change_state(&"mental_state", 4)]
				),
				_choice(
					"underpass_nightfall.keep_moving", "Искать другое место",
					"Вы решаете не оставаться там, где вас легко заметить.", [],
					[Effect.advance_time(5, "Уход из перехода"), Effect.shift_polarity(&"uncertainty_behavior", -2)]
				),
			]
		),
		_card(
			"market_damaged_food", "food_opportunity", "market",
			"Списанные продукты", "Работник складывает в ящик помятые овощи и вчерашнюю выпечку. Часть еды выглядит пригодной.",
			[
				_choice(
					"market_damaged_food.inspect", "Отобрать безопасные продукты",
					"Вы внимательно проверяете запах и повреждения и находите нормальную еду.",
					[Condition.with_reason(Condition.stat(&"intelligence", 6), "Нужно уметь оценить испорченные продукты")],
					[Effect.advance_time(15, "Проверка списанных продуктов"), Effect.change_state(&"hunger", -20), Effect.knowledge(&"food_safety", 1, &"unlock"), Effect.shift_polarity(&"attention_distribution", -4)]
				),
				_choice(
					"market_damaged_food.make_meal", "Собрать продукты для простой еды",
					"Из нескольких невзрачных продуктов получится сытная порция.",
					[],
					[Effect.advance_time(12, "Сбор продуктов"), Effect.add_item(&"simple_meal"), Effect.practice_skill(&"cooking", &"legacy_market_meal"), Effect.mastery(1)]
				),
				_choice(
					"market_damaged_food.eat_pastry", "Съесть то, что выглядит лучше",
					"Голод отступает, хотя уверенности в качестве выпечки нет.", [],
					[Effect.advance_time(8, "Быстрая еда"), Effect.change_state(&"hunger", -14), Effect.deferred(&"stomach_upset", 150, {"energy": -8, "tension": 4}, &"market_food_aftereffect", &"market_damaged_food")]
				),
			]
		),
		_card(
			"market_dropped_bag", "lost_property", "market",
			"Потерянная сумка", "У выхода лежит хозяйственная сумка с кошельком в боковом кармане. Владелец, вероятно, ещё рядом.",
			[
				_choice(
					"market_dropped_bag.find_owner", "Найти владельца по приметам",
					"Вы замечаете растерянную женщину у соседнего ряда. Она забирает сумку и благодарит вас.",
					[Condition.with_reason(Condition.stat(&"luck", 6), "Нужно вовремя заметить владельца в толпе")],
					[Effect.advance_time(12, "Поиск владельца сумки"), Effect.change_money(30), Effect.change_state(&"mental_state", 7), Effect.deferred(&"owner_remembers_help", 300, {"location_id": "market"}, &"market_owner_memory", &"market_dropped_bag")]
				),
				_choice(
					"market_dropped_bag.ask_stalls", "Расспросить соседних продавцов",
					"Продавцы быстро находят хозяина сумки и начинают смотреть на вас доброжелательнее.",
					[Condition.with_reason(Condition.stat(&"charisma", 5), "Нужно, чтобы продавцы захотели помочь")],
					[Effect.advance_time(15, "Расспросы о сумке"), Effect.knowledge(&"market_regulars", 1, &"unlock"), Effect.change_state(&"mental_state", 5), Effect.shift_polarity(&"influence_style", 4)]
				),
				_choice(
					"market_dropped_bag.leave", "Оставить сумку у охраны",
					"Вы передаёте находку охраннику и не задерживаетесь.", [],
					[Effect.advance_time(6, "Передача находки"), Effect.change_state(&"tension", -2)]
				),
			]
		),
		_card(
			"market_city_rumors", "local_information", "market",
			"Разговор у ворот", "Грузчики обсуждают дешёвую столовую, способы использовать вчерашние продукты, ночную проверку на вокзале и пункт вторсырья у реки.",
			[
				_choice(
					"market_city_rumors.listen", "Запомнить полезные ориентиры",
					"Из обрывков разговора складывается первая понятная карта района и несколько практичных правил обращения с простой едой.",
					[Condition.with_reason(Condition.stat(&"intelligence", 4), "Нужно отделить полезные сведения от слухов")],
					[Effect.advance_time(10, "Разговоры у рынка"), Effect.knowledge(&"district_landmarks", 1, &"unlock"), Effect.practice_skill(&"city_navigation", &"legacy_market_talk"), Effect.shift_polarity(&"attention_distribution", 3)]
				),
				_choice(
					"market_city_rumors.move_on", "Не задерживаться у ворот",
					"Вы уходите до того, как началась утренняя разгрузка.", [],
					[Effect.advance_time(5, "Осмотр рынка")]
				),
			]
		),
		_card(
			"market_unloading_offer", "job_entry", "market",
			"Машина у ворот", "Водитель ищет человека, который поможет быстро снять несколько ящиков до открытия ряда.",
			[
				_choice(
					"market_unloading_offer.lift", "Взяться за тяжёлые ящики",
					"Работа заканчивается быстро, и водитель рассчитывается сразу.",
					[Condition.with_reason(Condition.stat(&"strength", 6), "Ящики слишком тяжелы для безопасной разгрузки")],
					[Effect.advance_time(40, "Разгрузка у рынка"), Effect.change_state(&"energy", -14), Effect.change_state(&"hunger", 8), Effect.change_money(90), Effect.practice_skill(&"cargo_handling", &"legacy_market_unload")]
				),
				_choice(
					"market_unloading_offer.organize", "Предложить удобный порядок разгрузки",
					"Вы переставляете пустые поддоны и экономите всем несколько лишних ходок.",
					[Condition.with_reason(Condition.stat(&"intelligence", 6), "Нужно быстро оценить тесную разгрузочную зону")],
					[Effect.advance_time(35, "Организация разгрузки"), Effect.change_state(&"energy", -9), Effect.change_money(75), Effect.shift_polarity(&"execution_style", 4), Effect.mastery(1)]
				),
				_choice(
					"market_unloading_offer.negotiate", "Сначала договориться об оплате",
					"Водитель ворчит, но называет ясную сумму и сдерживает слово.",
					[Condition.with_reason(Condition.stat(&"charisma", 6), "Нужно уверенно договориться до начала работы")],
					[Effect.advance_time(35, "Оплаченная помощь у рынка"), Effect.change_state(&"energy", -10), Effect.change_money(105), Effect.practice_skill(&"trade", &"legacy_market_paid_help"), Effect.shift_polarity(&"influence_style", 4)]
				),
				_choice(
					"market_unloading_offer.decline", "Отказаться от тяжёлой работы",
					"Вы сохраняете силы и продолжаете искать более подходящее занятие.", [],
					[Effect.advance_time(3, "Отказ от разгрузки"), Effect.change_state(&"tension", -1)]
				),
			]
		),
		_card(
			"station_first_minutes", "orientation", "station_square",
			"Утро у вокзала", "Электронные часы показывают раннее утро. Под навесом сухо, но дежурный уже осматривает площадь.",
			[
				_choice(
					"station_first_minutes.read_board", "Изучить схему транспорта",
					"По старой схеме удаётся восстановить основные направления района.",
					[Condition.with_reason(Condition.stat(&"intelligence", 5), "Схема запутана и частично заклеена объявлениями")],
					[Effect.advance_time(12, "Изучение схемы у вокзала"), Effect.knowledge(&"district_landmarks", 1, &"unlock"), Effect.shift_polarity(&"attention_distribution", -3)]
				),
				_choice(
					"station_first_minutes.ask_commuter", "Спросить совета у пассажира",
					"Один из пассажиров называет рынок и пункт вторсырья, где иногда платят в тот же день.",
					[Condition.with_reason(Condition.stat(&"charisma", 5), "Нужно выбрать человека, готового остановиться")],
					[Effect.advance_time(8, "Разговор на площади"), Effect.knowledge(&"recycling_job", 1, &"unlock"), Effect.shift_polarity(&"influence_style", 3)]
				),
				_choice(
					"station_first_minutes.leave_canopy", "Уйти с навеса",
					"Вы покидаете площадь до того, как дежурный подходит ближе.", [],
					[Effect.advance_time(5, "Уход с вокзальной площади"), Effect.change_state(&"tension", -3)]
				),
			]
		),
		_card(
			"station_porter_offer", "casual_work", "station_square",
			"Багаж без носильщика", "Пожилая пара не может поднять чемодан на высокий бордюр и оглядывается в поисках помощи.",
			[
				_choice(
					"station_porter_offer.carry", "Донести чемодан до платформы",
					"Чемодан тяжёлый, зато помощь оценивают честно.",
					[Condition.with_reason(Condition.stat(&"strength", 6), "Не хватает силы нести чемодан по лестнице")],
					[Effect.advance_time(25, "Помощь с багажом"), Effect.change_state(&"energy", -10), Effect.change_money(70), Effect.practice_skill(&"cargo_handling", &"legacy_station_luggage"), Effect.deferred(&"muscle_soreness", 240, {"energy": -5}, &"station_porter_soreness", &"station_porter_offer")]
				),
				_choice(
					"station_porter_offer.find_cart", "Найти свободную багажную тележку",
					"Вы замечаете тележку за колонной и решаете задачу без надрыва.",
					[Condition.with_reason(Condition.stat(&"luck", 6), "Свободная тележка попадается не всегда")],
					[Effect.advance_time(15, "Поиск тележки"), Effect.change_money(40), Effect.change_state(&"mental_state", 4), Effect.shift_polarity(&"uncertainty_behavior", -3)]
				),
				_choice(
					"station_porter_offer.point_way", "Показать, где стоят тележки",
					"Вы подсказываете направление и не берётесь за неподходящую нагрузку.", [],
					[Effect.advance_time(5, "Подсказка пассажирам"), Effect.change_state(&"mental_state", 2)]
				),
			]
		),
		_card(
			"station_lost_wallet", "lost_property", "station_square",
			"Кошелёк под скамьёй", "Под скамьёй лежит кошелёк с документами. Дежурный смотрит в другую сторону, а поезд только что отправился.",
			[
				_choice(
					"station_lost_wallet.find_owner", "Догнать владельца",
					"По билету и времени отправления вы понимаете, где искать человека.",
					[Condition.with_reason(Condition.stat(&"intelligence", 6), "Нужно сопоставить билет, платформу и расписание")],
					[Effect.advance_time(25, "Возврат кошелька"), Effect.change_state(&"energy", -6), Effect.change_state(&"mental_state", 8), Effect.deferred(&"owner_favor", 180, {"money": 60}, &"station_wallet_favor", &"station_lost_wallet")]
				),
				_choice(
					"station_lost_wallet.hand_to_clerk", "Передать в справочную",
					"Сотрудница записывает находку и убирает кошелёк в сейф.",
					[Condition.with_reason(Condition.stat(&"charisma", 4), "Нужно объяснить сотруднице, где лежал кошелёк")],
					[Effect.advance_time(12, "Передача кошелька"), Effect.change_state(&"mental_state", 4), Effect.knowledge(&"station_desk", 1, &"unlock")]
				),
				_choice(
					"station_lost_wallet.leave", "Не трогать находку",
					"Вы оставляете кошелёк на виду у камеры и отходите.", [],
					[Effect.advance_time(2, "Отказ от находки"), Effect.shift_polarity(&"decision_priority", 2)]
				),
			]
		),
		_card(
			"station_cardboard", "public_order", "station_square",
			"Картон у служебной двери", "Работник складывает у контейнера большие сухие листы картона. Рядом проходит вокзальный дежурный.",
			[
				_choice(
					"station_cardboard.ask", "Попросить один лист",
					"Работник разрешает забрать картон, если не оставлять мусор на площади.",
					[Condition.with_reason(Condition.stat(&"charisma", 5), "Нужно обратиться к работнику, не вызывая подозрений")],
					[Effect.advance_time(8, "Разговор у контейнера"), Effect.add_item(&"cardboard_sheet"), Effect.change_state(&"mental_state", 3)]
				),
				_choice(
					"station_cardboard.walk_past", "Пройти мимо",
					"Вы не привлекаете внимание дежурного.", [],
					[Effect.advance_time(3, "Осмотр служебного двора"), Effect.change_state(&"tension", -1)]
				),
			]
		),
		_card(
			"recycling_sorting_trial", "job_entry", "recycling_point",
			"Пробная смена", "Хозяин пункта предлагает короткую смену: шесть задач по сортировке и разгрузке, оплата сразу после работы.",
			[
				_choice(
					"recycling_sorting_trial.accept", "Выйти на смену",
					"Хозяин выдаёт перчатки и показывает рабочую площадку.",
					[
						Condition.with_reason(Condition.state(&"energy", 30), "Слишком мало сил для смены"),
						Condition.with_reason(Condition.state(&"hunger", 85, Condition.LESS_OR_EQUAL), "Сильный голод делает смену опасной"),
					],
					[Effect.knowledge(&"recycling_job", 1, &"unlock")]
				),
				_choice(
					"recycling_sorting_trial.inspect", "Сначала изучить маркировку",
					"Вы разбираетесь в таблице категорий и запоминаете основные обозначения.",
					[Condition.with_reason(Condition.stat(&"intelligence", 6), "Нужно быстро разобраться в промышленной маркировке")],
					[Effect.advance_time(15, "Изучение правил сортировки"), Effect.knowledge(&"recycling_rules", 1, &"unlock"), Effect.shift_polarity(&"attention_distribution", -4)]
				),
				_choice(
					"recycling_sorting_trial.ask_terms", "Уточнить оплату и правила",
					"Хозяин ценит прямой разговор и обещает позвать вас, если понадобится ещё одна смена.",
					[Condition.with_reason(Condition.skill(&"trade", 1), "Нужен опыт делового разговора")],
					[Effect.advance_time(10, "Разговор с хозяином пункта"), Effect.knowledge(&"recycling_terms", 1, &"unlock"), Effect.deferred(&"shift_offer", 360, {"location_id": "recycling_point"}, &"recycling_future_shift", &"recycling_sorting_trial")]
				),
				_choice(
					"recycling_sorting_trial.decline", "Пока отказаться",
					"Хозяин пожимает плечами: работа останется до вечера.", [],
					[Effect.advance_time(3, "Отказ от смены")]
				),
			]
		),
		_card(
			"recycling_scale_dispute", "territory_conflict", "recycling_point",
			"Спор у весов", "Клиент уверен, что весы показывают меньше положенного. Приёмщик раздражён, очередь начинает шуметь.",
			[
				_choice(
					"recycling_scale_dispute.check", "Проверить нулевую отметку",
					"Под платформой застрял кусок проволоки. После проверки весы снова показывают ровно.",
					[Condition.with_reason(Condition.stat(&"intelligence", 6), "Нужно понимать, как исключить простую ошибку измерения")],
					[Effect.advance_time(12, "Проверка весов"), Effect.knowledge(&"recycling_rules", 1, &"unlock"), Effect.practice_skill(&"repair", &"legacy_scales_check"), Effect.change_state(&"mental_state", 4)]
				),
				_choice(
					"recycling_scale_dispute.mediate", "Предложить повторное взвешивание",
					"Спор заканчивается после контрольного замера на пустой таре.",
					[Condition.with_reason(Condition.skill(&"trade", 1), "Нужен навык торговли, чтобы предложить приемлемую процедуру")],
					[Effect.advance_time(10, "Улаживание спора"), Effect.change_state(&"tension", -4), Effect.mastery(1), Effect.shift_polarity(&"influence_style", 4)]
				),
				_choice(
					"recycling_scale_dispute.wait", "Подождать в стороне",
					"Через несколько минут хозяин сам прекращает спор.", [],
					[Effect.advance_time(10, "Ожидание у весов"), Effect.change_state(&"tension", 2)]
				),
			]
		),
		_card(
			"recycling_useful_scrap", "recyclable_search", "recycling_point",
			"Полка с мелким ломом", "На выбраковочной полке лежат провод, крепёж и детали старой техники. Хозяин разрешает взять одну вещь.",
			[
				_choice(
					"recycling_useful_scrap.choose", "Выбрать полезную деталь",
					"Вы находите целый кусок провода и небольшой исправный зажим.",
					[Condition.with_reason(Condition.skill(&"repair", 1), "Нужен навык ремонта, чтобы узнать исправную деталь")],
					[Effect.advance_time(10, "Выбор деталей"), Effect.add_item(&"scrap_wire"), Effect.mastery(1)]
				),
				_choice(
					"recycling_useful_scrap.leave", "Ничего не брать",
					"Без понятной цели лишний металл будет только мешать.", [],
					[Effect.advance_time(2, "Осмотр выбраковочной полки"), Effect.shift_polarity(&"decision_priority", 2)]
				),
			]
		),
		_card(
			"clinic_tea_window", "food_opportunity", "clinic_yard",
			"Чай из служебного окна", "Сотрудница открывает окно, чтобы проветрить кабинет. На подоконнике стоит чайник и пакет с простой едой.",
			[
				_choice(
					"clinic_tea_window.ask", "Попросить горячей воды и еды",
					"Сотрудница наливает чай и отдаёт бутерброд, оставшийся после дежурства.",
					[Condition.with_reason(Condition.stat(&"charisma", 5), "Нужно спокойно объяснить свою ситуацию")],
					[Effect.advance_time(15, "Разговор у служебного окна"), Effect.change_state(&"hunger", -18), Effect.change_state(&"mental_state", 6), Effect.shift_polarity(&"influence_style", 3)]
				),
				_choice(
					"clinic_tea_window.leave", "Не беспокоить сотрудников",
					"Вы садитесь на скамью и даёте себе несколько минут отдыха.", [],
					[Effect.advance_time(10, "Отдых во дворе"), Effect.change_state(&"energy", 4), Effect.change_state(&"tension", -3)]
				),
			]
		),
		_card(
			"clinic_blister", "minor_health", "clinic_yard",
			"Сбитая нога", "После долгой ходьбы пятка саднит. Кожа повреждена, а впереди ещё целый день на ногах.",
			[
				_choice(
					"clinic_blister.dress", "Обработать и закрыть повреждение",
					"Простая повязка уменьшает боль и не натирает при ходьбе.",
					[Condition.with_reason(Condition.skill(&"first_aid", 1), "Нужен базовый навык первой помощи")],
					[Effect.advance_time(15, "Перевязка ноги"), Effect.change_state(&"health", 3), Effect.change_state(&"tension", -4), Effect.mastery(1)]
				),
				_choice(
					"clinic_blister.improvise", "Сделать мягкую прокладку",
					"Сложенная ткань защищает пятку от дальнейшего трения.",
					[Condition.with_reason(Condition.stat(&"intelligence", 5), "Нужно понять, как снять давление с повреждённого места")],
					[Effect.advance_time(12, "Уход за ногой"), Effect.change_state(&"health", 1), Effect.knowledge(&"wound_care", 1, &"unlock"), Effect.shift_polarity(&"execution_style", 3)]
				),
				_choice(
					"clinic_blister.ignore", "Идти дальше как есть",
					"Боль пока терпима, но повреждение может стать серьёзнее.", [],
					[Effect.advance_time(3, "Осмотр повреждённой ноги"), Effect.deferred(&"blister_worsens", 180, {"health": -6, "energy": -4}, &"clinic_blister_aftereffect", &"clinic_blister")]
				),
			]
		),
		_card(
			"clinic_notice_board", "local_information", "clinic_yard",
			"Объявления во дворе", "На доске висят часы работы, адрес бесплатной столовой, памятка по уходу за мелкими ранами и сведения для тех, кому негде ночевать.",
			[
				_choice(
					"clinic_notice_board.read", "Разобраться в объявлениях",
					"Вы находите полезный адрес, запоминаете правила простой перевязки и замечаете расписание служебной калитки.",
					[Condition.with_reason(Condition.stat(&"intelligence", 4), "Нужно сопоставить несколько старых объявлений")],
					[Effect.advance_time(12, "Чтение объявлений"), Effect.knowledge(&"clinic_back_gate", 1, &"unlock"), Effect.knowledge(&"cheap_canteen", 1, &"unlock"), Effect.practice_skill(&"first_aid", &"legacy_clinic_notices"), Effect.shift_polarity(&"attention_distribution", -3)]
				),
				_choice(
					"clinic_notice_board.rest", "Просто передохнуть у доски",
					"Двор остаётся тихим, и короткий отдых немного успокаивает.", [],
					[Effect.advance_time(10, "Отдых у поликлиники"), Effect.change_state(&"energy", 3), Effect.change_state(&"tension", -3)]
				),
			]
		),
		_card(
			"embankment_fisher", "street_contact", "embankment",
			"Рыбак у парапета", "Мужчина складывает снасти и недовольно смотрит на порванный ремень своего ящика.",
			[
				_choice(
					"embankment_fisher.talk", "Разговориться о районе",
					"Рыбак рассказывает, где на набережной не проверяют по ночам, и обещает запомнить вас.",
					[Condition.with_reason(Condition.stat(&"charisma", 6), "Нужно поддержать ненавязчивый разговор")],
					[Effect.advance_time(18, "Разговор с рыбаком"), Effect.knowledge(&"embankment_shelter", 1, &"unlock"), Effect.deferred(&"fisher_remembers", 420, {"location_id": "embankment"}, &"embankment_fisher_memory", &"embankment_fisher")]
				),
				_choice(
					"embankment_fisher.fix_strap", "Поправить ремень ящика",
					"Зажим из проволоки держит ремень. Рыбак делится хлебом в благодарность.",
					[Condition.with_reason(Condition.skill(&"repair", 1), "Нужен навык мелкого ремонта")],
					[Effect.advance_time(15, "Ремонт рыбацкого ящика"), Effect.change_state(&"hunger", -12), Effect.change_state(&"mental_state", 5), Effect.mastery(1)]
				),
				_choice(
					"embankment_fisher.pass", "Не мешать и пройти дальше",
					"Вы оставляете рыбака со снастями и продолжаете путь вдоль воды.", [],
					[Effect.advance_time(5, "Прогулка по набережной"), Effect.change_state(&"tension", -2)]
				),
			]
		),
		_card(
			"embankment_cold_wind", "weather", "embankment",
			"Ветер с реки", "Ветер резко усиливается. Открытая набережная быстро остывает, а ближайшие здания стоят в стороне.",
			[
				_choice(
					"embankment_cold_wind.plan_route", "Идти вдоль защищённой стены",
					"Путь длиннее, зато стена закрывает от самых сильных порывов.",
					[Condition.with_reason(Condition.stat(&"intelligence", 5), "Нужно заранее оценить направление ветра")],
					[Effect.advance_time(25, "Путь вдоль стены"), Effect.change_state(&"energy", -5), Effect.shift_polarity(&"decision_priority", 4)]
				),
				_choice(
					"embankment_cold_wind.return", "Вернуться к освещённым улицам",
					"Вы уходите с открытого берега до наступления холода.", [],
					[Effect.advance_time(20, "Возвращение с набережной"), Effect.change_state(&"energy", -7), Effect.change_state(&"tension", 2)]
				),
			]
		),
		_card(
			"embankment_bottles", "recyclable_search", "embankment",
			"Следы после пикника", "На газоне остались бутылки и банки. Большую часть уже собрали, но кое-что могло закатиться под скамьи.",
			[
				_choice(
					"embankment_bottles.search", "Проверить неприметные места",
					"Под дальней скамьёй находится целый пакет сухих банок.",
					[Condition.with_reason(Condition.stat(&"luck", 6), "Полезная находка попадается не каждый раз")],
					[Effect.advance_time(15, "Поиск вторсырья"), Effect.add_item(&"recyclables", 3), Effect.change_state(&"mental_state", 4)]
				),
				_choice(
					"embankment_bottles.route", "Собрать вдоль удобного маршрута",
					"Вы проходите набережную без лишних кругов и набираете небольшой мешок.",
					[Condition.with_reason(Condition.skill(&"city_navigation", 1), "Нужен навык ориентирования, чтобы не тратить силы впустую")],
					[Effect.advance_time(18, "Сбор вторсырья по маршруту"), Effect.add_item(&"recyclables", 2), Effect.change_state(&"energy", -5), Effect.mastery(1)]
				),
				_choice(
					"embankment_bottles.visible", "Поднять то, что видно сразу",
					"На виду остаётся несколько банок — немного, но лучше, чем ничего.", [],
					[Effect.advance_time(10, "Сбор банок"), Effect.add_item(&"recyclables"), Effect.change_state(&"energy", -3)]
				),
			]
		),
		_card(
			"embankment_nightfall", "evening_shelter", "embankment",
			"Сумерки у воды", "Фонари загораются один за другим. Под лодочным навесом сухо, но бетон холодный, а ветер ночью усилится.",
			[
				_choice(
					"embankment_nightfall.improvise", "Утеплить место картоном",
					"Картон отделяет тело от бетона и закрывает нижнюю щель в стене.",
					[Condition.with_reason(Condition.item(&"cardboard_sheet"), "Нужен хотя бы один лист сухого картона")],
					[Effect.advance_time(15, "Подготовка места под навесом"), Effect.knowledge(&"embankment_shelter", 1, &"unlock"), Effect.shift_polarity(&"execution_style", 3)]
				),
				_choice(
					"embankment_nightfall.find_boathouse", "Осмотреть лодочную станцию",
					"Боковая стенка закрывает угол от ветра, а дорожка сюда почти не просматривается.",
					[Condition.with_reason(Condition.stat(&"luck", 7), "Нужно случайно заметить неприметный проход")],
					[Effect.advance_time(10, "Осмотр лодочной станции"), Effect.knowledge(&"embankment_shelter", 1, &"unlock"), Effect.change_state(&"mental_state", 4)]
				),
				_choice(
					"embankment_nightfall.stay_exposed", "Остаться под открытым навесом",
					"Место найдено, но ночь обещает быть холодной.", [],
					[Effect.advance_time(8, "Подготовка к ночи у воды"), Effect.change_state(&"tension", 5), Effect.deferred(&"cold_night", 480, {"health": -8, "energy": -4}, &"embankment_cold_night", &"embankment_nightfall")]
				),
			]
		),
	]


## A road between districts. Walking one is not on offer: the point of another
## district is that reaching it costs a fare and a departure you can miss.
static func _line(
	destination_id: String,
	mode_id: String,
	title: String,
	minutes: int,
	fare: int,
	opens_minute: int,
	closes_minute: int
) -> Dictionary:
	return {
		"destination_id": destination_id,
		"walk_minutes": 0,
		"transport": {
			"mode": mode_id,
			"title": title,
			"minutes": minutes,
			"fare": fare,
			"opens_minute": opens_minute,
			"closes_minute": closes_minute,
		},
	}


static func _route(destination_id: String, walk_minutes: int, fare: int = -1, bus_minutes: int = -1) -> Dictionary:
	var value := {
		"destination_id": destination_id,
		"walk_minutes": walk_minutes,
	}
	if fare >= 0 and bus_minutes > 0:
		value["fare"] = fare
		value["bus_minutes"] = bus_minutes
	return value


static func _luck_weights(values: Array) -> Dictionary:
	var result: Dictionary = {}
	for index in range(values.size()):
		result[str(index + 1)] = values[index]
	return result


static func _card(
	card_id: String,
	family_id: String,
	location_id: String,
	title: String,
	text: String,
	choices: Array,
	weight: int = 10
) -> Dictionary:
	return {
		"id": card_id,
		"family_id": family_id,
		"location_id": location_id,
		"title": title,
		"text": text,
		"weight": weight,
		"once": true,
		"tags": [family_id],
		"conditions": [],
		"choices": choices,
	}


static func _choice(
	choice_id: String,
	label: String,
	outcome: String,
	conditions: Array = [],
	effects: Array = [],
	extra: Dictionary = {}
) -> Dictionary:
	var value := {
		"id": choice_id,
		"label": label,
		"text": label,
		"outcome": outcome,
		"conditions": conditions,
		"effects": effects,
	}
	for key in extra:
		value[key] = extra[key]
	return value


static func _job_choice(choice_id: String, label: String, score: int, conditions: Array = []) -> Dictionary:
	return {
		"id": choice_id,
		"label": label,
		"text": label,
		"score": score,
		"conditions": conditions,
	}


static func _sort_by_id(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("id", "")) < String(right.get("id", ""))

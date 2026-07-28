class_name FirstDayContent
extends RefCounted

## Data-only catalog for the first playable day.
##
## The catalog deliberately returns plain Dictionaries and Arrays. Conditions
## and effects are constructed through the M1 rules API, so the same content can
## later be moved to JSON without changing the session flow.

const DISTRICT_ID := "riverside_central"
const REQUIRED_LOCATION_IDS := [
	"underpass",
	"market",
	"station_square",
	"recycling_point",
	"clinic_yard",
	"embankment",
	"freight_yard",
	"courtyard_blocks",
]


static func district() -> Dictionary:
	return {
		"id": DISTRICT_ID,
		"title": "Приречный район",
		"description": "Старый район между вокзалом и рекой: шумный рынок, дворы учреждений и несколько мест, где можно переждать ночь.",
		"location_ids": REQUIRED_LOCATION_IDS.duplicate(),
	}


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
		},	}


static func location(location_id: String) -> Dictionary:
	var value: Variant = locations().get(location_id, {})
	return value.duplicate(true) if value is Dictionary else {}


static func routes_from(location_id: String) -> Array:
	var place := location(location_id)
	return _array_copy(place.get("routes", []))


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
					Effect.unlock_skill(&"cargo_handling"),
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
					Effect.unlock_skill(&"cargo_handling"),
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
					[Condition.with_reason(Condition.skill(&"cooking", 1), "Нужен хотя бы базовый навык готовки")],
					[Effect.advance_time(12, "Сбор продуктов"), Effect.add_item(&"simple_meal"), Effect.mastery(1)]
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
					[Effect.advance_time(10, "Разговоры у рынка"), Effect.knowledge(&"district_landmarks", 1, &"unlock"), Effect.unlock_skill(&"city_navigation"), Effect.unlock_skill(&"cooking"), Effect.shift_polarity(&"attention_distribution", 3)]
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
					[Effect.advance_time(40, "Разгрузка у рынка"), Effect.change_state(&"energy", -14), Effect.change_state(&"hunger", 8), Effect.change_money(90), Effect.unlock_skill(&"cargo_handling")]
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
					[Effect.advance_time(35, "Оплаченная помощь у рынка"), Effect.change_state(&"energy", -10), Effect.change_money(105), Effect.unlock_skill(&"trade"), Effect.shift_polarity(&"influence_style", 4)]
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
					[Effect.advance_time(25, "Помощь с багажом"), Effect.change_state(&"energy", -10), Effect.change_money(70), Effect.unlock_skill(&"cargo_handling"), Effect.deferred(&"muscle_soreness", 240, {"energy": -5}, &"station_porter_soreness", &"station_porter_offer")]
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
					[Effect.advance_time(12, "Проверка весов"), Effect.knowledge(&"recycling_rules", 1, &"unlock"), Effect.unlock_skill(&"repair"), Effect.change_state(&"mental_state", 4)]
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
					[Effect.advance_time(12, "Чтение объявлений"), Effect.knowledge(&"clinic_back_gate", 1, &"unlock"), Effect.knowledge(&"cheap_canteen", 1, &"unlock"), Effect.unlock_skill(&"first_aid"), Effect.shift_polarity(&"attention_distribution", -3)]
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


static func _array_copy(value: Variant) -> Array:
	return value.duplicate(true) if value is Array else []


static func _sort_by_id(left: Dictionary, right: Dictionary) -> bool:
	return String(left.get("id", "")) < String(right.get("id", ""))


static func validate_condition_packet(
	raw_conditions: Variant,
	context: String = "content"
) -> Dictionary:
	var errors: Array = []
	if not raw_conditions is Array:
		errors.append("Условия в %s должны быть массивом" % context)
	else:
		_validate_conditions(raw_conditions, context, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static func validate_effect_packet(
	raw_effects: Variant,
	context: String = "content"
) -> Dictionary:
	var errors: Array = []
	if not raw_effects is Array:
		errors.append("Эффекты в %s должны быть массивом" % context)
	else:
		_validate_effects(raw_effects, context, errors)
	return {"ok": errors.is_empty(), "errors": errors}


static var _validation_cache: Dictionary = {}


## The first-day content is a static literal: it cannot change while the game
## runs, yet every session validation re-derived and re-checked all of it.
## The answer is computed once and handed out as a copy.
static func validate_content() -> Dictionary:
	if _validation_cache.is_empty():
		_validation_cache = _validate_content_uncached()
	return _validation_cache.duplicate(true)


static func reset_validation_cache_for_tests() -> void:
	_validation_cache = {}


static func _validate_content_uncached() -> Dictionary:
	var errors: Array = []
	var place_map := locations()
	var cards := event_cards()
	var starts := start_situations()
	var shelter_map := shelters()
	var family_ids: Dictionary = {}
	var choice_ids: Dictionary = {}
	var deferred_ids: Dictionary = {}
	var route_count := 0
	var choice_count := 0
	var deferred_count := 0

	var district_data := district()
	if String(district_data.get("id", "")) != DISTRICT_ID:
		errors.append("Район имеет неверный id")
	_validate_display_text(String(district_data.get("title", "")), "название района", errors)
	_validate_display_text(String(district_data.get("description", "")), "описание района", errors)
	# M4 grows the district to eight and allows twelve. The floor is what the
	# week needs; the ceiling is what one district can stay legible at.
	if place_map.size() < 6 or place_map.size() > 12:
		errors.append("В районе должно быть от 6 до 12 локаций")
	for required_id in REQUIRED_LOCATION_IDS:
		if not place_map.has(required_id):
			errors.append("Отсутствует обязательная локация: %s" % required_id)

	for key in place_map:
		var place: Variant = place_map[key]
		if not place is Dictionary:
			errors.append("Локация %s должна быть Dictionary" % key)
			continue
		var place_id := String(place.get("id", ""))
		if place_id != String(key) or not _valid_identifier(place_id):
			errors.append("Некорректный id локации: %s" % key)
		if String(place.get("district_id", "")) != DISTRICT_ID:
			errors.append("Локация %s относится к неизвестному району" % place_id)
		if String(place.get("title", "")).strip_edges().is_empty():
			errors.append("У локации %s нет названия" % place_id)
		_validate_display_text(String(place.get("title", "")), "название локации %s" % place_id, errors)
		_validate_display_text(String(place.get("description", "")), "описание локации %s" % place_id, errors)
		if String(place.get("background_id", "")).strip_edges().is_empty():
			errors.append("У локации %s нет background_id" % place_id)
		var routes := _array_copy(place.get("routes", []))
		route_count += routes.size()
		for route_value in routes:
			if not route_value is Dictionary:
				errors.append("Маршрут из %s должен быть Dictionary" % place_id)
				continue
			var destination_id := String(route_value.get("destination_id", ""))
			if not place_map.has(destination_id):
				errors.append("Маршрут из %s ведёт в неизвестную локацию %s" % [place_id, destination_id])
			if destination_id == place_id:
				errors.append("Маршрут %s не должен вести в исходную локацию" % place_id)
			if typeof(route_value.get("walk_minutes", null)) != TYPE_INT or int(route_value.get("walk_minutes", 0)) <= 0:
				errors.append("У маршрута %s -> %s неверное время пешком" % [place_id, destination_id])
			var has_fare: bool = route_value.has("fare")
			var has_bus_time: bool = route_value.has("bus_minutes")
			if has_fare != has_bus_time:
				errors.append("Автобусный маршрут %s -> %s должен содержать fare и bus_minutes вместе" % [place_id, destination_id])
			elif has_fare and (typeof(route_value["fare"]) != TYPE_INT or int(route_value["fare"]) < 0 or typeof(route_value["bus_minutes"]) != TYPE_INT or int(route_value["bus_minutes"]) <= 0):
				errors.append("У автобусного маршрута %s -> %s неверные параметры" % [place_id, destination_id])
	_validate_connected_map(place_map, errors)

	if starts.size() != 4:
		errors.append("Должно быть ровно 4 стартовые ситуации")
	var start_ids: Dictionary = {}
	var luck_totals: Dictionary = {}
	for luck in range(1, 11):
		luck_totals[str(luck)] = 0
	for start_value in starts:
		if not start_value is Dictionary:
			errors.append("Стартовая ситуация должна быть Dictionary")
			continue
		var start_id := String(start_value.get("id", ""))
		if not _valid_identifier(start_id) or start_ids.has(start_id):
			errors.append("Некорректный или повторный id старта: %s" % start_id)
		start_ids[start_id] = true
		_validate_display_text(String(start_value.get("title", "")), "название старта %s" % start_id, errors)
		_validate_display_text(String(start_value.get("text", "")), "текст старта %s" % start_id, errors)
		_validate_display_text(String(start_value.get("journal_message", "")), "запись старта %s" % start_id, errors)
		var start_location := String(start_value.get("location_id", ""))
		if not place_map.has(start_location):
			errors.append("Старт %s указывает неизвестную локацию" % start_id)
		var severity: Variant = start_value.get("severity", null)
		if typeof(severity) != TYPE_INT or int(severity) < 1 or int(severity) > 4:
			errors.append("Тяжесть старта %s должна быть от 1 до 4" % start_id)
		var opening_id := String(start_value.get("opening_event_id", ""))
		if not cards.has(opening_id):
			errors.append("Старт %s указывает неизвестную opening event" % start_id)
		elif String(cards[opening_id].get("location_id", "")) != start_location:
			errors.append("Старт %s и его opening event находятся в разных локациях" % start_id)
		var weights: Variant = start_value.get("weights_by_luck", {})
		if not weights is Dictionary or weights.size() != 10:
			errors.append("Старт %s должен иметь 10 весов Удачи" % start_id)
		else:
			for luck in range(1, 11):
				var luck_key := str(luck)
				var weight: Variant = weights.get(luck_key, null)
				if typeof(weight) != TYPE_INT or int(weight) < 0:
					errors.append("У старта %s неверный вес для Удачи %d" % [start_id, luck])
				else:
					luck_totals[luck_key] = int(luck_totals[luck_key]) + int(weight)
		var start_conditions := _array_copy(start_value.get("conditions", []))
		if not start_conditions.is_empty():
			errors.append("Старт %s не должен иметь условий: старт выбирается только весом Удачи" % start_id)
		var initial_effects := _array_copy(start_value.get("initial_effects", []))
		var session_effects := _array_copy(start_value.get("effects", []))
		if initial_effects != session_effects:
			errors.append("У старта %s расходятся initial_effects и effects" % start_id)
		_validate_effects(initial_effects, "старт %s" % start_id, errors)
		_validate_start_effects(initial_effects, start_id, errors)
		_validate_effect_packet_runtime(initial_effects, "старт %s" % start_id, errors)
	for luck in range(1, 11):
		if int(luck_totals[str(luck)]) <= 0:
			errors.append("Для Удачи %d нет доступного стартового веса" % luck)

	if cards.size() < 20 or cards.size() > 25:
		errors.append("Нужно от 20 до 25 карточек событий")
	for key in cards:
		var card_value: Variant = cards[key]
		if not card_value is Dictionary:
			errors.append("Карточка %s должна быть Dictionary" % key)
			continue
		var card_id := String(card_value.get("id", ""))
		if card_id != String(key) or not _valid_identifier(card_id):
			errors.append("Некорректный id карточки: %s" % key)
		var family_id := String(card_value.get("family_id", ""))
		if not _valid_identifier(family_id):
			errors.append("Карточка %s имеет неверный family_id" % card_id)
		else:
			family_ids[family_id] = true
		if not place_map.has(String(card_value.get("location_id", ""))):
			errors.append("Карточка %s относится к неизвестной локации" % card_id)
		if String(card_value.get("title", "")).strip_edges().is_empty() or String(card_value.get("text", "")).strip_edges().is_empty():
			errors.append("Карточка %s должна иметь название и текст" % card_id)
		_validate_display_text(String(card_value.get("title", "")), "название карточки %s" % card_id, errors)
		_validate_display_text(String(card_value.get("text", "")), "текст карточки %s" % card_id, errors)
		_validate_conditions(_array_copy(card_value.get("conditions", [])), "карточка %s" % card_id, errors)
		var choices: Variant = card_value.get("choices", [])
		if not choices is Array or choices.is_empty():
			errors.append("Карточка %s не содержит вариантов" % card_id)
			continue
		var has_unconditional := false
		choice_count += choices.size()
		for choice_value in choices:
			if not choice_value is Dictionary:
				errors.append("Вариант карточки %s должен быть Dictionary" % card_id)
				continue
			var choice_id := String(choice_value.get("id", ""))
			if not _valid_identifier(choice_id, true) or choice_ids.has(choice_id):
				errors.append("Некорректный или повторный id варианта: %s" % choice_id)
			choice_ids[choice_id] = true
			if not choice_id.begins_with(card_id + "."):
				errors.append("Id варианта %s не начинается с id карточки" % choice_id)
			if String(choice_value.get("label", "")).strip_edges().is_empty() or String(choice_value.get("outcome", "")).strip_edges().is_empty():
				errors.append("Вариант %s должен иметь label и outcome" % choice_id)
			_validate_display_text(String(choice_value.get("label", "")), "текст варианта %s" % choice_id, errors)
			_validate_display_text(String(choice_value.get("outcome", "")), "результат варианта %s" % choice_id, errors)
			var conditions := _array_copy(choice_value.get("conditions", []))
			if conditions.is_empty():
				has_unconditional = true
			_validate_conditions(conditions, "вариант %s" % choice_id, errors)
			var effects := _array_copy(choice_value.get("effects", []))
			_validate_effects(effects, "вариант %s" % choice_id, errors)
			_validate_guarded_costs(conditions, effects, "вариант %s" % choice_id, errors)
			_validate_deferred_references(effects, card_id, deferred_ids, errors)
			if conditions.is_empty():
				_validate_effect_packet_runtime(effects, "безусловный вариант %s" % choice_id, errors)
			deferred_count += _count_deferred(effects)
		if not has_unconditional:
			errors.append("Карточка %s не имеет безусловного выхода" % card_id)

	if family_ids.size() < 12 or family_ids.size() > 15:
		errors.append("Нужно от 12 до 15 семейств событий")
	if choice_count < 45 or choice_count > 70:
		errors.append("Нужно от 45 до 70 вариантов ответа")
	if deferred_count < 8 or deferred_count > 12:
		errors.append("Нужно от 8 до 12 отложенных эффектов")

	var job_data := job()
	_validate_job(job_data, place_map, errors)
	_validate_skill_reachability(cards, job_data, errors)
	if shelter_map.size() != 4:
		errors.append("Должно быть ровно 4 варианта ночлега")
	var has_open_shelter := false
	for key in shelter_map:
		var shelter_value: Variant = shelter_map[key]
		if not shelter_value is Dictionary:
			errors.append("Ночлег %s должен быть Dictionary" % key)
			continue
		var shelter_id := String(shelter_value.get("id", ""))
		if shelter_id != String(key) or not _valid_identifier(shelter_id):
			errors.append("Некорректный id ночлега: %s" % key)
		if not place_map.has(String(shelter_value.get("location_id", ""))):
			errors.append("Ночлег %s находится в неизвестной локации" % shelter_id)
		_validate_display_text(String(shelter_value.get("title", "")), "название ночлега %s" % shelter_id, errors)
		_validate_display_text(String(shelter_value.get("description", "")), "описание ночлега %s" % shelter_id, errors)
		var shelter_conditions := _array_copy(shelter_value.get("conditions", []))
		if shelter_conditions.is_empty():
			has_open_shelter = true
		_validate_conditions(shelter_conditions, "ночлег %s" % shelter_id, errors)
		var shelter_effects := _array_copy(shelter_value.get("effects", []))
		_validate_effects(shelter_effects, "ночлег %s" % shelter_id, errors)
		_validate_guarded_costs(shelter_conditions, shelter_effects, "ночлег %s" % shelter_id, errors)
		_validate_effect_packet_runtime(shelter_effects, "ночлег %s" % shelter_id, errors)
	if not has_open_shelter:
		errors.append("Нужен хотя бы один безусловный ночлег")
	_validate_unlockable_references(cards, shelter_map, errors)
	_validate_start_reachability(starts, job_data, shelter_map, place_map, errors)

	return {
		"ok": errors.is_empty(),
		"errors": errors,
		"counts": {
			"districts": 1,
			"locations": place_map.size(),
			"routes": route_count,
			"starts": starts.size(),
			"event_families": family_ids.size(),
			"event_cards": cards.size(),
			"event_choices": choice_count,
			"deferred_effects": deferred_count,
			"jobs": 1,
			"job_prompts": _array_copy(job_data.get("minigame", {}).get("prompts", [])).size(),
			"shelters": shelter_map.size(),
		},
	}


static func _validate_connected_map(place_map: Dictionary, errors: Array) -> void:
	if place_map.is_empty():
		return
	for origin_value in place_map.keys():
		var origin_id := String(origin_value)
		var visited := _reachable_locations(origin_id, place_map)
		if visited.size() != place_map.size():
			errors.append("Из локации %s нельзя добраться до всех точек района" % origin_id)


static func _validate_conditions(conditions: Array, context: String, errors: Array) -> void:
	const VALID_KINDS := ["stat", "state", "money", "item", "polarity", "skill", "knowledge"]
	const VALID_OPERATORS := [">=", ">", "==", "!=", "<", "<="]
	for condition_value in conditions:
		if not condition_value is Dictionary:
			errors.append("Условие в %s должно быть Dictionary" % context)
			continue
		var kind := String(condition_value.get("kind", condition_value.get("type", "")))
		var identifier := String(condition_value.get("id", ""))
		var operator := String(condition_value.get("operator", ">="))
		var raw_value: Variant = condition_value.get("value", null)
		if kind not in VALID_KINDS:
			errors.append("В %s используется неизвестный вид условия: %s" % [context, kind])
		if operator not in VALID_OPERATORS:
			errors.append("В %s используется неизвестный оператор: %s" % [context, operator])
		if kind != "money" and identifier.is_empty():
			errors.append("В %s условие %s не имеет id" % [context, kind])
		if condition_value.has("blocked_reason"):
			_validate_display_text(String(condition_value.get("blocked_reason", "")), "причина блокировки в %s" % context, errors)
		match kind:
			"stat":
				if not GameRules.is_known_characteristic(identifier):
					errors.append("В %s указана неизвестная характеристика: %s" % [context, identifier])
				if not _is_number(raw_value) or float(raw_value) < GameRules.CHARACTERISTIC_MIN or float(raw_value) > GameRules.CHARACTERISTIC_MAX:
					errors.append("В %s порог характеристики вне диапазона 1..10" % context)
			"state":
				if not GameRules.is_known_meter(identifier):
					errors.append("В %s указана неизвестная шкала состояния: %s" % [context, identifier])
				if not _is_number(raw_value) or float(raw_value) < GameRules.METER_MIN or float(raw_value) > GameRules.METER_MAX:
					errors.append("В %s порог состояния вне диапазона 0..100" % context)
			"money":
				if typeof(raw_value) != TYPE_INT or int(raw_value) < 0 or int(raw_value) > GameRules.MONEY_MAX:
					errors.append("В %s указан неверный денежный порог" % context)
			"item":
				if not _valid_identifier(identifier) or typeof(raw_value) != TYPE_INT or int(raw_value) < GameRules.INVENTORY_QUANTITY_MIN or int(raw_value) > GameRules.INVENTORY_QUANTITY_MAX:
					errors.append("В %s указано неверное условие предмета" % context)
			"polarity":
				if not GameRules.is_stored_polarity(identifier):
					errors.append("В %s указана неизвестная полярность: %s" % [context, identifier])
				if not _is_number(raw_value) or float(raw_value) < GameRules.POLARITY_MIN or float(raw_value) > GameRules.POLARITY_MAX:
					errors.append("В %s порог полярности вне допустимого диапазона" % context)
			"skill":
				if not GameRules.is_known_skill(identifier):
					errors.append("В %s указан неизвестный навык: %s" % [context, identifier])
				if typeof(raw_value) != TYPE_INT or int(raw_value) < 1 or int(raw_value) > GameRules.SKILL_MAX_RANK:
					errors.append("В %s указан неверный ранг навыка" % context)
			"knowledge":
				# Zero is not a stored knowledge level, but it is a valid
				# requirement for data that must run only before discovery.
				if not _valid_identifier(identifier) or typeof(raw_value) != TYPE_INT or int(raw_value) < 0 or int(raw_value) > GameRules.KNOWLEDGE_LEVEL_MAX:
					errors.append("В %s указано неверное условие знания" % context)


static func _validate_effects(effects: Array, context: String, errors: Array) -> void:
	const VALID_TYPES := [
		"advance_time", "change_state", "change_money", "add_item", "remove_item",
		"shift_polarity", "unlock_skill", "advance_skill", "mastery", "deferred", "knowledge",
	]
	var total_advance_minutes := 0
	for effect_value in effects:
		if not effect_value is Dictionary:
			errors.append("Эффект в %s должен быть Dictionary" % context)
			continue
		var effect_type := String(effect_value.get("type", ""))
		var identifier := String(effect_value.get("id", ""))
		if effect_type not in VALID_TYPES:
			errors.append("В %s используется неизвестный эффект: %s" % [context, effect_type])
			continue
		match effect_type:
			"advance_time":
				var minutes: Variant = effect_value.get("minutes", null)
				if typeof(minutes) != TYPE_INT or int(minutes) <= 0 or int(minutes) > GameRules.MAX_TIME_ADVANCE_MINUTES:
					errors.append("В %s указано неверное изменение времени" % context)
				else:
					total_advance_minutes += int(minutes)
			"change_state":
				if not GameRules.is_known_meter(identifier) or typeof(effect_value.get("delta", null)) != TYPE_INT:
					errors.append("В %s указано неверное изменение состояния" % context)
			"change_money":
				var money_delta: Variant = effect_value.get("delta", null)
				if typeof(money_delta) != TYPE_INT or absi(int(money_delta)) > GameRules.MONEY_MAX:
					errors.append("В %s указано неверное изменение денег" % context)
			"add_item", "remove_item":
				if not _valid_identifier(identifier) or typeof(effect_value.get("quantity", null)) != TYPE_INT or int(effect_value.get("quantity", 0)) < GameRules.INVENTORY_QUANTITY_MIN or int(effect_value.get("quantity", 0)) > GameRules.INVENTORY_QUANTITY_MAX:
					errors.append("В %s указан неверный предметный эффект" % context)
			"shift_polarity":
				if not GameRules.is_stored_polarity(identifier) or typeof(effect_value.get("delta", null)) != TYPE_INT:
					errors.append("В %s указан неверный сдвиг полярности" % context)
			"unlock_skill":
				if not GameRules.is_known_skill(identifier) or typeof(effect_value.get("rank", null)) != TYPE_INT or int(effect_value.get("rank", 0)) < 1 or int(effect_value.get("rank", 0)) > GameRules.SKILL_MAX_RANK:
					errors.append("В %s указан неверный навык для открытия" % context)
			"advance_skill":
				if not GameRules.is_known_skill(identifier) or typeof(effect_value.get("ranks", null)) != TYPE_INT or int(effect_value.get("ranks", 0)) <= 0:
					errors.append("В %s указано неверное развитие навыка" % context)
			"mastery":
				if typeof(effect_value.get("delta", null)) != TYPE_INT or int(effect_value.get("delta", 0)) <= 0:
					errors.append("В %s указано неверное изменение мастерства" % context)
			"deferred":
				var effect_id := String(effect_value.get("effect_id", ""))
				var delay: Variant = effect_value.get("delay_minutes", null)
				if not _valid_identifier(effect_id):
					errors.append("Отложенный эффект в %s не имеет effect_id" % context)
				if typeof(delay) != TYPE_INT or int(delay) < 0 or int(delay) > GameRules.MAX_TIME_ADVANCE_MINUTES:
					errors.append("Отложенный эффект в %s имеет неверную задержку" % context)
				if not effect_value.get("payload", {}) is Dictionary:
					errors.append("Отложенный эффект в %s должен иметь payload-словарь" % context)
			"knowledge":
				var knowledge_mode := String(effect_value.get("mode", "add"))
				if not _valid_identifier(identifier) or typeof(effect_value.get("amount", null)) != TYPE_INT or int(effect_value.get("amount", 0)) <= 0 or knowledge_mode not in ["add", "advance", "unlock", "set", "remove"]:
					errors.append("В %s указано неверное изменение знания" % context)
	if total_advance_minutes > GameRules.MAX_TIME_ADVANCE_MINUTES:
		errors.append("Пакет эффектов в %s превышает предел изменения времени" % context)


static func _validate_job(job_data: Dictionary, place_map: Dictionary, errors: Array) -> void:
	var job_id := String(job_data.get("id", ""))
	if not _valid_identifier(job_id):
		errors.append("У работы неверный id")
	if not place_map.has(String(job_data.get("location_id", ""))):
		errors.append("Работа находится в неизвестной локации")
	_validate_display_text(String(job_data.get("title", "")), "название работы %s" % job_id, errors)
	_validate_display_text(String(job_data.get("description", "")), "описание работы %s" % job_id, errors)
	_validate_conditions(_array_copy(job_data.get("entry_conditions", [])), "работа %s" % job_id, errors)
	var minigame: Variant = job_data.get("minigame", {})
	if not minigame is Dictionary:
		errors.append("Мини-игра работы должна быть Dictionary")
		return
	var prompts := _array_copy(minigame.get("prompts", []))
	if not _valid_identifier(String(minigame.get("type", ""))):
		errors.append("Мини-игра работы имеет неверный type")
	if int(minigame.get("rounds_to_draw", 0)) != 6:
		errors.append("Смена первого дня должна состоять из 6 раундов")
	if prompts.size() < 6:
		errors.append("Для мини-игры нужно не менее 6 задач")
	var prompt_ids: Dictionary = {}
	var prompt_choice_ids: Dictionary = {}
	var maximum_total_score := 0
	for prompt_value in prompts:
		if not prompt_value is Dictionary:
			errors.append("Задача мини-игры должна быть Dictionary")
			continue
		var prompt_id := String(prompt_value.get("id", ""))
		if not _valid_identifier(prompt_id) or prompt_ids.has(prompt_id):
			errors.append("Некорректный или повторный id задачи: %s" % prompt_id)
		prompt_ids[prompt_id] = true
		_validate_display_text(String(prompt_value.get("text", "")), "текст задачи %s" % prompt_id, errors)
		var prompt_choices := _array_copy(prompt_value.get("choices", []))
		if prompt_choices.is_empty():
			errors.append("Задача %s не имеет вариантов" % prompt_id)
		var has_open_choice := false
		var prompt_max_score := -2_147_483_648
		for prompt_choice in prompt_choices:
			if not prompt_choice is Dictionary:
				errors.append("Вариант задачи %s должен быть Dictionary" % prompt_id)
				continue
			var prompt_choice_id := String(prompt_choice.get("id", ""))
			if not _valid_identifier(prompt_choice_id) or prompt_choice_ids.has(prompt_choice_id):
				errors.append("Некорректный или повторный id ответа мини-игры: %s" % prompt_choice_id)
			prompt_choice_ids[prompt_choice_id] = true
			_validate_display_text(String(prompt_choice.get("label", "")), "ответ мини-игры %s" % prompt_choice_id, errors)
			var conditions := _array_copy(prompt_choice.get("conditions", []))
			if conditions.is_empty():
				has_open_choice = true
			_validate_conditions(conditions, "задача %s" % prompt_id, errors)
			if typeof(prompt_choice.get("score", null)) != TYPE_INT:
				errors.append("Вариант задачи %s должен иметь целый score" % prompt_id)
			else:
				prompt_max_score = maxi(prompt_max_score, int(prompt_choice.get("score", 0)))
		if not has_open_choice:
			errors.append("Задача %s не имеет безусловного варианта" % prompt_id)
		if prompt_max_score == -2_147_483_648:
			errors.append("Задача %s не имеет корректного score" % prompt_id)
		else:
			maximum_total_score += prompt_max_score
	var tiers := _array_copy(job_data.get("result_tiers", []))
	if tiers.is_empty():
		errors.append("Работа не имеет уровней результата")
	for tier_value in tiers:
		if not tier_value is Dictionary:
			errors.append("Уровень результата работы должен быть Dictionary")
			continue
		var tier_id := String(tier_value.get("id", ""))
		if not _valid_identifier(tier_id):
			errors.append("Уровень результата работы имеет неверный id: %s" % tier_id)
		if typeof(tier_value.get("min_score", null)) != TYPE_INT or typeof(tier_value.get("max_score", null)) != TYPE_INT or int(tier_value.get("min_score", 0)) > int(tier_value.get("max_score", 0)):
			errors.append("Уровень результата %s имеет неверный диапазон" % tier_id)
		_validate_display_text(String(tier_value.get("label", "")), "название результата %s" % tier_id, errors)
		var tier_effects := _array_copy(tier_value.get("effects", []))
		_validate_effects(tier_effects, "результат %s" % tier_id, errors)
		_validate_guarded_costs([], tier_effects, "результат %s" % tier_id, errors)
		_validate_effect_packet_runtime(tier_effects, "результат %s" % tier_id, errors)
	for score in range(maximum_total_score + 1):
		var matching_tiers := 0
		for tier_value in tiers:
			if tier_value is Dictionary and score >= int(tier_value.get("min_score", 0)) and score <= int(tier_value.get("max_score", -1)):
				matching_tiers += 1
		if matching_tiers != 1:
			errors.append("Для результата работы %d должно существовать ровно одно итоговое состояние" % score)


static func _validate_start_effects(effects: Array, start_id: String, errors: Array) -> void:
	const RESOURCE_EFFECTS := [
		"change_money", "add_item", "remove_item", "unlock_skill",
		"advance_skill", "mastery", "knowledge",
	]
	for effect_value in effects:
		if effect_value is Dictionary and String(effect_value.get("type", "")) in RESOURCE_EFFECTS:
			errors.append("Старт %s не должен выдавать деньги, предметы, знания или навыки" % start_id)


static func _validate_guarded_costs(
	conditions: Array,
	effects: Array,
	context: String,
	errors: Array
) -> void:
	for effect_value in effects:
		if not effect_value is Dictionary:
			continue
		var effect_type := String(effect_value.get("type", ""))
		if effect_type == "change_money":
			var delta := int(effect_value.get("delta", 0))
			if delta < 0 and not _has_sufficient_guard(conditions, "money", "", -delta):
				errors.append("Расход денег в %s не защищён достаточным условием money" % context)
		elif effect_type == "remove_item":
			var item_id := String(effect_value.get("id", ""))
			var quantity := int(effect_value.get("quantity", 0))
			if not _has_sufficient_guard(conditions, "item", item_id, quantity):
				errors.append("Расход предмета %s в %s не защищён достаточным условием item" % [item_id, context])


static func _has_sufficient_guard(
	conditions: Array,
	kind: String,
	identifier: String,
	required_amount: int
) -> bool:
	for condition_value in conditions:
		if not condition_value is Dictionary:
			continue
		if String(condition_value.get("kind", "")) != kind:
			continue
		if kind != "money" and String(condition_value.get("id", "")) != identifier:
			continue
		var value := int(condition_value.get("value", 0))
		var operator := String(condition_value.get("operator", ">="))
		if operator == ">=" and value >= required_amount:
			return true
		if operator == ">" and value + 1 >= required_amount:
			return true
		if operator == "==" and value >= required_amount:
			return true
	return false


static func _validate_deferred_references(
	effects: Array,
	card_id: String,
	deferred_ids: Dictionary,
	errors: Array
) -> void:
	for effect_value in effects:
		if not effect_value is Dictionary or String(effect_value.get("type", "")) != "deferred":
			continue
		var deferred_id := String(effect_value.get("deferred_id", ""))
		var effect_id := String(effect_value.get("effect_id", ""))
		var source_id := String(effect_value.get("source_id", ""))
		if not _valid_identifier(deferred_id):
			errors.append("Отложенное последствие %s должно иметь стабильный deferred_id" % effect_id)
		elif deferred_ids.has(deferred_id):
			errors.append("Повторный deferred_id: %s" % deferred_id)
		else:
			deferred_ids[deferred_id] = true
		if not _valid_identifier(effect_id):
			errors.append("Некорректный effect_id отложенного последствия в карточке %s" % card_id)
		if source_id != card_id:
			errors.append("Отложенное последствие %s должно ссылаться на исходную карточку %s" % [deferred_id, card_id])


static func _validate_effect_packet_runtime(effects: Array, context: String, errors: Array) -> void:
	var state := RunState.new(GameRules.DEFAULT_CHARACTERISTICS, GameRules.DEFAULT_RNG_SEED)
	var result := ActionTransaction.execute(state, {
		"id": "content_validation",
		"title": "Проверка контента",
		"conditions": [],
		"effects": effects,
	})
	if not result.success:
		errors.append("Пакет эффектов «%s» не исполняется: %s — %s" % [context, String(result.code), result.message])


static func _validate_skill_reachability(cards: Dictionary, job_data: Dictionary, errors: Array) -> void:
	var producers: Dictionary = {}
	for card_value in cards.values():
		if not card_value is Dictionary:
			continue
		var card_id := String(card_value.get("id", ""))
		for choice_value in _array_copy(card_value.get("choices", [])):
			if not choice_value is Dictionary:
				continue
			var conditions := _array_copy(choice_value.get("conditions", []))
			for effect_value in _array_copy(choice_value.get("effects", [])):
				if not effect_value is Dictionary or String(effect_value.get("type", "")) != "unlock_skill":
					continue
				var skill_id := String(effect_value.get("id", ""))
				if _condition_requires_skill(conditions, skill_id):
					continue
				if not producers.has(skill_id):
					producers[skill_id] = []
				producers[skill_id].append(card_id)

	for card_value in cards.values():
		if not card_value is Dictionary:
			continue
		var consumer_card_id := String(card_value.get("id", ""))
		for choice_value in _array_copy(card_value.get("choices", [])):
			if choice_value is Dictionary:
				_validate_skill_conditions_have_producer(
					_array_copy(choice_value.get("conditions", [])),
					consumer_card_id,
					producers,
					errors
				)

	var minigame: Variant = job_data.get("minigame", {})
	if minigame is Dictionary:
		for prompt_value in _array_copy(minigame.get("prompts", [])):
			if not prompt_value is Dictionary:
				continue
			for choice_value in _array_copy(prompt_value.get("choices", [])):
				if choice_value is Dictionary:
					_validate_skill_conditions_have_producer(
						_array_copy(choice_value.get("conditions", [])),
						"@job",
						producers,
						errors
					)


static func _validate_skill_conditions_have_producer(
	conditions: Array,
	consumer_id: String,
	producers: Dictionary,
	errors: Array
) -> void:
	for condition_value in conditions:
		if not condition_value is Dictionary or String(condition_value.get("kind", "")) != "skill":
			continue
		var skill_id := String(condition_value.get("id", ""))
		var producer_cards := _array_copy(producers.get(skill_id, []))
		var reachable := false
		for producer_id in producer_cards:
			if consumer_id == "@job" or String(producer_id) != consumer_id:
				reachable = true
				break
		if not reachable:
			errors.append("Навык %s требуется в %s, но его нельзя освоить заранее в первом дне" % [skill_id, consumer_id])


static func _condition_requires_skill(conditions: Array, skill_id: String) -> bool:
	for condition_value in conditions:
		if condition_value is Dictionary and String(condition_value.get("kind", "")) == "skill" and String(condition_value.get("id", "")) == skill_id:
			return true
	return false


static func _validate_unlockable_references(cards: Dictionary, shelter_map: Dictionary, errors: Array) -> void:
	var item_producers: Dictionary = {}
	var knowledge_producers: Dictionary = {}
	for card_value in cards.values():
		if not card_value is Dictionary:
			continue
		var card_id := String(card_value.get("id", ""))
		for choice_value in _array_copy(card_value.get("choices", [])):
			if not choice_value is Dictionary:
				continue
			for effect_value in _array_copy(choice_value.get("effects", [])):
				if not effect_value is Dictionary:
					continue
				var effect_type := String(effect_value.get("type", ""))
				var identifier := String(effect_value.get("id", ""))
				if effect_type == "add_item":
					_append_producer(item_producers, identifier, card_id)
				elif effect_type == "knowledge" and String(effect_value.get("mode", "add")) in ["add", "advance", "unlock", "set"] and int(effect_value.get("amount", 0)) > 0:
					_append_producer(knowledge_producers, identifier, card_id)

	for card_value in cards.values():
		if not card_value is Dictionary:
			continue
		var card_id := String(card_value.get("id", ""))
		for choice_value in _array_copy(card_value.get("choices", [])):
			if choice_value is Dictionary:
				_validate_unlockable_conditions(
					_array_copy(choice_value.get("conditions", [])),
					card_id,
					item_producers,
					knowledge_producers,
					errors
				)
	for shelter_value in shelter_map.values():
		if shelter_value is Dictionary:
			_validate_unlockable_conditions(
				_array_copy(shelter_value.get("conditions", [])),
				"@shelter",
				item_producers,
				knowledge_producers,
				errors
			)


static func _validate_unlockable_conditions(
	conditions: Array,
	consumer_id: String,
	item_producers: Dictionary,
	knowledge_producers: Dictionary,
	errors: Array
) -> void:
	for condition_value in conditions:
		if not condition_value is Dictionary:
			continue
		var kind := String(condition_value.get("kind", ""))
		if kind not in ["item", "knowledge"]:
			continue
		var identifier := String(condition_value.get("id", ""))
		var producer_map := item_producers if kind == "item" else knowledge_producers
		var producer_cards := _array_copy(producer_map.get(identifier, []))
		var reachable := false
		for producer_id in producer_cards:
			if consumer_id.begins_with("@") or String(producer_id) != consumer_id:
				reachable = true
				break
		if not reachable:
			errors.append("Требование %s:%s в %s нельзя получить заранее в первом дне" % [kind, identifier, consumer_id])


static func _append_producer(producers: Dictionary, identifier: String, card_id: String) -> void:
	if not producers.has(identifier):
		producers[identifier] = []
	if card_id not in producers[identifier]:
		producers[identifier].append(card_id)


static func _validate_start_reachability(
	starts: Array,
	job_data: Dictionary,
	shelter_map: Dictionary,
	place_map: Dictionary,
	errors: Array
) -> void:
	var open_shelter_locations: Array = []
	for shelter_value in shelter_map.values():
		if shelter_value is Dictionary and _array_copy(shelter_value.get("conditions", [])).is_empty():
			open_shelter_locations.append(String(shelter_value.get("location_id", "")))
	var job_location := String(job_data.get("location_id", ""))
	var job_conditions := _array_copy(job_data.get("entry_conditions", []))
	for start_value in starts:
		if not start_value is Dictionary:
			continue
		var start_id := String(start_value.get("id", ""))
		var start_location := String(start_value.get("location_id", ""))
		var reachable := _reachable_locations(start_location, place_map)
		if not reachable.has(job_location):
			errors.append("Из старта %s географически недоступна работа" % start_id)
		var shelter_reachable := false
		for shelter_location in open_shelter_locations:
			if reachable.has(String(shelter_location)):
				shelter_reachable = true
				break
		if not shelter_reachable:
			errors.append("Из старта %s недоступен безусловный ночлег" % start_id)
		var state := RunState.new(GameRules.DEFAULT_CHARACTERISTICS, GameRules.DEFAULT_RNG_SEED)
		var start_result := ActionTransaction.execute(state, {
			"id": "validate_start_reachability",
			"title": "Проверка старта",
			"conditions": [],
			"effects": _array_copy(start_value.get("initial_effects", [])),
		})
		if not start_result.success:
			continue
		var job_check := CheckResolver.evaluate_all(state, job_conditions)
		if not bool(job_check.get("allowed", false)):
			errors.append("После старта %s базовые условия работы недостижимы без восстановления" % start_id)


static func _reachable_locations(origin_id: String, place_map: Dictionary) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array = [origin_id]
	while not queue.is_empty():
		var current_id := String(queue.pop_front())
		if visited.has(current_id) or not place_map.has(current_id):
			continue
		visited[current_id] = true
		for route_value in _array_copy(place_map[current_id].get("routes", [])):
			if route_value is Dictionary:
				var destination_id := String(route_value.get("destination_id", ""))
				if not visited.has(destination_id):
					queue.append(destination_id)
	return visited


static func _validate_display_text(value: String, context: String, errors: Array) -> void:
	var text := value.strip_edges()
	if text.is_empty():
		errors.append("Пустой пользовательский текст: %s" % context)
		return
	var has_cyrillic := false
	for index in range(text.length()):
		var code := text.unicode_at(index)
		if (code >= 0x0410 and code <= 0x044f) or code == 0x0401 or code == 0x0451:
			has_cyrillic = true
		if code == 0xfffd or (code < 32 and code not in [9, 10, 13]):
			errors.append("Повреждённый пользовательский текст: %s" % context)
			return
	if not has_cyrillic:
		errors.append("Пользовательский текст должен быть на русском: %s" % context)


static func _is_number(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT


static func _count_deferred(effects: Array) -> int:
	var result := 0
	for effect_value in effects:
		if effect_value is Dictionary and String(effect_value.get("type", "")) == "deferred":
			result += 1
	return result


static func _valid_identifier(value: String, allow_dot: bool = false) -> bool:
	if value.is_empty():
		return false
	var first_code := value.unicode_at(0)
	if first_code < 97 or first_code > 122:
		return false
	for index in range(value.length()):
		var code := value.unicode_at(index)
		var is_lower_letter := code >= 97 and code <= 122
		var is_digit := code >= 48 and code <= 57
		var is_underscore := code == 95
		var is_dot := allow_dot and code == 46
		if not (is_lower_letter or is_digit or is_underscore or is_dot):
			return false
	return true

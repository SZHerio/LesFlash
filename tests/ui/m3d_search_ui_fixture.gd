class_name M3dSearchUiFixture
extends RefCounted

const UiTheme := preload("res://ui/theme/m3_ui_theme.tres")


static func model(font_scale: float) -> Dictionary:
	return {
		"title": "Служебный двор под путепроводом",
		"subtitle": "Ходьба не тратит игровое время. Время меняют только подтверждённые действия.",
		"background_path": "res://assets/search/underpass_service_yard_v1.png",
		"world_size": [1648, 960],
		"hero": {"position": [785, 474], "path_index": 0},
		"path": [],
		"psyche_intensity": 0.65,
		"reduced_motion": false,
		"font_scale": font_scale,
		"risk": {
			"score": 30,
			"noise": 3,
			"trespass": 1,
			"repeated_attempts": 2,
			"warning_threshold": 35,
			"label": "Растёт",
		},
		"objects": [{
			"id": "open_dumpster",
			"title": "Открытый контейнер",
			"type": "open",
			"position": [785, 474],
			"interaction_radius": 112,
			"state": "available",
			"revealed": true,
			"interacted": false,
			"approaches": [
				{
					"id": "sort_by_hand",
					"title": "Перебрать содержимое руками",
					"enabled": false,
					"blocked_reasons": ["Нужны целые рабочие перчатки."],
					"cost_text": "Время: 12 мин. · Энергия: −2 · Шум: +1",
				},
				{
					"id": "search_slowly",
					"title": "Осмотреть содержимое по слоям",
					"enabled": true,
					"blocked_reasons": [],
					"cost_text": "Время: 18 мин. · Энергия: −1",
				},
			],
		}],
		"loot_tray": [{
			"stack_id": "ground:loot:1",
			"item_id": "scrap_wire",
			"title": "Моток провода",
			"quantity": 1,
			"condition": 64,
			"mass_text": "180 г",
			"volume_text": "240 мл",
			"target_container_id": "pockets",
		}],
		"quick_search": {
			"visible": true,
			"enabled": true,
			"blocked_reason": "",
		},
	}


static func capacity_model() -> Dictionary:
	return {
		"incoming": {
			"stack_id": "ground:loot:1",
			"title": "Моток медного провода",
			"quantity": 1,
			"mass_grams": 180,
			"volume_ml": 240,
		},
		"container_id": "hands",
		"capacity": {
			"mass_used_grams": 4300,
			"mass_capacity_grams": 4400,
			"volume_used_ml": 2900,
			"volume_capacity_ml": 3000,
		},
		"comparison": [{
			"stack_id": "stack:coat",
			"title": "Старая куртка",
			"mass_grams": 1200,
			"volume_ml": 2100,
		}],
		"recoveries": ["choose_other_container", "replace", "leave_at_source"],
	}


static func scaled_theme(scale: float) -> Theme:
	var result := UiTheme.duplicate(true) as Theme
	result.default_font_size = int(round(float(UiTheme.default_font_size) * scale))
	return result

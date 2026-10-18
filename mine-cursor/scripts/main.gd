extends Node2D
# Главный скрипт игры. Делает:
# 1) раскладывает камни сеткой и выкладывает новые, когда поле зачищено,
# 2) ломает камни под кистью, пока зажата левая кнопка мыши,
# 3) рисует кольцо кисти, осколки и интерфейс (счётчик + панель улучшений).

# preload загружает скрипт камня заранее, чтобы создавать из него новые камни.
const RockScript := preload("res://scripts/rock.gd")

# Описание улучшений. Чтобы добавить новое, дописываем строку сюда
# (и одну строку в _apply_upgrades).
#   base_cost — цена первого уровня, growth — во сколько раз дорожает каждый следующий,
#   step — на сколько растёт параметр за уровень.
const UPGRADES := {
	"damage": {"title": "Урон",         "base_cost": 10.0, "growth": 1.6, "max_level": 10, "step": 30.0},
	"radius": {"title": "Радиус кисти", "base_cost": 15.0, "growth": 1.7, "max_level": 10, "step": 15.0},
}

const PANEL_WIDTH := 260.0                 # ширина правой панели в пикселях
const ACCENT := Color(0.96, 0.72, 0.26)    # фирменный янтарный цвет интерфейса

# Стартовые значения. Меняются в Инспекторе справа (узел Main).
@export var base_damage: float = 60.0         # урон в секунду без улучшений
@export var base_brush_radius: float = 70.0   # радиус кисти без улучшений
@export var columns: int = 9                  # камней в ряду
@export var rows: int = 6                     # рядов
@export var spacing: float = 84.0             # расстояние между центрами камней

# Текущие значения (с учётом купленных улучшений).
var damage_per_second: float
var brush_radius: float

var levels: Dictionary = {"damage": 0, "radius": 0}  # уровни улучшений
var buttons: Dictionary = {}                          # кнопки улучшений по названию
var crystals: int = 0                                 # кристаллы игрока
var rocks_left: int = 0                               # камней на поле
var play_width: float = 0.0                           # ширина игрового поля (без панели)

var ring: Node2D           # узел с кольцом кисти
var crystal_label: Label   # счётчик кристаллов
var label_tween: Tween     # анимация «подпрыгивания» счётчика


func _ready() -> void:
	play_width = get_viewport_rect().size.x - PANEL_WIDTH
	damage_per_second = base_damage
	brush_radius = base_brush_radius

	_build_ui()
	_spawn_rocks()

	# Кольцо рисуем на отдельном узле с большим z_index, иначе камни закроют его.
	ring = Node2D.new()
	ring.z_index = 100
	ring.draw.connect(_draw_ring)  # сигнал draw: «мне пора рисоваться»
	add_child(ring)


# ---------- Интерфейс ----------

func _build_ui() -> void:
	# CanvasLayer — слой интерфейса поверх игры, он не двигается вместе с миром.
	var layer := CanvasLayer.new()
	add_child(layer)

	# Счётчик кристаллов слева вверху.
	crystal_label = Label.new()
	crystal_label.position = Vector2(24, 16)
	crystal_label.add_theme_font_size_override("font_size", 32)
	crystal_label.add_theme_color_override("font_color", ACCENT)
	layer.add_child(crystal_label)

	# Правая панель улучшений.
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(PANEL_WIDTH, 0)
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.08, 0.09, 0.12)
	panel_style.border_width_left = 2
	panel_style.border_color = Color(0.20, 0.22, 0.28)
	panel_style.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", panel_style)
	layer.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)  # прижать к правому краю на всю высоту

	# VBoxContainer раскладывает всё, что внутри, столбиком.
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	panel.add_child(column)

	var title := Label.new()
	title.text = "УЛУЧШЕНИЯ"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", ACCENT)
	column.add_child(title)

	# По кнопке на каждое улучшение из таблицы UPGRADES.
	for id in UPGRADES:
		var button := Button.new()
		button.custom_minimum_size = Vector2(0, 68)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.add_theme_font_size_override("font_size", 18)
		button.add_theme_color_override("font_disabled_color", Color(0.45, 0.47, 0.52))
		button.add_theme_stylebox_override("normal", _button_style(Color(0.14, 0.16, 0.21), Color(0.30, 0.33, 0.42)))
		button.add_theme_stylebox_override("hover", _button_style(Color(0.18, 0.21, 0.28), ACCENT))
		button.add_theme_stylebox_override("pressed", _button_style(Color(0.24, 0.27, 0.35), ACCENT))
		button.add_theme_stylebox_override("disabled", _button_style(Color(0.10, 0.11, 0.14), Color(0.20, 0.22, 0.28)))
		button.pressed.connect(_buy.bind(id))  # при нажатии вызвать _buy("damage") и т.п.
		column.add_child(button)
		buttons[id] = button

	_refresh_ui()


# Готовая «карточка стиля» для кнопки: фон, рамка, скруглённые углы.
func _button_style(bg: Color, border: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.border_color = border
	style.set_border_width_all(2)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(10)
	return style


# Обновляем надписи на кнопках и счётчик.
func _refresh_ui() -> void:
	crystal_label.text = "Кристаллы: %d" % crystals
	for id in UPGRADES:
		var info: Dictionary = UPGRADES[id]
		var level: int = levels[id]
		var button: Button = buttons[id]
		if level >= info["max_level"]:
			button.text = "%s\nМАКСИМУМ" % info["title"]
			button.disabled = true
		else:
			var cost := _cost(id)
			button.text = "%s   ур. %d\nЦена: %d" % [info["title"], level, cost]
			button.disabled = crystals < cost  # не хватает кристаллов — кнопка серая


# ---------- Улучшения ----------

# Цена следующего уровня: base_cost * growth^уровень (каждый раз дороже).
func _cost(id: String) -> int:
	var info: Dictionary = UPGRADES[id]
	return int(round(info["base_cost"] * pow(info["growth"], levels[id])))


func _buy(id: String) -> void:
	var info: Dictionary = UPGRADES[id]
	if levels[id] >= info["max_level"]:
		return
	var cost := _cost(id)
	if crystals < cost:
		return
	crystals -= cost
	levels[id] += 1
	_apply_upgrades()
	_refresh_ui()
	_pop(buttons[id])  # маленькая анимация «нажатия»


# Пересчитываем текущие параметры по уровням улучшений.
func _apply_upgrades() -> void:
	damage_per_second = base_damage + UPGRADES["damage"]["step"] * levels["damage"]
	brush_radius = base_brush_radius + UPGRADES["radius"]["step"] * levels["radius"]


# Анимация: элемент быстро чуть вырастает и возвращается. Tween — «аниматор» свойств.
func _pop(control: Control, strength: float = 1.08) -> void:
	control.pivot_offset = control.size / 2.0  # растём из центра
	var tween := create_tween()
	tween.tween_property(control, "scale", Vector2(strength, strength), 0.08)
	tween.tween_property(control, "scale", Vector2.ONE, 0.12)


# ---------- Камни ----------

func _spawn_rocks() -> void:
	var view := get_viewport_rect().size
	# Сетку центрируем в игровом поле (слева от панели).
	var start := Vector2(
		(play_width - (columns - 1) * spacing) / 2.0,
		(view.y - (rows - 1) * spacing) / 2.0
	)
	for row in rows:
		for col in columns:
			var rock := RockScript.new()
			rock.kind = _pick_kind()
			rock.position = start + Vector2(col * spacing, row * spacing)
			rock.add_to_group("rocks")  # метка «я камень»
			rock.destroyed.connect(_on_rock_destroyed)  # подписка на сигнал «разрушен»
			add_child(rock)
			rocks_left += 1


# Случайно выбираем вид: 50% мягкий, 35% обычный, 15% крепкий.
func _pick_kind() -> String:
	var roll := randf()
	if roll < 0.50:
		return "soft"
	elif roll < 0.85:
		return "medium"
	return "hard"


# Вызывается автоматически, когда любой камень сообщил «разрушен».
func _on_rock_destroyed(reward: int, pos: Vector2, color: Color) -> void:
	crystals += reward
	_refresh_ui()
	# Счётчик «подпрыгивает». Если прошлая анимация ещё идёт, останавливаем её.
	if label_tween:
		label_tween.kill()
	crystal_label.pivot_offset = Vector2(0, crystal_label.size.y / 2.0)
	label_tween = create_tween()
	label_tween.tween_property(crystal_label, "scale", Vector2(1.12, 1.12), 0.05)
	label_tween.tween_property(crystal_label, "scale", Vector2.ONE, 0.10)

	_spawn_shards(pos, color)
	rocks_left -= 1
	if rocks_left == 0:
		# Поле зачищено: ждём секунду и выкладываем новое.
		await get_tree().create_timer(1.0).timeout
		_spawn_rocks()


# Осколки: маленькие квадратики, которые разлетаются и гаснут.
func _spawn_shards(pos: Vector2, color: Color) -> void:
	var shards := CPUParticles2D.new()
	shards.position = pos
	shards.one_shot = true
	shards.explosiveness = 1.0
	shards.amount = 12
	shards.lifetime = 0.5
	shards.spread = 180.0
	shards.initial_velocity_min = 80.0
	shards.initial_velocity_max = 220.0
	shards.gravity = Vector2(0, 500)
	shards.scale_amount_min = 3.0
	shards.scale_amount_max = 6.0
	shards.color = color
	add_child(shards)
	shards.emitting = true
	shards.finished.connect(shards.queue_free)  # закончили — удаляем сами себя


# ---------- Кисть ----------

func _process(delta: float) -> void:
	var mouse := get_global_mouse_position()
	# Бьём камни, только если кнопка зажата и курсор на игровом поле, а не над панелью.
	if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and mouse.x < play_width:
		for rock in get_tree().get_nodes_in_group("rocks"):
			if mouse.distance_to(rock.global_position) <= brush_radius + rock.radius:
				rock.take_damage(damage_per_second * delta)
	ring.queue_redraw()  # каждый кадр двигаем кольцо за курсором


func _draw_ring() -> void:
	var mouse := ring.get_local_mouse_position()
	if mouse.x >= play_width:
		return  # над панелью кольцо не показываем
	ring.draw_arc(mouse, brush_radius, 0.0, TAU, 48, Color(1, 1, 1, 0.6), 2.0)

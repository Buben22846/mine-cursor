extends Node2D
# Один камень. Теперь камни бывают трёх видов, а бить их будет не сам камень,
# а главный скрипт main.gd (он знает, где курсор). Камень только хранит
# свою прочность, умеет получать урон и рисовать себя.

# const — «константа»: значение, которое не меняется во время игры.
# Здесь словарь (Dictionary): таблица «название → набор свойств», как карточки видов породы.
const TYPES := {
	"soft":   {"health": 30.0,  "radius": 26.0, "color": Color(0.80, 0.68, 0.45), "reward": 1},   # мягкая: быстро ломается, мало кристаллов
	"medium": {"health": 100.0, "radius": 32.0, "color": Color(0.50, 0.50, 0.52), "reward": 4},   # обычная
	"hard":   {"health": 250.0, "radius": 38.0, "color": Color(0.30, 0.38, 0.62), "reward": 15},  # крепкая жила: долго, но дорого
}

# Сигнал — «сообщение наружу». Камень кричит «я разрушен!» и передаёт, сколько кристаллов дал.
# Кто хочет — подписывается (так делает main.gd), а камню не нужно знать, кто его слушает.
signal destroyed(reward: int, pos: Vector2, color: Color)

# Вид камня. main.gd выставляет его ДО того, как камень попадёт в игру.
var kind: String = "medium"

var max_health: float = 100.0
var health: float = 100.0
var radius: float = 32.0
var base_color: Color = Color.GRAY
var reward: int = 4  # сколько кристаллов даёт за разрушение
var flash: float = 0.0  # сколько ещё секунд камень «дрожит и светлеет» после удара


func _ready() -> void:
	# Достаём из таблицы «карточку» нашего вида и копируем свойства в переменные.
	var card: Dictionary = TYPES[kind]
	max_health = card["health"]
	radius = card["radius"]
	base_color = card["color"]
	reward = card["reward"]
	health = max_health


# Вызывается из main.gd, когда кисть задела камень.
func take_damage(amount: float) -> void:
	if health <= 0.0:
		return  # уже разрушен, второй раз награду не даём
	health -= amount
	flash = 0.08  # включаем «реакцию на удар» на 0.08 секунды
	queue_redraw()  # просим Godot перерисовать камень
	if health <= 0.0:
		# сообщаем наружу: награда, где был камень и какого он цвета (для осколков)
		destroyed.emit(reward, global_position, base_color)
		queue_free()  # и удаляем камень из игры


func _process(delta: float) -> void:
	# Пока flash больше нуля, камень дрожит и светлее. Каждый кадр отнимаем время.
	if flash > 0.0:
		flash -= delta
		queue_redraw()


func _draw() -> void:
	# share — доля оставшейся прочности: 1.0 целый, 0.0 почти разбит.
	var share := health / max_health
	# По мере повреждений камень краснеет и уменьшается.
	var color := base_color.lerp(Color(0.85, 0.30, 0.20), 1.0 - share)
	var shake := Vector2.ZERO
	if flash > 0.0:
		color = color.lightened(0.35)  # при ударе камень светлеет
		shake = Vector2(randf_range(-2.0, 2.0), randf_range(-2.0, 2.0))  # и чуть дрожит
	draw_circle(shake, radius * (0.5 + 0.5 * share), color)

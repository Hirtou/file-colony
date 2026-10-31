extends Node2D
## Ставит камеру так, чтобы была видна вся карта.

func _ready() -> void:
	var b: Rect2 = $Map.bounds()
	var cam: Camera2D = $Camera
	cam.position = b.get_center()
	var vp := get_viewport_rect().size
	var z := minf(vp.x / b.size.x, vp.y / b.size.y) * 0.9
	cam.zoom = Vector2(z, z)

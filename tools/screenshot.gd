extends SceneTree
## Запускает главную сцену (из настроек проекта) и сохраняет screenshots/latest.png
## Аргументы после --: --rot=<рад> (поворот всех планет), --out=<имя.png>,
## --view=map|city|house (сразу на материк C:), --lang=ru|en

func _initialize() -> void:
	var rot := NAN
	var out := "latest.png"
	var view := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--view="):
			view = a.trim_prefix("--view=")
		elif a.begins_with("--rot="):
			rot = a.trim_prefix("--rot=").to_float()
		elif a.begins_with("--out="):
			out = a.trim_prefix("--out=")
	var scene: Node = load(ProjectSettings.get_setting("application/run/main_scene")).instantiate()
	root.add_child(scene)
	await process_frame  # _ready сцены уже прошёл
	var game := root.get_node_or_null("Game")
	if game and game._fps:
		game._fps.visible = false  # счётчик FPS на снимках не нужен (настройки не меняем)
	if not is_nan(rot) and "planets" in scene:
		for p in scene.planets:
			p.rot = rot
			p.spin_speed = 0.0
			p.vel = 0.0
	if view != "" and scene.has_method("debug_view"):
		scene.debug_view(view)
	for i in 10:
		await process_frame
	if "--fps" in OS.get_cmdline_user_args():
		# замер: 6 секунд работы, средний FPS
		var t0 := Time.get_ticks_msec()
		var frames := 0
		while Time.get_ticks_msec() - t0 < 6000:
			await process_frame
			frames += 1
		print("fps: ", frames / 6.0)
	await RenderingServer.frame_post_draw
	var path := ProjectSettings.globalize_path("res://screenshots/" + out)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var err := root.get_texture().get_image().save_png(path)
	print("screenshot: ", path, " err=", err)
	quit(err)

# The update on start (docs/release.md §7) against a local fake release, offline: an older nightly finds the newer
# one in the release's nightly.json, shows its line, downloads, checks and unpacks it beside a scratch game folder,
# and the swap puts it in place (the old one kept until cleanup); then setup's check on a scratch data folder whose
# steps never ran shows its line. Linux and macOS (tar).
#   IAF_DEFAULT_SETTINGS=1 godot --headless --audio-driver Dummy --path modern-iaf \
#     -s ../modern-iaf/tests/test_update.gd --log-file <temp>
extends "res://../tests/godot/base.gd"

const OLD := "0.1.0-nightly.20261101+aaaaaaa"
const NEW := "0.1.0-nightly.20261125+bbbbbbb"


func run() -> void:
	var updater: GDScript = load("res://shared/util/updater.gd")
	var tmp := OS.get_cache_dir().path_join("iaf-test-update-%d" % OS.get_process_id())
	var release := tmp.path_join("release")
	var app := tmp.path_join("Modern IAF")
	DirAccess.make_dir_recursive_absolute(release)
	DirAccess.make_dir_recursive_absolute(app)
	DirAccess.make_dir_recursive_absolute(tmp.path_join("src/Modern IAF"))
	FileAccess.open(app.path_join("v"), FileAccess.WRITE).store_string("1")
	FileAccess.open(tmp.path_join("src/Modern IAF/v"), FileAccess.WRITE).store_string("2")
	var name := "modern-iaf-nightly-linux-x86_64.tar.gz"
	var tgz := release.path_join(name)
	OS.execute("tar", ["-czf", tgz, "-C", tmp.path_join("src"), "Modern IAF"])
	var size := FileAccess.get_file_as_bytes(tgz).size()
	var entry := {"name": name, "version": NEW, "size": size, "sha256": FileAccess.get_sha256(tgz)}
	FileAccess.open(release.path_join("nightly.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"assets": [entry]})
	)
	OS.set_environment("IAF_UPDATE_NO_RESTART", "1")

	var u: CanvasLayer = updater.new()
	u.own = OLD
	u.app = app
	u.base = release
	u.os_name = "Linux"
	u.updates = tmp.path_join("updates")
	root.add_child(u)
	await frames(2)
	check(u.offer.get("version", "") == NEW and u.bar.visible, "the newer nightly is offered: " + u.line.text)
	check(u.line.text.contains(NEW) and u.update_button.visible, "its line names the version, with Update")
	u._on_update()
	for i in 300:
		if u.state in ["unpacked", "failed"]:
			break
		await process_frame
	var new := IafSetup.update_stage_dir(app).path_join("Modern IAF")
	check(u.state == "unpacked", "downloaded, checked and unpacked: " + u.state + " " + u.line.text)
	check(FileAccess.get_file_as_string(new.path_join("v")) == "2", "the new version is beside the game")
	check(IafSetup.update_swap(app, new) == "", "the swap")
	check(FileAccess.get_file_as_string(app.path_join("v")) == "2", "the game's folder holds the new version")
	var old := app.get_base_dir().path_join(".Modern IAF.old")
	check(FileAccess.get_file_as_string(old.path_join("v")) == "1", "the old version is kept until the new one starts")
	IafSetup.update_cleanup(app)
	check(not DirAccess.dir_exists_absolute(old), "cleanup removes the old version")
	u.queue_free()

	# A wrong checksum: refused, the game stays.
	entry.sha256 = "00" + entry.sha256.substr(2)
	FileAccess.open(release.path_join("nightly.json"), FileAccess.WRITE).store_string(
		JSON.stringify({"assets": [entry]})
	)
	u = updater.new()
	u.own = OLD
	u.app = app
	u.base = release
	u.os_name = "Linux"
	u.updates = tmp.path_join("updates")
	root.add_child(u)
	await frames(2)
	u._on_update()
	for i in 300:
		if u.state in ["unpacked", "failed"]:
			break
		await process_frame
	check(u.state == "failed" and u.bar.visible, "a download with another SHA-256 is refused: " + u.line.text)
	u.queue_free()

	# A data folder inside the game's folder: refused with its line.
	OS.set_environment("IAF_ASSETS_DIR", app.path_join("data"))
	u = updater.new()
	u.own = OLD
	u.app = app
	u.base = release
	u.os_name = "Linux"
	u.updates = tmp.path_join("updates")
	root.add_child(u)
	await frames(2)
	u._on_update()
	check(u.state == "failed" and u.line.text == u.s("data_inside"), "a data folder inside the game's: " + u.line.text)
	u.queue_free()
	OS.unset_environment("IAF_ASSETS_DIR")

	# The same version or none newer: no line; setup's check on a data folder whose steps never ran: its line.
	var assets := tmp.path_join("assets")
	DirAccess.make_dir_recursive_absolute(assets.path_join("converted/modern-iaf/missions"))
	OS.set_environment("IAF_ASSETS_DIR", assets)
	u = updater.new()
	u.own = NEW
	u.base = release
	u.os_name = "Linux"
	root.add_child(u)
	for i in 600:
		if u.state == "" or not is_instance_valid(u):
			break
		await process_frame
	check(is_instance_valid(u) and u.offer.is_empty(), "no newer nightly: no offer")
	check(is_instance_valid(u) and u.stale.size() >= 6 and u.bar.visible, "setup's steps to run again: " + u.line.text)
	if is_instance_valid(u):
		u.queue_free()
	OS.unset_environment("IAF_ASSETS_DIR")
	OS.execute("rm", ["-rf", tmp])

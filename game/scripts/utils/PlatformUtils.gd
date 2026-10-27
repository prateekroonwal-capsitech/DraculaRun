class_name PlatformUtils
extends Node

# PlatformUtils — platform detection helpers
# PDF §6 Time Complexity: get_platform() result is cached after first call.
#   OS.has_feature() is a C++ call — no need to re-evaluate it every frame.
# PDF §6 SOLID: one job — platform detection. Nothing else lives here.

# PDF §6: cached after first call — subsequent reads are O(1)
static var _platform: String = ""

static func get_platform() -> String:
	if not _platform.is_empty():
		return _platform   # O(1) cache hit
	if   OS.has_feature("ios"):     _platform = "ios"
	elif OS.has_feature("android"): _platform = "android"
	elif OS.has_feature("web"):     _platform = "web"
	elif OS.has_feature("windows"): _platform = "windows"
	elif OS.has_feature("macos"):   _platform = "macos"
	elif OS.has_feature("linux"):   _platform = "linux"
	else:                           _platform = "unknown"
	return _platform

static func is_mobile() -> bool:
	var p := get_platform()
	return p == "ios" or p == "android"   # O(1) — uses cached string

static func is_desktop() -> bool:
	var p := get_platform()
	return p == "windows" or p == "macos" or p == "linux"

static func is_web() -> bool:
	return get_platform() == "web"

static func get_device_id() -> String:
	return OS.get_unique_id()

static func get_locale() -> String:
	return OS.get_locale_language()

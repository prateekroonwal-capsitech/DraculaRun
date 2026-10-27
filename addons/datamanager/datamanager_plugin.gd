@tool
extends EditorPlugin

const CONFIG_AUTOLOAD = "DataManagerConfig"
const SIGNALS_AUTOLOAD = "DataManagerSignals"
const SYNC_AUTOLOAD = "SyncManager"
const DATA_AUTOLOAD = "DataManager"

func _enter_tree() -> void:
	# Registers singletons in order of dependency
	add_autoload_singleton(CONFIG_AUTOLOAD, "res://addons/datamanager/autoload/Config.gd")
	add_autoload_singleton(SIGNALS_AUTOLOAD, "res://addons/datamanager/autoload/Signals.gd")
	add_autoload_singleton(SYNC_AUTOLOAD, "res://addons/datamanager/autoload/SyncManager.gd")
	add_autoload_singleton(DATA_AUTOLOAD, "res://addons/datamanager/autoload/DataManager.gd")
	print("[DataManager Addon] Singletons registered and activated.")

func _exit_tree() -> void:
	# Removes singletons when plugin is disabled
	remove_autoload_singleton(CONFIG_AUTOLOAD)
	remove_autoload_singleton(SIGNALS_AUTOLOAD)
	remove_autoload_singleton(SYNC_AUTOLOAD)
	remove_autoload_singleton(DATA_AUTOLOAD)
	print("[DataManager Addon] Singletons deregistered and deactivated.")

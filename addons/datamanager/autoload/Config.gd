# class_name DataManagerConfig
# Holds configuration settings for the data management framework. Can be registered as an autoload or instantiated.
extends Node

# Logging Configuration
@export var log_level: String = "DEBUG":
	set(val):
		log_level = val
		DataManagerLogger.set_level_by_name(val)

# Local Storage Configuration
@export var local_save_directory: String = "user://saves"
@export var local_save_extension: String = ".json"
@export var encrypt_local_saves: bool = false
@export var encryption_key: String = "ChangeThisSecurityKey123!"

# Cloud Storage Configuration
@export var cloud_enabled: bool = false

@export var sync_on_save: bool = false:
	set(val):
		sync_on_save = val
		DataManagerLogger.info("sync_on_save changed at runtime to: %s" % str(val), "CONFIG")

@export var periodic_sync_enabled: bool = false:
	set(val):
		periodic_sync_enabled = val
		DataManagerLogger.info("periodic_sync_enabled changed at runtime to: %s" % str(val), "CONFIG")
		var sync_node = get_node_or_null("/root/SyncManager")
		if sync_node:
			# Automatically trigger timer setup update
			sync_node._setup_periodic_sync()

@export var sync_interval_seconds: float = 120.0:
	set(val):
		sync_interval_seconds = val
		var sync_node = get_node_or_null("/root/SyncManager")
		if sync_node:
			sync_node._setup_periodic_sync()

@export_enum("SingleDocument", "MultiCollection") var firestore_sync_mode: String = "SingleDocument"
@export var firestore_parent_collection: String = "users"
@export var segregate_by_platform: bool = true
@export_enum("platform_users", "users_platform", "platform_only") var collection_naming_style: String = "platform_users"

# Cloud merge policy. Options: "LatestTimestamp", "PreferCloud", "PreferLocal", "Manual"
@export var default_merge_policy: String = "LatestTimestamp"

# Retry/Backoff Parameters
@export var max_retry_attempts: int = 5
@export var retry_initial_delay: float = 1.0
@export var retry_multiplier: float = 2.0
@export var retry_max_delay: float = 30.0

# Auto Save Settings
@export var autosave_enabled: bool = true:
	set(val):
		autosave_enabled = val
		var dm = get_node_or_null("/root/DataManager")
		if dm:
			dm.configure_autosave(val, autosave_interval_seconds)

@export var autosave_interval_seconds: float = 300.0: # 5 minutes
	set(val):
		autosave_interval_seconds = val
		var dm = get_node_or_null("/root/DataManager")
		if dm:
			dm.configure_autosave(autosave_enabled, val)

@export var autosave_on_quit: bool = true
@export var autosave_on_pause: bool = true

func _ready() -> void:
	# Configure logger level automatically based on settings
	DataManagerLogger.set_level_by_name(log_level)
	
	# In release builds (exported non-debug), auto-enable encryption and use .dat extension
	if not OS.is_debug_build():
		encrypt_local_saves = true
		local_save_extension = ".dat"
		
	DataManagerLogger.info("Config loaded. Log level: %s, Encrypt: %s, Extension: %s" % [log_level, str(encrypt_local_saves), local_save_extension], "CONFIG")

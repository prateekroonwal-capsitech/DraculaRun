extends Node

# BackendService — initializes 3rd-party/backend services and data management
# PDF §2 Architecture: explicit separation for backend devs. Game devs do not touch this.
# Responsible for DataManager, Firebase, GameAnalytics, Ads SDK, Meta SDK, etc.

var data: Node
var data_signals: Node
var data_config: Node
var data_sync: Node

func _ready() -> void:
	data = get_node_or_null("/root/DataManager")
	data_signals = get_node_or_null("/root/DataManagerSignals")
	data_config = get_node_or_null("/root/DataManagerConfig")
	data_sync = get_node_or_null("/root/SyncManager")
	
	_init_firebase()
	_init_game_analytics()
	_init_ads_sdk()
	_init_meta_sdk()

# ── Service Stubs ──────────────────────────────────────────────────────────

func _init_firebase() -> void:
	# Stub for Firebase SDK initialization
	# e.g., Firebase.App.setup()
	pass

func _init_game_analytics() -> void:
	# Stub for GameAnalytics initialization
	pass

func _init_ads_sdk() -> void:
	# Stub for Ads integration (e.g. AdMob, AppLovin)
	pass

func _init_meta_sdk() -> void:
	# Stub for Meta SDK initialization
	pass

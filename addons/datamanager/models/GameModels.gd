# class_name GameModels
# Central schema definitions for all Unified Game Data Models.
# All domain models and developer sandbox models live here in a single file for easy discovery and editing.
class_name GameModels

# ==============================================================================
# 1. Identity & Account Bucket
# ==============================================================================
class IdentityData extends BaseModel:
	var user_id: String = ""
	var auth_provider: String = "guest" # "guest" | "google" | "apple" | "playgames"
	var signed_in: bool = false
	var email: Variant = null
	var fcm_token: String = ""

	func _init() -> void:
		schema_version = 1
		var uid = OS.get_unique_id()
		if not uid.is_empty():
			user_id = uid
		else:
			user_id = "user_%d" % int(Time.get_unix_time_from_system() * 1000.0)

# ==============================================================================
# 2. Player Profile Bucket
# ==============================================================================
class ProfileData extends BaseModel:
	var display_name: String = "Player"
	var is_custom_name: bool = false
	var avatar_id: String = "default"
	var frame_id: String = ""
	var badge_id: String = ""
	var country_code: String = ""
	var photo_url: Variant = null
	var player_title: String = "Novice"

	func _init() -> void:
		schema_version = 1
		var loc = OS.get_locale()
		if not loc.is_empty():
			var parts = loc.split("_")
			if parts.size() > 1:
				country_code = parts[1].to_upper()
			elif parts.size() == 1 and parts[0].length() == 2:
				country_code = parts[0].to_upper()

# ==============================================================================
# 3. Device & Hardware Bucket
# ==============================================================================
class DeviceData extends BaseModel:
	var app_version: String = "0.0.0"

	func _init() -> void:
		schema_version = 1
		var ver = ProjectSettings.get_setting("application/config/version", "1.0.0")
		if ver != null and not str(ver).is_empty():
			app_version = str(ver)

# ==============================================================================
# 4. System Metadata Bucket
# ==============================================================================
class MetadataData extends BaseModel:
	var revision: int = 1
	var created_at: float = 0.0
	var last_login_at: float = 0.0
	var last_saved_at: float = 0.0
	var dirty_buckets: Dictionary = {} # bucket_name -> boolean
	var values: Dictionary = {}        # legacy system key-values

	func _init() -> void:
		schema_version = 1
		var now = Time.get_unix_time_from_system()
		created_at = now
		last_login_at = now
		last_saved_at = now

# ==============================================================================
# 5. Session & Analytics Bucket
# ==============================================================================
class SessionData extends BaseModel:
	var screen_time_seconds: float = 0.0
	var last_session_date_utc: String = ""
	var session_count: int = 1

	func _init() -> void:
		schema_version = 1
		session_count = 1
		last_session_date_utc = Time.get_date_string_from_system(true)

# ==============================================================================
# 6. User Settings Bucket
# ==============================================================================
class SettingsData extends BaseModel:
	var music_enabled: bool = true
	var sfx_enabled: bool = true
	var haptics_enabled: bool = true
	var music_volume: float = 1.0
	var sfx_volume: float = 1.0
	var locale: String = "en"

	func _init() -> void:
		schema_version = 1
		var sys_locale = TranslationServer.get_locale()
		if not sys_locale.is_empty():
			locale = sys_locale
		else:
			var lang = OS.get_locale_language()
			if not lang.is_empty():
				locale = lang

# ==============================================================================
# 7. Level & XP Progression Bucket
# ==============================================================================
class ProgressionData extends BaseModel:
	var current_level: int = 1
	var unlocked_levels: int = 1
	var level_stars: Dictionary = {} # level_id -> int
	var xp: int = 0
	var areas: Dictionary = {} # area_id -> AreaProgress
	var achievements_unlocked: Array = []

	func _init() -> void:
		schema_version = 1

# ==============================================================================
# 8. Currencies & Economy Bucket
# ==============================================================================
class EconomyData extends BaseModel:
	var currencies: Dictionary = {
		"coins": 0,
		"lives": 3
	}

	func _init() -> void:
		schema_version = 1

# ==============================================================================
# 9. Owned & Equipped Items Bucket
# ==============================================================================
class InventoryData extends BaseModel:
	var equipped: Dictionary = {} # slot_type -> item_id
	var owned: Dictionary = {} # category -> array<item_id>
	var boosters: Dictionary = {} # booster_id -> count

	func _init() -> void:
		schema_version = 1

# ==============================================================================
# 10. Live Events & Daily Rewards Bucket
# ==============================================================================
class LiveOpsData extends BaseModel:
	var daily_reward: Dictionary = {
		"current_day": 1,
		"last_claimed_date": "",
		"streak": 0
	}
	var chests: Dictionary = {} # chestId -> { claimed: bool, claimedAt: int }

	func _init() -> void:
		schema_version = 1

# ==============================================================================
# 11. Gameplay Statistics & Telemetry Bucket
# ==============================================================================
class StatsData extends BaseModel:
	var matches_played: int = 0
	var matches_won: int = 0
	var matches_lost: int = 0
	var win_streak: int = 0
	var custom: Dictionary = {} # Genre-specific counters (level_attempts, accuracy, etc.)

	func _init() -> void:
		schema_version = 1

# ==============================================================================
# 12. Tutorial State Bucket
# ==============================================================================
class TutorialsData extends BaseModel:
	var seen: Dictionary = {} # tutorialId -> bool
	var ftue_completed: bool = false
	var terms_accepted: bool = false

	func _init() -> void:
		schema_version = 1

# ==============================================================================
# 13. Monetization & Purchases Bucket
# ==============================================================================
class MonetizationData extends BaseModel:
	var ad_watch_counts: Dictionary = {} # adType -> number
	var remove_ads_purchased: bool = false
	var purchase_history: Array = [] # array<{ productId: string, timestamp: number }>
	var entitlements: Dictionary = {} # map<string, any>

	func _init() -> void:
		schema_version = 1

# ==============================================================================
# 14. Dedicated Developer Sandbox Bucket
# ==============================================================================
class CustomData extends BaseModel:
	var data: Dictionary = {}

	func _init() -> void:
		schema_version = 1

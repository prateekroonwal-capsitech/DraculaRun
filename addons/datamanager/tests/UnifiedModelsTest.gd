# class_name UnifiedModelsTest
# Comprehensive validation test suite for all 12 Unified Game Data Model models and repositories.
extends MainLoop

const _DataResult = preload("res://addons/datamanager/utils/Result.gd")
const _BaseModel = preload("res://addons/datamanager/models/BaseModel.gd")
const _BaseRepository = preload("res://addons/datamanager/repositories/BaseRepository.gd")
const _MemoryCache = preload("res://addons/datamanager/storage/MemoryCache.gd")

const _GameModels = preload("res://addons/datamanager/models/GameModels.gd")

const _IdentityData = _GameModels.IdentityData
const _ProfileData = _GameModels.ProfileData
const _DeviceData = _GameModels.DeviceData
const _MetadataData = _GameModels.MetadataData
const _SessionData = _GameModels.SessionData
const _SettingsData = _GameModels.SettingsData
const _ProgressionData = _GameModels.ProgressionData
const _EconomyData = _GameModels.EconomyData
const _InventoryData = _GameModels.InventoryData
const _LiveOpsData = _GameModels.LiveOpsData
const _StatsData = _GameModels.StatsData
const _TutorialsData = _GameModels.TutorialsData
const _MonetizationData = _GameModels.MonetizationData
const _CustomData = _GameModels.CustomData

var passed: int = 0
var failed: int = 0

var log_lines: Array[String] = []

func _initialize() -> void:
	log_lines.append("=== Running Unified Game Data Model Test Suite ===")
	run_all_tests()
	log_lines.append("=== Tests Complete: %d Passed, %d Failed ===" % [passed, failed])
	if failed > 0:
		log_lines.append("Unified Model tests had failures.")
	else:
		log_lines.append("✓ All Unified Game Data Model tests passed successfully!")
		
	var file = FileAccess.open("user://test_results.txt", FileAccess.WRITE)
	if file:
		file.store_string("\n".join(log_lines))
		file.close()

func _process(_delta: float) -> bool:
	return true # Exit loop immediately after test execution

func _assert(condition: bool, test_name: String) -> void:
	if condition:
		passed += 1
		log_lines.append("  [PASS] %s" % test_name)
		print("  [PASS] %s" % test_name)
	else:
		failed += 1
		log_lines.append("  [FAIL] %s" % test_name)
		printerr("  [FAIL] %s" % test_name)

func run_all_tests() -> void:
	test_deterministic_field_defaults()
	test_identity_model()
	test_profile_model()
	test_device_model()
	test_metadata_model()
	test_session_model()
	test_settings_model()
	test_progression_model()
	test_economy_model()
	test_inventory_model()
	test_liveops_model()
	test_stats_model()
	test_tutorials_model()
	test_monetization_model()
	test_custom_model()
	test_repository_dirty_tracking()
	test_merge_logic()
	test_deeply_nested_structures()

func test_identity_model() -> void:
	var id = _IdentityData.new()
	id.user_id = "test_user_42"
	id.auth_provider = "google"
	id.signed_in = true
	id.email = "player@example.com"
	id.fcm_token = "token_abc123"
	
	var serialized = id.serialize()
	_assert(serialized["user_id"] == "test_user_42", "IdentityData serialize user_id")
	_assert(serialized["auth_provider"] == "google", "IdentityData serialize auth_provider")
	_assert(serialized["signed_in"] == true, "IdentityData serialize signed_in")
	_assert(serialized["email"] == "player@example.com", "IdentityData serialize email")
	
	var clone = id.clone()
	_assert(id.equals(clone), "IdentityData clone equals original")
	
	var restored = _IdentityData.new()
	restored.deserialize(serialized)
	_assert(id.equals(restored), "IdentityData deserialize fidelity")

func test_profile_model() -> void:
	var prof = _ProfileData.new()
	prof.display_name = "SpeedRunner"
	prof.is_custom_name = true
	prof.avatar_id = "penguin_gold"
	prof.frame_id = "frame_diamond"
	prof.country_code = "US"
	
	var serialized = prof.serialize()
	_assert(serialized["display_name"] == "SpeedRunner", "ProfileData serialize display_name")
	_assert(serialized["is_custom_name"] == true, "ProfileData serialize is_custom_name")
	
	var restored = _ProfileData.new()
	restored.deserialize(serialized)
	_assert(prof.equals(restored), "ProfileData deserialize fidelity")

func test_device_model() -> void:
	var dev = _DeviceData.new()
	dev.app_version = "1.0.3"
	var serialized = dev.serialize()
	_assert(serialized["app_version"] == "1.0.3", "DeviceData serialize app_version")
	
	var restored = _DeviceData.new()
	restored.deserialize(serialized)
	_assert(dev.equals(restored), "DeviceData deserialize fidelity")

func test_metadata_model() -> void:
	var meta = _MetadataData.new()
	meta.revision = 3
	meta.dirty_buckets["economy"] = true
	meta.values["test_key"] = "test_val"
	var serialized = meta.serialize()
	_assert(serialized["revision"] == 3, "MetadataData serialize revision")
	_assert(serialized["dirty_buckets"]["economy"] == true, "MetadataData serialize dirty_buckets")
	
	var restored = _MetadataData.new()
	restored.deserialize(serialized)
	_assert(meta.equals(restored), "MetadataData deserialize fidelity")

func test_session_model() -> void:
	var sess = _SessionData.new()
	sess.session_count = 5
	sess.screen_time_seconds = 1200.5
	sess.last_session_date_utc = "2026-08-26T12:00:00Z"
	
	var serialized = sess.serialize()
	_assert(serialized["session_count"] == 5, "SessionData serialize session_count")
	
	var restored = _SessionData.new()
	restored.deserialize(serialized)
	_assert(sess.equals(restored), "SessionData deserialize fidelity")

func test_settings_model() -> void:
	var set = _SettingsData.new()
	set.music_enabled = false
	set.sfx_enabled = true
	set.haptics_enabled = false
	set.music_volume = 0.5
	set.sfx_volume = 0.8
	set.locale = "pt-BR"
	
	var serialized = set.serialize()
	_assert(serialized["music_enabled"] == false, "SettingsData serialize music_enabled")
	_assert(serialized["locale"] == "pt-BR", "SettingsData serialize locale")
	
	var restored = _SettingsData.new()
	restored.deserialize(serialized)
	_assert(set.equals(restored), "SettingsData deserialize fidelity")

func test_progression_model() -> void:
	var prog = _ProgressionData.new()
	prog.current_level = 15
	prog.unlocked_levels = 16
	prog.level_stars["level_1"] = 3
	prog.xp = 450
	prog.achievements_unlocked.append("first_win")
	
	var serialized = prog.serialize()
	_assert(serialized["current_level"] == 15, "ProgressionData serialize current_level")
	_assert(serialized["level_stars"]["level_1"] == 3, "ProgressionData serialize level_stars")
	
	var restored = _ProgressionData.new()
	restored.deserialize(serialized)
	_assert(prog.equals(restored), "ProgressionData deserialize fidelity")
	_assert(typeof(restored.level_stars["level_1"]) == TYPE_INT, "ProgressionData level_stars int type preservation")

func test_economy_model() -> void:
	var eco = _EconomyData.new()
	eco.currencies["coins"] = 500
	eco.currencies["lives"] = 3
	
	_assert(eco.currencies["coins"] == 500, "EconomyData currencies dictionary")
	
	var serialized = eco.serialize()
	_assert(serialized["currencies"]["coins"] == 500, "EconomyData serialize currencies")
	
	var restored = _EconomyData.new()
	restored.deserialize(serialized)
	_assert(eco.equals(restored), "EconomyData deserialize fidelity")

func test_inventory_model() -> void:
	var inv = _InventoryData.new()
	inv.equipped["trail"] = "trail_fire"
	inv.owned["trails"] = ["trail_fire", "trail_ice"]
	inv.boosters["hammer"] = 3
	
	var serialized = inv.serialize()
	_assert(serialized["equipped"]["trail"] == "trail_fire", "InventoryData serialize equipped")
	_assert(serialized["boosters"]["hammer"] == 3, "InventoryData serialize boosters")
	
	var restored = _InventoryData.new()
	restored.deserialize(serialized)
	_assert(inv.equals(restored), "InventoryData deserialize fidelity")

func test_liveops_model() -> void:
	var live = _LiveOpsData.new()
	live.daily_reward["streak"] = 5
	live.chests["chest_wood"] = { "claimed": true, "claimed_at": 1700000000 }
	
	var serialized = live.serialize()
	_assert(serialized["daily_reward"]["streak"] == 5, "LiveOpsData serialize daily_reward")
	
	var restored = _LiveOpsData.new()
	restored.deserialize(serialized)
	_assert(live.equals(restored), "LiveOpsData deserialize fidelity")

func test_stats_model() -> void:
	var stats = _StatsData.new()
	stats.matches_played = 20
	stats.matches_won = 15
	stats.win_streak = 4
	stats.custom["level_attempts_by_level"] = { "1": 3, "2": 5 }
	
	var serialized = stats.serialize()
	_assert(serialized["matches_played"] == 20, "StatsData serialize matches_played")
	_assert(serialized["custom"]["level_attempts_by_level"]["1"] == 3, "StatsData serialize custom map")
	
	var restored = _StatsData.new()
	restored.deserialize(serialized)
	_assert(stats.equals(restored), "StatsData deserialize fidelity")

func test_tutorials_model() -> void:
	var tut = _TutorialsData.new()
	tut.seen["drag_aim"] = true
	tut.ftue_completed = true
	tut.terms_accepted = true
	
	_assert(tut.seen["drag_aim"] == true, "TutorialsData seen map")
	_assert(tut.seen.get("unknown", false) == false, "TutorialsData unseen tutorial")
	
	var serialized = tut.serialize()
	_assert(serialized["seen"]["drag_aim"] == true, "TutorialsData serialize seen")
	_assert(serialized["ftue_completed"] == true, "TutorialsData serialize ftue_completed")
	
	var restored = _TutorialsData.new()
	restored.deserialize(serialized)
	_assert(tut.equals(restored), "TutorialsData deserialize fidelity")

func test_monetization_model() -> void:
	var mon = _MonetizationData.new()
	mon.ad_watch_counts["rewarded"] = 10
	mon.remove_ads_purchased = true
	mon.purchase_history.append({ "product_id": "no_ads_pack", "timestamp": 123456789 })
	mon.entitlements["vip"] = true
	
	var serialized = mon.serialize()
	_assert(serialized["remove_ads_purchased"] == true, "MonetizationData serialize remove_ads_purchased")
	
	var restored = _MonetizationData.new()
	restored.deserialize(serialized)
	_assert(mon.equals(restored), "MonetizationData deserialize fidelity")

func test_repository_dirty_tracking() -> void:
	var cache = _MemoryCache.new()
	var repo = _BaseRepository.new("economy", _EconomyData, cache)
	
	_assert(!repo.is_dirty(), "Repo starts clean")
	var data = repo.data as _EconomyData
	data.currencies["coins"] = 100
	repo.mark_dirty()
	_assert(repo.is_dirty(), "Repo marks dirty upon mutation")
	_assert((repo.data as _EconomyData).currencies.get("coins", 0) == 100, "Repo data property returns accurate balance")
	_assert((repo.get_data() as _EconomyData).currencies.get("coins", 0) == 100, "Repo get_data() returns accurate balance")
	
	# Test mutate helper
	repo.mutate(func(d: _EconomyData):
		d.currencies["coins"] = 60
	)
	_assert((repo.data as _EconomyData).currencies.get("coins", 0) == 60, "Repo mutate helper updates balance")
	
	repo.clear_dirty()
	_assert(!repo.is_dirty(), "Repo clears dirty state and updates baseline")

func test_merge_logic() -> void:
	var local_prog = _ProgressionData.new()
	var remote_prog = _ProgressionData.new()
	var merged_prog = local_prog.merge(remote_prog)
	_assert(merged_prog == null, "BaseModel merge() returns null by default, letting SyncManager handle conflict resolution")

func test_deeply_nested_structures() -> void:
	# 1. Deeply nested dictionaries and arrays (5 levels deep)
	var stats = _StatsData.new()
	stats.custom = {
		"level_stats": {
			"world_1": {
				"zone_a": {
					"attempts": 42,
					"checkpoints": [10.5, 20.5, 35.2],
					"flags": {"boss_beaten": true, "no_damage": false}
				}
			}
		},
		"player_tags": ["beta_tester", "vip_founder", "speedrunner"]
	}
	
	var serialized = stats.serialize()
	_assert(serialized["custom"]["level_stats"]["world_1"]["zone_a"]["attempts"] == 42, "Deep nested dictionary serialization (level 5)")
	_assert(serialized["custom"]["level_stats"]["world_1"]["zone_a"]["checkpoints"][1] == 20.5, "Deep nested array inside dictionary serialization")
	_assert(serialized["custom"]["level_stats"]["world_1"]["zone_a"]["flags"]["boss_beaten"] == true, "Deep nested boolean serialization")
	
	# 2. Deserialization fidelity of deeply nested structures
	var restored = _StatsData.new()
	restored.deserialize(serialized)
	_assert(stats.equals(restored), "Deeply nested data equals restored instance")
	_assert(restored.custom["level_stats"]["world_1"]["zone_a"]["attempts"] == 42, "Deeply nested value correctly deserialized")
	
	# 3. Clone independence (mutating the clone must NOT mutate the original)
	var cloned = stats.clone() as _StatsData
	_assert(cloned != null and cloned != stats, "Cloned instance is a distinct object")
	cloned.custom["level_stats"]["world_1"]["zone_a"]["attempts"] = 999
	_assert(stats.custom["level_stats"]["world_1"]["zone_a"]["attempts"] == 42, "Deep clone maintains reference isolation")
	_assert(!stats.equals(cloned), "Deeply modified clone correctly detects inequality (dirty)")

	# 4. Nested sub-model instances
	var outer = _StatsData.new()
	var inner_profile = _ProfileData.new()
	inner_profile.display_name = "EmbeddedHero"
	outer.custom["embedded_profile"] = inner_profile
	
	var outer_ser = outer.serialize()
	_assert(outer_ser["custom"]["embedded_profile"] is Dictionary, "Embedded sub-model serialized to Dictionary")
	_assert(outer_ser["custom"]["embedded_profile"]["display_name"] == "EmbeddedHero", "Embedded sub-model property serialized")
	
	var outer_restored = _StatsData.new()
	outer_restored.custom["embedded_profile"] = _ProfileData.new()
	outer_restored.deserialize(outer_ser)
	_assert(outer_restored.custom["embedded_profile"] is _ProfileData, "Embedded sub-model restored as model instance")
	_assert((outer_restored.custom["embedded_profile"] as _ProfileData).display_name == "EmbeddedHero", "Embedded sub-model restored property fidelity")

	# 5. Type safety edge cases (JSON floats vs ints, booleans, and negative numbers)
	var type_test_model = _StatsData.new()
	var mock_json_data = {
		"custom": {
			"whole_float": 50.0,
			"decimal_float": 3.14159,
			"negative_int": -42.0,
			"bool_flag": true,
			"nested_list": [1.0, 2.5, 3.0, false]
		}
	}
	type_test_model.deserialize(mock_json_data)
	_assert(typeof(type_test_model.custom["whole_float"]) == TYPE_INT and type_test_model.custom["whole_float"] == 50, "JSON 50.0 coerced to int 50")
	_assert(typeof(type_test_model.custom["decimal_float"]) == TYPE_FLOAT and is_equal_approx(type_test_model.custom["decimal_float"], 3.14159), "JSON 3.14159 preserved as float")
	_assert(typeof(type_test_model.custom["negative_int"]) == TYPE_INT and type_test_model.custom["negative_int"] == -42, "Negative float -42.0 coerced to int -42")
	_assert(typeof(type_test_model.custom["bool_flag"]) == TYPE_BOOL and type_test_model.custom["bool_flag"] == true, "Boolean flag preserved as bool")
	_assert(typeof(type_test_model.custom["nested_list"][0]) == TYPE_INT, "Array element 1.0 coerced to int 1")
	_assert(typeof(type_test_model.custom["nested_list"][1]) == TYPE_FLOAT, "Array element 2.5 preserved as float")
	_assert(typeof(type_test_model.custom["nested_list"][3]) == TYPE_BOOL, "Array element boolean preserved")

func test_custom_model() -> void:
	var c = _CustomData.new()
	c.data["custom_flag"] = true
	c.data["hero_power"] = 9001
	c.data["unlocked_items"] = ["hat_pirate", "sword_fire"]

	var serialized = c.serialize()
	_assert(serialized["data"]["custom_flag"] == true, "CustomData serialize custom_flag")
	_assert(serialized["data"]["hero_power"] == 9001, "CustomData serialize hero_power")

	var clone = c.clone()
	_assert(c.equals(clone), "CustomData clone equals original")

	var restored = _CustomData.new()
	restored.deserialize(serialized)
	_assert(c.equals(restored), "CustomData deserialize fidelity")

	# Test arbitrary deep nesting
	c.data["skills"] = {"warrior": {"slash": {"level": 5}}}
	var ser2 = c.serialize()
	var res2 = _CustomData.new()
	res2.deserialize(ser2)
	_assert(res2.data["skills"]["warrior"]["slash"]["level"] == 5, "CustomData arbitrary deep nesting serialization")

func test_deterministic_field_defaults() -> void:
	var dev = _DeviceData.new()
	_assert(!dev.app_version.is_empty(), "DeviceData auto-populates non-empty app_version")

	var id = _IdentityData.new()
	_assert(!id.user_id.is_empty(), "IdentityData auto-populates non-empty user_id")
	_assert(id.auth_provider == "guest", "IdentityData defaults to guest auth_provider")

	var meta = _MetadataData.new()
	_assert(meta.revision == 1, "MetadataData revision starts at 1")
	_assert(meta.created_at > 0.0, "MetadataData created_at populated with unix timestamp")
	_assert(meta.last_login_at > 0.0, "MetadataData last_login_at populated with unix timestamp")

	var sess = _SessionData.new()
	_assert(sess.session_count == 1, "SessionData session_count starts at 1")
	_assert(!sess.last_session_date_utc.is_empty(), "SessionData last_session_date_utc populated with UTC date")
	_assert(sess.screen_time_seconds == 0.0, "SessionData screen_time_seconds starts at 0.0")

	var settings = _SettingsData.new()
	_assert(!settings.locale.is_empty(), "SettingsData auto-populates system locale")

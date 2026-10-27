# class_name DataFrameworkTest
# Self-contained integration test runner verifying the clean-slate dynamic registry.
extends Node

# ==============================================================================
# Nested Test Models & Repositories (demonstrating custom developer extensions)
# ==============================================================================

class TestPlayerData extends BaseModel:
	var coins: int = 0

	func _init() -> void:
		schema_version = 1

	func serialize() -> Dictionary:
		return {
			"schema_version": schema_version,
			"coins": coins,
			"last_saved_timestamp": last_saved_timestamp
		}

	func deserialize(dict: Dictionary) -> void:
		if dict.has("schema_version"):
			schema_version = int(dict["schema_version"])
		if dict.has("coins"):
			coins = int(dict["coins"])
		if dict.has("last_saved_timestamp"):
			last_saved_timestamp = float(dict["last_saved_timestamp"])

	func clone() -> BaseModel:
		var copy = TestPlayerData.new()
		copy.schema_version = schema_version
		copy.coins = coins
		copy.last_saved_timestamp = last_saved_timestamp
		return copy

	func equals(other: BaseModel) -> bool:
		var o = other as TestPlayerData
		if not o:
			return false
		return schema_version == o.schema_version and \
			coins == o.coins and \
			is_equal_approx(last_saved_timestamp, o.last_saved_timestamp)

# Custom test repository managing the TestPlayerData
class TestPlayerRepository extends BaseRepository:
	func _init(p_cache: MemoryCache) -> void:
		super("TestPlayer", TestPlayerData, p_cache)
		
	func add_coins(amount: int) -> void:
		var data = get_data() as TestPlayerData
		data.coins += amount
		mark_dirty()

# ==============================================================================
# Integration Test Execution Flow
# ==============================================================================

var tests_passed: int = 0
var tests_failed: int = 0

func _ready() -> void:
	# Wait a frame to ensure autoloads are registered and ready
	await get_tree().process_frame
	
	DataManagerLogger.info("=======================================", "TEST")
	DataManagerLogger.info("Starting Data Management Framework Tests", "TEST")
	DataManagerLogger.info("=======================================", "TEST")
	
	await run_tests()
	
	DataManagerLogger.info("=======================================", "TEST")
	DataManagerLogger.info("Test Run Completed: %d PASSED, %d FAILED" % [tests_passed, tests_failed], "TEST")
	DataManagerLogger.info("=======================================", "TEST")
	
	if tests_failed > 0:
		push_error("Some integration tests failed!")
		get_tree().quit(1)
	else:
		print("All clean-slate framework tests completed successfully!")
		get_tree().quit(0)

func run_tests() -> void:
	var dm = get_node_or_null("/root/DataManager")
	if not dm:
		_fail("DataManager autoload not found. Cannot run tests.")
		return
		
	# 1. Clear sandbox and inject MockCloudStorage for offline test simulation
	var config = get_node_or_null("/root/DataManagerConfig")
	if config:
		config.cloud_enabled = true
		
	var mock_cloud = MockCloudStorage.new()
	dm.set_cloud_storage(mock_cloud)
	dm.clear_local()
	mock_cloud.set_online_status(false)
	
	# 2. Dynamically register our custom test repository
	var test_repo = TestPlayerRepository.new(dm.memory_cache)
	var reg_res = dm.register_repository(test_repo)
	if not reg_res.success:
		_fail("Dynamic repository registration failed: " + reg_res.error_message)
		return
	
	# 3. Run test cases
	await test_default_values(dm)
	await test_dirty_tracking(dm)
	await test_transactions_commit(dm)
	await test_transactions_rollback(dm)
	await test_conflict_resolution(dm)
	await test_metadata_store(dm)
	await test_firestore_modes(dm)

func test_default_values(dm) -> void:
	DataManagerLogger.info("--- Running: test_default_values ---", "TEST")
	var repo = dm.get_repository("TestPlayer") as TestPlayerRepository
	var data = repo.get_data() as TestPlayerData
	if data.coins == 0:
		_pass("Default player variables correctly initialized dynamically.")
	else:
		_fail("Default values incorrect.")

func test_dirty_tracking(dm) -> void:
	DataManagerLogger.info("--- Running: test_dirty_tracking ---", "TEST")
	var repo = dm.get_repository("TestPlayer") as TestPlayerRepository
	
	# Verify clean state
	if repo.is_dirty():
		_fail("Repository dirty before any edits.")
		return
		
	# Mutate state
	repo.add_coins(100)
	
	# Verify dirty state
	if repo.is_dirty():
		_pass("Repository successfully detected dirty state changes.")
	else:
		_fail("Repository failed to detect dirty changes.")
		
	# Save and verify clean
	dm.save()
	if not repo.is_dirty():
		_pass("Dirty status cleared after save.")
	else:
		_fail("Repository remained dirty after save completed.")

func test_transactions_commit(dm) -> void:
	DataManagerLogger.info("--- Running: test_transactions_commit ---", "TEST")
	var repo = dm.get_repository("TestPlayer") as TestPlayerRepository
	var data = repo.get_data() as TestPlayerData
	var old_coins = data.coins
	
	dm.begin_transaction()
	repo.add_coins(50)
	
	var res = dm.commit_transaction()
	if res.success and data.coins == old_coins + 50:
		_pass("Transaction successfully committed.")
	else:
		_fail("Failed to commit transaction.")

func test_transactions_rollback(dm) -> void:
	DataManagerLogger.info("--- Running: test_transactions_rollback ---", "TEST")
	var repo = dm.get_repository("TestPlayer") as TestPlayerRepository
	var data = repo.get_data() as TestPlayerData
	var old_coins = data.coins
	
	dm.begin_transaction()
	repo.add_coins(1000) # Uncommitted coins
	
	# Verify cache has temporary modifications during transaction
	if data.coins != old_coins + 1000:
		_fail("Changes were not reflected in-cache during transaction.")
		return
		
	dm.rollback_transaction()
	
	# Verify cache reverted to baseline
	data = repo.get_data() as TestPlayerData
	if data.coins == old_coins:
		_pass("Transaction reverted changes successfully.")
	else:
		_fail("Rollback failed to revert cache to snapshots.")

func test_conflict_resolution(dm) -> void:
	DataManagerLogger.info("--- Running: test_conflict_resolution ---", "TEST")
	
	var sync_node = get_node_or_null("/root/SyncManager")
	var signals = get_tree().root.get_node_or_null("DataManagerSignals")
	if sync_node and sync_node._is_syncing and signals:
		await signals.sync_finished
		
	dm.clear_local()
	
	var cloud = dm.cloud_storage as FirestoreStorage
	cloud.set_online_status(false)
	
	var test_repo = TestPlayerRepository.new(dm.memory_cache)
	dm.register_repository(test_repo)
	
	cloud.set_online_status(true)
	await cloud.login_anonymous()
	
	if sync_node and sync_node._is_syncing and signals:
		await signals.sync_finished
	
	# 1. Set baseline data: Local starts with 10 coins, sync to cloud
	var data = test_repo.get_data() as TestPlayerData
	data.coins = 10
	test_repo.mark_dirty()
	dm.save()
	await dm.sync()
	
	# Verify remote cloud save matches baseline
	var cloud_res = await cloud.load_data("TestPlayer")
	if not cloud_res.success or int(cloud_res.data["coins"]) != 10:
		_fail("Cloud save did not receive baseline data.")
		return
		
	# 2. Simulate local change: player gets 50 coins, saves with newer timestamp
	data = test_repo.get_data() as TestPlayerData
	data.coins = 50
	test_repo.mark_dirty()
	dm.save()
	var current_system_time = Time.get_unix_time_from_system()
	
	# 3. Simulate remote cloud change behind our back (e.g. modified on another device)
	# Cloud receives 100 coins with a timestamp older than local
	var hijacked_cloud_data = {
		"schema_version": 1,
		"coins": 100,
		"last_saved_timestamp": current_system_time - 1000.0 # Guaranteed older than local save
	}
	# Directly bypass sync managers to inject server-side changes
	cloud._remote_db[cloud._user_id]["TestPlayer"] = hijacked_cloud_data
	cloud._invalidate_cache()
	
	# 4. Trigger Sync. With LatestTimestamp strategy:
	# Local (50 coins) should win over Remote (100 coins)
	var sync_res = await dm.sync()
	if not sync_res.success:
		_fail("Sync failed during conflict test: %s" % sync_res.error_message)
		return
		
	data = test_repo.get_data() as TestPlayerData
	if data.coins == 50:
		_pass("Timestamp conflict resolution successfully picked Local (newer).")
	else:
		_fail("Incorrect winner picked during conflict resolution. Coins: %d" % data.coins)
		return
		
	# 5. Now update hijacked remote cloud save to have a timestamp in the future (newer than local)
	hijacked_cloud_data["coins"] = 150
	hijacked_cloud_data["last_saved_timestamp"] = Time.get_unix_time_from_system() + 1000.0 # Guaranteed newer than local
	cloud._remote_db[cloud._user_id]["TestPlayer"] = hijacked_cloud_data
	cloud._invalidate_cache()
	
	# 6. Trigger Sync. Remote should now win
	sync_res = await dm.sync()
	if not sync_res.success:
		_fail("Sync failed during remote conflict check.")
		return
		
	data = test_repo.get_data() as TestPlayerData
	if data.coins == 150:
		_pass("Timestamp conflict resolution successfully picked Remote (newer).")
	else:
		_fail("Incorrect winner picked. Expected 150 (Remote), got %d." % data.coins)

func test_metadata_store(dm) -> void:
	DataManagerLogger.info("--- Running: test_metadata_store ---", "TEST")
	dm.clear_local()
	
	dm.metadata_repo.mutate(func(d: GameModels.MetadataData):
		d.values["quest_id"] = "find_shield"
		d.values["is_premium"] = true
	)
	
	var data = dm.metadata_repo.data as GameModels.MetadataData
	if data.values.get("quest_id") == "find_shield" and data.values.get("is_premium") == true:
		_pass("Generic metadata key-value set and retrieve succeeded.")
	else:
		_fail("Metadata retrieved incorrect values.")
		return
		
	dm.metadata_repo.mutate(func(d: GameModels.MetadataData):
		d.values.erase("is_premium")
	)
	if not (dm.metadata_repo.data as GameModels.MetadataData).values.has("is_premium"):
		_pass("Metadata key deletion succeeded.")
	else:
		_fail("Metadata key deletion failed to remove key.")

func test_firestore_modes(dm) -> void:
	DataManagerLogger.info("--- Running: test_firestore_modes ---", "TEST")
	dm.clear_local()
	
	# Fetch Config and Cloud storage references
	var config = get_node_or_null("/root/DataManagerConfig")
	var cloud = dm.cloud_storage as MockCloudStorage
	if not config or not cloud:
		_fail("DataManagerConfig or MockCloudStorage not found.")
		return
		
	# 1. Test SingleDocument Mode (the default)
	config.firestore_sync_mode = "SingleDocument"
	cloud.set_online_status(true)
	await cloud.login_anonymous()
	
	# Prepare some mock data in the database
	var user_id = cloud._user_id
	cloud._remote_db[user_id] = {
		"TestPlayer": {
			"schema_version": 1,
			"coins": 200,
			"last_saved_timestamp": 5000.0
		},
		"Metadata": {
			"schema_version": 1,
			"values": {"test_mode": "SingleDocMode"},
			"last_saved_timestamp": 5000.0
		}
	}
	
	# Reset counters and load/sync
	cloud.reset_simulated_counters()
	var res1 = await cloud.load_data("TestPlayer")
	var res2 = await cloud.load_data("Metadata")
	
	if not res1.success or not res2.success:
		_fail("Failed to load repository data in SingleDocument mode.")
		return
		
	# In SingleDocument mode, the first load_data should fetch the whole user document (1 read).
	# The second load_data should be served from cache (0 reads).
	# So simulated_read_count should be exactly 1.
	if cloud.simulated_read_count == 1:
		_pass("SingleDocument mode optimized cloud reads: exactly 1 database read for multiple repositories.")
	else:
		_fail("SingleDocument mode read count mismatch. Expected 1, got %d." % cloud.simulated_read_count)
		
	# Test SingleDocument save_batch optimization (multiple repositories written in 1 atomic write)
	cloud.reset_simulated_counters()
	var batch_write_res = await cloud.save_batch({
		"TestPlayer": {"schema_version": 1, "coins": 300},
		"Metadata": {"schema_version": 1, "values": {"status": "saved"}}
	})
	if batch_write_res.success and cloud.simulated_write_count == 1:
		_pass("SingleDocument mode optimized cloud writes: exactly 1 database write for batch save.")
	else:
		_fail("SingleDocument mode batch write failed or count mismatch. Expected 1, got %d." % cloud.simulated_write_count)
		
	# 2. Test MultiCollection Mode
	config.firestore_sync_mode = "MultiCollection"
	
	# Reset counters, invalidate cache, and read again
	cloud._invalidate_cache()
	cloud.reset_simulated_counters()
	
	var res3 = await cloud.load_data("TestPlayer")
	var res4 = await cloud.load_data("Metadata")
	
	if not res3.success or not res4.success:
		_fail("Failed to load repository data in MultiCollection mode.")
		return
		
	# In MultiCollection mode, caching is bypassed.
	# Each load_data call makes a network call (1 read per repository).
	# So simulated_read_count should be exactly 2.
	if cloud.simulated_read_count == 2:
		_pass("MultiCollection mode performed independent collection queries: exactly 2 database reads.")
	else:
		_fail("MultiCollection mode read count mismatch. Expected 2, got %d." % cloud.simulated_read_count)

	# Restore default configuration
	config.firestore_sync_mode = "SingleDocument"

func _pass(message: String) -> void:
	tests_passed += 1
	DataManagerLogger.info("[PASS] %s" % message, "TEST")

func _fail(message: String) -> void:
	tests_failed += 1
	DataManagerLogger.error("[FAIL] %s" % message, "TEST")

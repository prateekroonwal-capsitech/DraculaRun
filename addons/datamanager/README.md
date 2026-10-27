# Unified Game Data Persistence & Cloud Synchronization Framework (Godot 4.x)

A production-grade, offline-first data persistence and cloud synchronization framework for Godot 4.x, implementing the studio's **Unified Game Data Model** specification (`android_users/{uid}` and `ios_users/{uid}`).

---

## 🚀 Quick Setup: Dropping into Any New Game

Follow these 6 steps to integrate this framework into any new Godot 4.x project:

### Step 1: Copy the Addon Folder
Copy the entire `addons/datamanager/` folder into your new Godot project's root:
```
res://addons/datamanager/
```

---

### Step 2: Enable the Plugin & Autoloads
In the Godot Editor, go to **Project -> Project Settings -> Plugins** and enable **DataManager**.

*Or alternatively, add this to your new project's `project.godot` file:*
```ini
[autoload]
DataManagerConfig="*res://addons/datamanager/autoload/Config.gd"
DataManagerSignals="*res://addons/datamanager/autoload/Signals.gd"
SyncManager="*res://addons/datamanager/autoload/SyncManager.gd"
DataManager="*res://addons/datamanager/autoload/DataManager.gd"

[editor_plugins]
enabled=["res://addons/datamanager/plugin.cfg"]
```

---

### Step 3: Autoload Initialization
DataManager auto-boots automatically as an Autoload Singleton (`res://addons/datamanager/autoload/DataManager.gd`).

> **What this does automatically:**
> - Registers all 13 unified data buckets into memory (`identity`, `profile`, `device`, `metadata`, `session`, `settings`, `progression`, `economy`, `inventory`, `liveOps`, `stats`, `tutorials`, `monetization`).
> - Loads existing local disk saves into cache (or creates fresh defaults).
> - Wires up auto-save on app pause/focus loss and quit.
> - Increments session counts and tracks player screen time.

---

### Step 4: Wire Auth Lifecycle (Login / Logout)
Whenever your game's authentication system (Firebase, Guest, Google Play Games, Apple Game Center) completes login or logout:

```gdscript
# When player logs in:
DataManagerSignals.login_changed.emit(player_uid, true)

# When player logs out / session ends:
DataManagerSignals.login_changed.emit("", false)
```

> **What this does automatically:**
> - Sets the user ID and credentials in the `identity` repository.
> - Automatically triggers cloud synchronization (downloading cloud backup and performing conflict resolution).

---

### Step 5: (Optional) Plug in a Custom Backend
If your game uses a custom backend (REST API, Supabase, Nakama, Custom WebSocket), inject your adapter:

```gdscript
# If you implemented a custom adapter extending ICloudStorage:
DataManager.set_cloud_storage(MyCustomBackendAdapter.new())
```
*(If omitted, it uses the built-in `FirestoreStorage` engine which works seamlessly offline and with standard Firestore).*

---

### Step 6: Use Player Data Anywhere in Your Game

You can use the high-level `SaveManager` facade or access `DataManager` directly:

```gdscript
# --- 1. Typed Facade Access (via SaveManager) ---
SaveManager.progression_data.current_level = 5
SaveManager.progression.mark_dirty()

SaveManager.economy_data.currencies["coins"] = 1500
SaveManager.economy.mark_dirty()

# --- 2. Dynamic Key-Value Sandbox (Eliminates PlayerPrefs) ---
SaveManager.set_custom("favorite_mode", "endless")
var mode = SaveManager.get_custom("favorite_mode", "classic")

# --- 3. Save & Sync ---
SaveManager.save_game()   # Saves all dirty repositories to local disk
SaveManager.sync_cloud()  # Asynchronously synchronizes with cloud backend
```

Or via direct repository access on `DataManager`:
```gdscript
DataManager.profile_repo.mutate(func(prof: GameModels.ProfileData):
    prof.display_name = "ShadowNinja"
)
DataManager.save()
```

---

## 📦 The Unified Data Buckets

| # | Bucket Name | Model Class | SaveManager Accessor | Description |
|---|---|---|---|---|
| 1 | `identity` | `IdentityData` | `SaveManager.identity_data` | User UID, Auth Provider, Sign-in state, Email, FCM token |
| 2 | `profile` | `ProfileData` | `SaveManager.profile_data` | Display name, custom name flag, avatar ID, frame ID, badge ID, country code |
| 3 | `device` | `DeviceData` | `SaveManager.device_data` | Installed app version & device info |
| 4 | `metadata` | `MetadataData` | `SaveManager.metadata_data` | Schema version, revision counter, created/login/saved timestamps, dirty map |
| 5 | `session` | `SessionData` | `SaveManager.session_data` | Total screen time, session count, first/last session UTC dates |
| 6 | `settings` | `SettingsData` | `SaveManager.settings_data` | Music, SFX, Haptics, Volume levels, Notifications, Locale |
| 7 | `progression` | `ProgressionData` | `SaveManager.progression_data` | Current level, highest unlocked level, level stars map, XP, achievements |
| 8 | `economy` | `EconomyData` | `SaveManager.economy_data` | Multi-currency (Coins, Gems, Energy, Custom), refill timers, overdraft guards |
| 9 | `inventory` | `InventoryData` | `SaveManager.inventory_data` | Equipped cosmetics, consumables, items map, booster counts |
| 10 | `liveOps` | `LiveOpsData` | `SaveManager.live_ops_data` | Daily reward streak/claim timestamps, active events, battle pass tier |
| 11 | `stats` | `StatsData` | `SaveManager.stats_data` | Matches played, matches won, win streaks, custom game statistics |
| 12 | `tutorials` | `TutorialsData` | `SaveManager.tutorials_data` | Map of seen tutorials, complete tutorial flags |
| 13 | `monetization` | `MonetizationData` | `SaveManager.monetization_data` | Payer flag, total spend USD, purchase history ledger, Remove Ads status |
| 14 | `custom` | `CustomData` | `SaveManager.custom_data` | Arbitrary key-value sandbox store for dynamic gameplay variables |

---

## 🧪 Running Automated Unit Tests

This addon includes a complete standalone test suite (86 passing test cases):

```powershell
# 1. Run Unified Models & Repositories Test Suite (72 Tests)
godot --headless --path . -s addons/datamanager/tests/UnifiedModelsTest.gd

# 2. Run Core Framework Integration Test Suite (14 Tests)
godot --headless --path . addons/datamanager/tests/DataFrameworkTest.tscn
```

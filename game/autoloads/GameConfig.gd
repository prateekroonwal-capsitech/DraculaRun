class_name GameConfig
extends Node

# GameConfig — build stage, backend URLs, feature flags
# Change BUILD_STAGE before exporting for each environment

enum Stage { PROTOTYPE, STAGING, PRODUCTION }

## Change this before exporting
const BUILD_STAGE: Stage = Stage.PROTOTYPE

const UI_PANELS = {
					}

#How to use
#var scene: PackedScene = load(GameConfig.UI_PANELS["shop"])
#_ui_manager.push_packed(scene)


# ── Backend URLs ──────────────────────────────────────────────────────────
const _FUNCTIONS_URL: Dictionary = {
	Stage.PROTOTYPE:  "http://127.0.0.1:5001/your-project-id/us-central1",
	Stage.STAGING:    "https://us-central1-your-game-staging.cloudfunctions.net",
	Stage.PRODUCTION: "https://us-central1-your-game-prod.cloudfunctions.net",
}

# ── Game Identity ─────────────────────────────────────────────────────────
const GAME_ID:    String = "game-template"   # must match backend GameConfig
const APP_VERSION: String = "1.0.0"

# ── Feature Flags ─────────────────────────────────────────────────────────
const USE_EMULATOR:          bool = BUILD_STAGE == Stage.PROTOTYPE
const VERSION_CHECK_ENABLED: bool = BUILD_STAGE != Stage.PROTOTYPE
const CLOUD_SAVE_ENABLED:    bool = BUILD_STAGE != Stage.PROTOTYPE
const ANALYTICS_ENABLED:     bool = BUILD_STAGE == Stage.PRODUCTION

# ── Helpers ───────────────────────────────────────────────────────────────
func get_functions_url() -> String:
	return _FUNCTIONS_URL[BUILD_STAGE]

func is_prototype() -> bool:
	return BUILD_STAGE == Stage.PROTOTYPE

func is_production() -> bool:
	return BUILD_STAGE == Stage.PRODUCTION

class_name GameFlowFeature
extends GameFeature

## Reusable game-flow feature. Dependencies are supplied by the composition root.

var _game: GameManager

func initialize(dependencies: Dictionary) -> void:
	super.initialize(dependencies)
	_game = dependencies.get("game") as GameManager
	if _game == null:
		push_error("GameFlowFeature: missing 'game' dependency")

func start_game() -> void:
	if _game:
		_game.start()

func pause_game() -> void:
	if _game:
		_game.pause()

func resume_game() -> void:
	if _game:
		_game.resume()

func finish_game(reason: String = "") -> void:
	if _game:
		_game.game_over(reason)

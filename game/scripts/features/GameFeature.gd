class_name GameFeature
extends Node

## Base lifecycle for reusable gameplay features.
## Features receive dependencies from their composition root before entering the tree.

var _initialized: bool = false
var _started: bool = false

func initialize(_dependencies: Dictionary) -> void:
	if _initialized:
		return
	_initialized = true

func start() -> void:
	if not _initialized or _started:
		return
	_started = true

func pause() -> void:
	pass

func resume() -> void:
	pass

func dispose() -> void:
	_started = false
	_initialized = false

class_name FeatureFactory
extends RefCounted

## Creates configured features before they enter the scene tree.
## This keeps dependency wiring in the composition root instead of feature code.

static func create_feature(feature_script: Script, parent: Node, dependencies: Dictionary) -> GameFeature:
	var feature := feature_script.new() as GameFeature
	if feature == null:
		push_error("FeatureFactory: script must extend GameFeature")
		return null
	feature.initialize(dependencies)
	parent.add_child(feature)
	return feature

static func create_node(node_script: Script, parent: Node, configure: Callable = Callable()) -> Node:
	var instance := node_script.new() as Node
	if instance == null:
		push_error("FeatureFactory: script must extend Node")
		return null
	if configure.is_valid():
		configure.call(instance)
	parent.add_child(instance)
	return instance

# class_name DataMergePolicy
# Defines the enum strategies used to resolve conflicts between local and remote save data.
class_name DataMergePolicy

enum Strategy {
	PREFER_CLOUD = 0,
	PREFER_LOCAL = 1,
	LATEST_TIMESTAMP = 2,
	MANUAL = 3
}

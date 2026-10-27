# class_name ConflictResolver
# Handles conflict resolution logic between local and remote save data files.
class_name ConflictResolver

## Resolves conflict between local and remote data structures based on the selected strategy.
## Returns a DataResult containing the resolved Dictionary.
static func resolve(local_data: Dictionary, remote_data: Dictionary, strategy: DataMergePolicy.Strategy, custom_resolver: Callable = Callable()) -> DataResult:
	DataManagerLogger.info("Resolving merge conflict. Strategy: %d" % strategy, "CONFLICT_RESOLVER")
	
	match strategy:
		DataMergePolicy.Strategy.PREFER_CLOUD:
			DataManagerLogger.info("Resolved conflict: Preferring Cloud.", "CONFLICT_RESOLVER")
			return DataResult.ok(remote_data.duplicate(true))
			
		DataMergePolicy.Strategy.PREFER_LOCAL:
			DataManagerLogger.info("Resolved conflict: Preferring Local.", "CONFLICT_RESOLVER")
			return DataResult.ok(local_data.duplicate(true))
			
		DataMergePolicy.Strategy.LATEST_TIMESTAMP:
			var local_time: float = 0.0
			var remote_time: float = 0.0
			
			if local_data.has("last_saved_timestamp"):
				local_time = float(local_data["last_saved_timestamp"])
			if remote_data.has("last_saved_timestamp"):
				remote_time = float(remote_data["last_saved_timestamp"])
				
			DataManagerLogger.debug("Timestamp comparison: Local=%f, Remote=%f" % [local_time, remote_time], "CONFLICT_RESOLVER")
			
			if remote_time > local_time:
				DataManagerLogger.info("Resolved conflict: Cloud is newer.", "CONFLICT_RESOLVER")
				return DataResult.ok(remote_data.duplicate(true))
			else:
				DataManagerLogger.info("Resolved conflict: Local is newer or equal.", "CONFLICT_RESOLVER")
				return DataResult.ok(local_data.duplicate(true))
				
		DataMergePolicy.Strategy.MANUAL:
			if custom_resolver.is_valid():
				var resolved = await custom_resolver.call(local_data, remote_data)
				if resolved is Dictionary:
					DataManagerLogger.info("Resolved conflict: Custom manual callable resolved successfully.", "CONFLICT_RESOLVER")
					return DataResult.ok(resolved)
				else:
					return DataResult.fail(DataErrors.Code.MERGE_CONFLICT, "Custom manual resolver returned invalid data type.")
			else:
				DataManagerLogger.warning("Manual merge selected but no valid custom resolver was provided. Falling back to Local.", "CONFLICT_RESOLVER")
				return DataResult.ok(local_data.duplicate(true))
				
		_:
			return DataResult.fail(DataErrors.Code.MERGE_CONFLICT, "Unsupported conflict merge strategy.")

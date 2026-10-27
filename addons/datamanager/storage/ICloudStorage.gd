class_name ICloudStorage
extends RefCounted

## ICloudStorage
## Abstract contract for all Cloud Storage adapters in the Data Persistence Framework.
## Implement this class to connect DataManager to ANY backend (Firebase, REST API, Nakama, Supabase, PlayFab, etc.)

## Saves data for a repository/bucket key to the cloud backend.
func save_data(_key: String, _data: Dictionary) -> DataResult:
	return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "save_data() not implemented in cloud adapter.")

## Saves multiple repository entries to the cloud backend in a single logical operation.
## Adapters can override this for atomic or batched network operations.
func save_batch(batch_data: Dictionary) -> DataResult:
	for key in batch_data:
		var res = await save_data(key, batch_data[key])
		if not res.success:
			return res
	return DataResult.ok()

## Loads data for a repository/bucket key from the cloud backend.
func load_data(_key: String) -> DataResult:
	return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "load_data() not implemented in cloud adapter.")

## Deletes data for a repository/bucket key from the cloud backend.
func delete_data(_key: String) -> DataResult:
	return DataResult.fail(DataErrors.Code.CLOUD_ERROR, "delete_data() not implemented in cloud adapter.")

## Returns true if the cloud backend is reachable and authenticated.
func is_connected_to_backend() -> bool:
	return false

## Updates the network connectivity state.
func set_online_status(_is_online: bool) -> void:
	pass

## Authenticates anonymously (useful for guest accounts and testing).
func login_anonymous() -> DataResult:
	return DataResult.ok()

## Logs out the active user.
func logout() -> DataResult:
	return DataResult.ok()

## Permanently deletes the active user's remote account.
func delete_account() -> DataResult:
	return DataResult.ok()

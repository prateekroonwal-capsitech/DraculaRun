# class_name DataErrors
# Contains constants representing all error types in the data management framework.
class_name DataErrors

enum Code {
	NONE = 0,
	DISK_ERROR = 1,
	CLOUD_ERROR = 2,
	SERIALIZATION_ERROR = 3,
	MERGE_CONFLICT = 4,
	AUTH_ERROR = 5,
	TIMEOUT = 6,
	CORRUPTED_SAVE = 7,
	VALIDATION_ERROR = 8,
	NOT_FOUND = 10,
	TRANSACTION_ERROR = 11,
	UNKNOWN_ERROR = 99
}

## Returns a human-readable message for a given error code.
static func get_message(code: Code) -> String:
	match code:
		Code.NONE:
			return "No error."
		Code.DISK_ERROR:
			return "Failed to read or write local storage."
		Code.CLOUD_ERROR:
			return "Remote cloud database operation failed."
		Code.SERIALIZATION_ERROR:
			return "Failed to serialize or deserialize data."
		Code.MERGE_CONFLICT:
			return "A merge conflict occurred between local and cloud data."
		Code.AUTH_ERROR:
			return "Authentication failed or user has logged out."
		Code.TIMEOUT:
			return "The request timed out."
		Code.CORRUPTED_SAVE:
			return "Save data is corrupted or invalid."
		Code.VALIDATION_ERROR:
			return "Data failed schema validation rules."
		Code.NOT_FOUND:
			return "Requested data key or entry was not found."
		Code.TRANSACTION_ERROR:
			return "A transactional operation failed or was rolled back."
		_:
			return "An unknown error occurred."

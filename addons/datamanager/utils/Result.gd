# class_name DataResult
# A standard wrapper for operation results containing status, error details, and optional data.
class_name DataResult

var success: bool = false
var error_code: DataErrors.Code = DataErrors.Code.NONE
var error_message: String = ""
var data: Variant = null

## Private constructor. Use static builders DataResult.ok() and DataResult.fail().
func _init(p_success: bool, p_error_code: DataErrors.Code = DataErrors.Code.NONE, p_error_msg: String = "", p_data: Variant = null) -> void:
	self.success = p_success
	self.error_code = p_error_code
	self.error_message = p_error_msg
	if p_error_msg == "" and p_error_code != DataErrors.Code.NONE:
		self.error_message = DataErrors.get_message(p_error_code)
	self.data = p_data

## Creates a successful Result.
static func ok(p_data: Variant = null) -> DataResult:
	return DataResult.new(true, DataErrors.Code.NONE, "", p_data)

## Creates a failed Result.
static func fail(p_error_code: DataErrors.Code, p_error_msg: String = "", p_data: Variant = null) -> DataResult:
	return DataResult.new(false, p_error_code, p_error_msg, p_data)

## Formats the result as a string for debugging.
func to_string() -> String:
	if success:
		return "DataResult(OK, data=%s)" % str(data)
	else:
		return "DataResult(FAIL, code=%d, message='%s', data=%s)" % [error_code, error_message, str(data)]
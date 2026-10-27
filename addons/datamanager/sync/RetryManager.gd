# class_name RetryManager
# Manages retries and exponential backoff timing for transient connection errors.
class_name RetryManager

var max_attempts: int = 5
var initial_delay: float = 1.0
var multiplier: float = 2.0
var max_delay: float = 30.0

func _init(p_max_attempts: int = 5, p_init_delay: float = 1.0, p_mult: float = 2.0, p_max_delay: float = 30.0) -> void:
	self.max_attempts = p_max_attempts
	self.initial_delay = p_init_delay
	self.multiplier = p_mult
	self.max_delay = p_max_delay

## Calculates the backoff sleep delay for a given attempt index (0-indexed).
func get_delay_for_attempt(attempt: int) -> float:
	var delay = initial_delay * pow(multiplier, attempt)
	return min(delay, max_delay)

## Executes an asynchronous cloud operation callable with arguments.
## Automatically retries with exponential backoff if a connection error is encountered.
func execute_with_retry(operation: Callable, args: Array = []) -> DataResult:
	var attempt = 0
	var last_result: DataResult = null
	
	while attempt < max_attempts:
		DataManagerLogger.debug("Executing cloud operation attempt %d/%d" % [attempt + 1, max_attempts], "RETRY_MANAGER")
		
		# Run operation. Since cloud operations are async, we await
		last_result = await operation.callv(args)
			
		if last_result.success:
			return last_result
			
		# Only retry on network timeouts or generic cloud connectivity errors
		var is_transient_error = (
			last_result.error_code == DataErrors.Code.TIMEOUT or \
			last_result.error_code == DataErrors.Code.CLOUD_ERROR
		)
		
		if not is_transient_error:
			# Non-retryable error (e.g. auth error, validation error, not found)
			DataManagerLogger.warning("Cloud operation failed with fatal error code: %d. Aborting retries." % last_result.error_code, "RETRY_MANAGER")
			return last_result
			
		attempt += 1
		if attempt < max_attempts:
			var delay = get_delay_for_attempt(attempt - 1)
			DataManagerLogger.warning("Cloud operation failed (Transient error: %s). Retrying in %f seconds..." % [last_result.error_message, delay], "RETRY_MANAGER")
			
			var tree = Engine.get_main_loop() as SceneTree
			if tree:
				await tree.create_timer(delay).timeout
				
	DataManagerLogger.error("Cloud operation failed permanently after %d attempts." % max_attempts, "RETRY_MANAGER")
	return last_result

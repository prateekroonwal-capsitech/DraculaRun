# class_name DataManagerSignals
# Global signal/event bus for the data management framework.
extends Node

# Saves
signal save_started
signal save_finished(result: DataResult)

# Syncing
signal sync_started
signal sync_finished(result: DataResult)
signal cloud_updated(repository_name: String, updated_data: Dictionary)

# Connection
signal connection_status_changed(is_online: bool)

# Repositories
signal repository_dirty(repository_name: String, is_dirty: bool)

# Authentication
signal login_changed(user_id: String, is_authenticated: bool)
signal logout_completed
signal logout_failed(error_message: String)
signal account_deleted
signal account_delete_failed(error_message: String)

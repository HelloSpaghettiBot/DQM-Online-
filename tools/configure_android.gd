@tool
extends EditorScript
func _run() -> void:
	var settings = get_editor_interface().get_editor_settings()
	settings.set_setting("export/android/java_sdk_path", ProjectSettings.globalize_path("res://../.tools/java/jdk-17.0.21+9"))
	settings.set_setting("export/android/android_sdk_path", ProjectSettings.globalize_path("res://../.tools/android-sdk"))

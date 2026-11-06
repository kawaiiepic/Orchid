/// Formats song durations supplied by catalog or addon metadata.
/// The duration is in seconds; unknown values are intentionally not displayed.
String? trackDurationLabel(int? seconds) {
  if (seconds == null || seconds <= 0) return null;
  final minutes = (seconds ~/ 60).toString();
  final remainder = (seconds % 60).toString().padLeft(2, '0');
  final hours = seconds ~/ 3600;
  if (hours > 0) {
    return '$hours:${((seconds % 3600) ~/ 60).toString().padLeft(2, '0')}:$remainder';
  }
  return '$minutes:$remainder';
}

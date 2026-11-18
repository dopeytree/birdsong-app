// Dates and places in plain words, without a locale package.

const _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String _two(int n) => n.toString().padLeft(2, '0');

String clock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

/// "Wed 18 Nov", with the year when it isn't this one.
String day(DateTime t) {
  final now = DateTime.now();
  final y = t.year == now.year ? '' : ' ${t.year}';
  return '${_days[t.weekday - 1]} ${t.day} ${_months[t.month - 1]}$y';
}

bool sameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;

/// "13m", "1hr32", "2hr"; "under a minute".
String lasting(Duration d) {
  final m = d.inMinutes;
  if (m < 1) return 'under a minute';
  if (m < 60) return '${m}m';
  final r = m % 60;
  return '${m ~/ 60}hr${r == 0 ? '' : _two(r)}';
}

/// "Wed 18 Nov, 22:19 for 13m", or "for 1hr32".
String span(DateTime from, DateTime to) =>
    '${day(from)}, ${clock(from)} for ${lasting(to.difference(from))}';

/// "51.454° N, 2.588° W"
String place(double lat, double lon) =>
    '${lat.abs().toStringAsFixed(3)}° ${lat >= 0 ? 'N' : 'S'}, '
    '${lon.abs().toStringAsFixed(3)}° ${lon >= 0 ? 'E' : 'W'}';

String megabytes(int bytes) =>
    bytes <= 0 ? 'size unknown' : '${(bytes / 1048576).toStringAsFixed(0)} MB';

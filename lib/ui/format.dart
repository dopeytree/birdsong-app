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

/// "Wed 18 Nov, 18:20 to 19:05" or across midnight "Wed 18 Nov 23:10 to Thu 19 Nov 01:30".
String span(DateTime from, DateTime to) => sameDay(from, to)
    ? '${day(from)}, ${clock(from)} to ${clock(to)}'
    : '${day(from)} ${clock(from)} to ${day(to)} ${clock(to)}';

/// "51.454° N, 2.588° W"
String place(double lat, double lon) =>
    '${lat.abs().toStringAsFixed(3)}° ${lat >= 0 ? 'N' : 'S'}, '
    '${lon.abs().toStringAsFixed(3)}° ${lon >= 0 ? 'E' : 'W'}';

String megabytes(int bytes) =>
    bytes <= 0 ? 'size unknown' : '${(bytes / 1048576).toStringAsFixed(0)} MB';

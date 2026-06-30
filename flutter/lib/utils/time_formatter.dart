import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import 'package:pax/models/local/activity_model.dart';

String formatTimestampWithIntl(Timestamp? timestamp) {
  if (timestamp == null) return 'N/A';

  final date = timestamp.toDate();

  // Format the date using DateFormat
  final DateFormat monthDayYearFormat = DateFormat('MMM d yyyy');
  final DateFormat timeFormat = DateFormat('h.mm a');

  final String datePart = monthDayYearFormat.format(date);
  final String timePart = timeFormat.format(date);

  return '$datePart | $timePart';
}

extension FormatActivityTimeStamp on Activity {
  String get formattedTimestamp => formatTimestampWithIntl(timestamp);
}

const int minimumTaskParticipantAge = 18;

int calculateAge(DateTime birthDate) {
  final now = DateTime.now();
  int age = now.year - birthDate.year;
  if (now.month < birthDate.month ||
      (now.month == birthDate.month && now.day < birthDate.day)) {
    age--;
  }
  return age;
}

bool isAtLeastMinimumAge(
  DateTime birthDate, {
  int minimumAge = minimumTaskParticipantAge,
}) {
  final today = DateTime.now();
  final cutoff = DateTime(today.year - minimumAge, today.month, today.day);
  return !birthDate.isAfter(cutoff);
}

bool isEligibleForTasks(Timestamp? dateOfBirth) {
  if (dateOfBirth == null) return false;
  return isAtLeastMinimumAge(dateOfBirth.toDate());
}

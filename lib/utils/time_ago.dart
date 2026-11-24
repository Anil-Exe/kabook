String timeAgo(DateTime date) {
  final diff = DateTime.now().difference(date);

  if (diff.inSeconds < 60) {
    return 'şimdi';
  } else if (diff.inMinutes < 60) {
    return '${diff.inMinutes} dk önce';
  } else if (diff.inHours < 24) {
    return '${diff.inHours} saat önce';
  } else if (diff.inDays < 7) {
    return '${diff.inDays} gün önce';
  } else {
    return '${date.day}.${date.month}.${date.year}';
  }
}

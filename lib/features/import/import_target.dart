import 'loveread_source.dart';

const defaultSite = 'https://loveread.ec';

sealed class ImportTarget {
  const ImportTarget();
}

class LoveReadTarget extends ImportTarget {
  const LoveReadTarget(this.site, this.bookId, this.firstPage);

  final Uri site;
  final int bookId;
  final int firstPage;
}

class WebPageTarget extends ImportTarget {
  const WebPageTarget(this.url);

  final Uri url;
}

/// Interprets what the user typed: a bare book id (resolved against the
/// remembered [site]), a loveread.* URL, or any other http(s) URL.
/// Returns null when the input is not usable.
ImportTarget? parseImportInput(String input, {required Uri site}) {
  final text = input.trim();
  if (text.isEmpty) return null;
  final id = int.tryParse(text);
  if (id != null) return LoveReadTarget(site, id, 1);
  final uri = Uri.tryParse(_withScheme(text, site));
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final bookId = LoveReadSource.bookId(uri);
  if (bookId != null) {
    return LoveReadTarget(
      LoveReadSource.siteOf(uri),
      bookId,
      LoveReadSource.startPage(uri),
    );
  }
  return WebPageTarget(uri);
}

/// Completes what was typed: a missing `https://` is added, and an address
/// that starts at the path (`read_book.php?id=5`) gets the remembered [site].
String _withScheme(String text, Uri site) {
  if (RegExp(r'^[a-z][a-z0-9+.-]*://', caseSensitive: false).hasMatch(text)) {
    return text;
  }
  if (text.startsWith('/')) return '$site$text';
  if (text.startsWith('read_book.php')) return '$site/$text';
  if (text.contains('.') && !text.contains(' ')) return 'https://$text';
  return text;
}

/// What the input field starts with so only the id has to be typed.
String inputPrefix(Uri site) =>
    '$site/read_book.php?id='.replaceFirst('//read', '/read');

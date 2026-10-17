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
  final uri = Uri.tryParse(text);
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
  final bookId = LoveReadSource.bookId(uri);
  if (bookId != null) {
    return LoveReadTarget(
        LoveReadSource.siteOf(uri), bookId, LoveReadSource.startPage(uri));
  }
  return WebPageTarget(uri);
}

/// What the input field starts with so only the id has to be typed.
String inputPrefix(Uri site) => '$site/read_book.php?id='.replaceFirst('//read', '/read');

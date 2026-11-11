/// Parses CSV exports from other password managers into importable records.
class ImportedItem {
  String title;
  String username;
  String password;
  String url;
  String notes;
  String? totp;
  String? folder;
  ImportedItem({
    this.title = '',
    this.username = '',
    this.password = '',
    this.url = '',
    this.notes = '',
    this.totp,
    this.folder,
  });
}

class ImportResult {
  final String source;
  final List<ImportedItem> items;
  const ImportResult(this.source, this.items);
}

class ImportService {
  ImportService._();

  /// RFC 4180 CSV parser (quoted fields, escaped quotes, embedded newlines).
  static List<List<String>> parseCsv(String input) {
    final text = input.startsWith('\uFEFF') ? input.substring(1) : input;
    final rows = <List<String>>[];
    var row = <String>[];
    final field = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < text.length; i++) {
      final c = text[i];
      if (inQuotes) {
        if (c == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(c);
        }
      } else if (c == '"') {
        inQuotes = true;
      } else if (c == ',') {
        row.add(field.toString());
        field.clear();
      } else if (c == '\n' || c == '\r') {
        if (c == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(field.toString());
        field.clear();
        if (row.any((f) => f.isNotEmpty)) rows.add(row);
        row = <String>[];
      } else {
        field.write(c);
      }
    }
    row.add(field.toString());
    if (row.any((f) => f.isNotEmpty)) rows.add(row);
    return rows;
  }

  static const _titleKeys = ['title', 'name', 'account', 'account name'];
  static const _urlKeys = [
    'url',
    'login_uri',
    'website',
    'web site',
    'login url',
    'uri',
  ];
  static const _userKeys = [
    'username',
    'login_username',
    'login name',
    'user name',
    'login',
    'email',
    'email address',
  ];
  static const _passKeys = ['password', 'login_password'];
  static const _noteKeys = ['notes', 'note', 'extra', 'comments', 'comment'];
  static const _totpKeys = [
    'otpauth',
    'totp',
    'login_totp',
    'otp secret',
    'otpsecret',
    'one-time password',
  ];
  static const _folderKeys = ['folder', 'grouping', 'group', 'category'];

  static String _detectSource(Set<String> h) {
    if (h.contains('login_uri') || h.contains('login_username')) {
      return 'Bitwarden';
    }
    if (h.contains('grouping') && h.contains('extra')) return 'LastPass';
    if (h.contains('otpauth') || (h.contains('title') && h.contains('type'))) {
      return '1Password';
    }
    if (h.contains('login name') && h.contains('web site')) return 'KeePass';
    if (h.contains('httprealm') || h.contains('timecreated')) return 'Firefox';
    if (h.contains('otpsecret') || h.contains('otp secret')) return 'Dashlane';
    if (h.contains('name') &&
        h.contains('url') &&
        h.contains('username') &&
        h.contains('password')) {
      return 'Chrome / Edge / Brave';
    }
    return 'Generic CSV';
  }

  static ImportResult? parse(String csv) {
    final rows = parseCsv(csv);
    if (rows.length < 2) return null;
    final header = rows.first.map((h) => h.trim().toLowerCase()).toList();
    final headerSet = header.toSet();

    int idx(List<String> keys) {
      for (final k in keys) {
        final i = header.indexOf(k);
        if (i >= 0) return i;
      }
      return -1;
    }

    final iTitle = idx(_titleKeys);
    final iUrl = idx(_urlKeys);
    final iUser = idx(_userKeys);
    final iPass = idx(_passKeys);
    final iNote = idx(_noteKeys);
    final iTotp = idx(_totpKeys);
    final iFolder = idx(_folderKeys);
    if (iPass < 0 && iUser < 0 && iUrl < 0) return null;

    String cell(List<String> r, int i) =>
        (i >= 0 && i < r.length) ? r[i].trim() : '';

    final items = <ImportedItem>[];
    for (final r in rows.skip(1)) {
      final url = cell(r, iUrl);
      var title = cell(r, iTitle);
      if (title.isEmpty) {
        title = Uri.tryParse(url)?.host ?? '';
        if (title.isEmpty) title = url;
      }
      final item = ImportedItem(
        title: title,
        username: cell(r, iUser),
        password: r.length > iPass && iPass >= 0 ? r[iPass] : '',
        url: url,
        notes: iNote >= 0 && iNote < r.length ? r[iNote] : '',
        totp: cell(r, iTotp).isEmpty ? null : cell(r, iTotp),
        folder: cell(r, iFolder).isEmpty ? null : cell(r, iFolder),
      );
      if (item.title.isEmpty &&
          item.username.isEmpty &&
          item.password.isEmpty) {
        continue;
      }
      items.add(item);
    }
    return ImportResult(_detectSource(headerSet), items);
  }
}

/// BCP-47 code of a language label such as "English" or "Italiano", null when
/// the label is not recognised. Labels are free text in the book, so common
/// English and native names and the codes themselves are accepted.
String? languageCodeFor(String label) {
  final key = label.trim().toLowerCase();
  if (key.isEmpty) return null;
  return _byName[key];
}

/// Primary language of a BCP-47 code: `pt-BR` and `pt-orig` give `pt`.
String baseLanguage(String code) =>
    code.toLowerCase().split(RegExp(r'[-_]')).first;

/// English name of the language [code] (`pt-BR` too), or the code itself
/// when it is not known.
String languageLabelFor(String code) {
  final base = baseLanguage(code);
  final names = _names[base];
  if (names == null) return code;
  final name = names.first;
  return name[0].toUpperCase() + name.substring(1);
}

/// Languages offered as one-tap additions: (label, code).
const suggestedLanguages = [
  ('English', 'en'),
  ('Italian', 'it'),
  ('Portuguese', 'pt'),
  ('Ukrainian', 'uk'),
  ('German', 'de'),
  ('French', 'fr'),
  ('Spanish', 'es'),
  ('Russian', 'ru'),
];

const _names = {
  'ru': ['russian', 'русский', 'російська', 'russo'],
  'en': ['english', 'inglese', 'английский', 'англійська'],
  'it': ['italian', 'italiano', 'итальянский', 'італійська'],
  'uk': ['ukrainian', 'українська', 'украинский', 'ucraino'],
  'de': ['german', 'deutsch', 'немецкий', 'німецька', 'tedesco'],
  'fr': ['french', 'français', 'francais', 'французский', 'французька', 'francese'],
  'es': ['spanish', 'español', 'espanol', 'испанский', 'іспанська', 'spagnolo'],
  'pl': ['polish', 'polski', 'польский', 'польська', 'polacco'],
  'nl': ['dutch', 'nederlands', 'нидерландский', 'olandese'],
  'pt': ['portuguese', 'português', 'portugues', 'португальский', 'portoghese'],
  'ro': ['romanian', 'română', 'romana', 'румынский', 'rumeno'],
  'cs': ['czech', 'čeština', 'cestina', 'чешский', 'ceco'],
  'sv': ['swedish', 'svenska', 'шведский', 'svedese'],
  'tr': ['turkish', 'türkçe', 'turkce', 'турецкий', 'turco'],
  'bg': ['bulgarian', 'български', 'болгарский', 'bulgaro'],
};

final _byName = {
  for (final e in _names.entries) ...{
    e.key: e.key,
    for (final n in e.value) n: e.key,
  }
};

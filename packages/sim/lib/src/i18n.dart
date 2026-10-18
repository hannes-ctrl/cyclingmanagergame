import 'i18n_de.dart';

/// Languages of the game.
enum Lang {
  en('English', 'GB'),
  de('Deutsch', 'DE');

  const Lang(this.label, this.flag);

  /// Name of the language in that language.
  final String label;

  /// ISO country code of the flag that stands for it.
  final String flag;
}

/// The language all texts are produced in. Texts are written in English in
/// the sources and looked up in the dictionary of the chosen language when
/// needed; texts that were already produced (inbox messages, race events)
/// keep the language they were written in.
class I18n {
  static Lang lang = Lang.en;
}

/// Translates a text into the current language and fills in its arguments.
///
/// @param en The English text, with `{0}`, `{1}` ... where arguments go.
/// @param args Values for the placeholders.
/// @returns The text in the current language; the English one if the
///   dictionary has no entry.
String tr(String en, [List<Object?> args = const []]) {
  var text = I18n.lang == Lang.en ? en : (german[en] ?? en);
  for (var i = args.length - 1; i >= 0; i--) {
    text = text.replaceAll('{$i}', '${args[i]}');
  }
  return text;
}

/// Whether a stored text is a given English text or its translation.
/// Texts in saves keep the language they were written in, so code that
/// recognises one must accept both.
///
/// @param text The stored text.
/// @param en The English text to compare with.
/// @returns true if they are the same text in either language.
bool isText(String text, String en) => text == en || text == german[en];

/// The source text of a stored key. Saves written before the sources were
/// in English hold some keys in German.
///
/// @param stored A key as it was stored.
/// @returns The English key; the stored one if it is not a translation.
String sourceText(String stored) {
  if (german.containsKey(stored)) return stored;
  for (final e in german.entries) {
    if (e.value == stored) return e.key;
  }
  return stored;
}

/// Formats a number with the decimal mark of the current language.
///
/// @param value The number.
/// @param digits Digits after the decimal mark.
/// @returns E.g. `3,5` in German and `3.5` in English.
String dec(num value, [int digits = 1]) {
  final text = value.toStringAsFixed(digits);
  return I18n.lang == Lang.de ? text.replaceAll('.', ',') : text;
}

const _monthsEn = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _two(int n) => n.toString().padLeft(2, '0');

/// A day as the current language writes it: `17.10.` in German, `17 Oct`
/// in English; with the year `17.10.2026` or `17 Oct 2026`.
///
/// @param d The day.
/// @param year Whether the year is part of it.
/// @returns The date.
String dayText(DateTime d, {bool year = false}) => I18n.lang == Lang.de
    ? '${_two(d.day)}.${_two(d.month)}.${year ? d.year : ''}'
    : '${d.day} ${_monthsEn[d.month - 1]}${year ? ' ${d.year}' : ''}';

/// A month as the current language writes it: `10.2026` or `Oct 2026`.
///
/// @param d A day of the month.
/// @returns The month.
String monthText(DateTime d) => I18n.lang == Lang.de
    ? '${_two(d.month)}.${d.year}'
    : '${_monthsEn[d.month - 1]} ${d.year}';

/// A count with its noun in the right number, in the current language:
/// `1 stage`, `3 stages`.
///
/// @param n The count.
/// @param one The text for one, with `{0}` for the count.
/// @param many The text for any other count.
/// @returns The text.
String trn(int n, String one, String many) => tr(n == 1 ? one : many, [n]);

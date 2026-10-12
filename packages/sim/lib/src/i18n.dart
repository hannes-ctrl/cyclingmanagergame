import 'i18n_en.dart';

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

/// The language all texts are produced in. Texts are written in German in
/// the sources and looked up in the English dictionary when needed; texts
/// that were already produced (inbox messages, race events) keep the
/// language they were written in.
class I18n {
  static Lang lang = Lang.en;
}

/// Translates a text into the current language and fills in its arguments.
///
/// @param de The German text, with `{0}`, `{1}` ... where arguments go.
/// @param args Values for the placeholders.
/// @returns The text in the current language; the German one if the
///   dictionary has no entry.
String tr(String de, [List<Object?> args = const []]) {
  var text = I18n.lang == Lang.de ? de : (english[de] ?? de);
  for (var i = args.length - 1; i >= 0; i--) {
    text = text.replaceAll('{$i}', '${args[i]}');
  }
  return text;
}

/// Whether a stored text is a given German text or its English version.
/// Texts in saves keep the language they were written in, so code that
/// recognises one must accept both.
///
/// @param text The stored text.
/// @param de The German text to compare with.
/// @returns true if they are the same text in either language.
bool isText(String text, String de) => text == de || text == english[de];

/// Formats a number with the decimal mark of the current language.
///
/// @param value The number.
/// @param digits Digits after the decimal mark.
/// @returns E.g. `3,5` in German and `3.5` in English.
String dec(num value, [int digits = 1]) {
  final text = value.toStringAsFixed(digits);
  return I18n.lang == Lang.de ? text.replaceAll('.', ',') : text;
}

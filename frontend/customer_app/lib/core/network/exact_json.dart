import 'dart:convert';

/// Preserve decimal number lexemes before Dart's JSON decoder can round them.
/// Integer metadata stays numeric; DTOs deliberately accept decimals as strings.
dynamic decodeExactJson(String source) {
  final tokens = RegExp(
    r'"(?:\\.|[^"\\])*"|-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?',
  );
  final preserved = source.replaceAllMapped(tokens, (match) {
    final token = match[0]!;
    if (token.startsWith('"')) return token;
    return token.contains(RegExp(r'[.eE]')) ? jsonEncode(token) : token;
  });
  return jsonDecode(preserved);
}

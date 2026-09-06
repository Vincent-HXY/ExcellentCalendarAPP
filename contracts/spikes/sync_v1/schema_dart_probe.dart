// Independent Dart strict JSON reader and assertions for the derived graph.
import 'dart:convert';
import 'dart:io';

class StrictJson {
  final String text;
  int pos = 0;
  StrictJson(this.text);
  void need(bool value) { if (!value) throw const FormatException('Invalid JSON'); }
  void space() { while (pos < text.length && ' \t\r\n'.contains(text[pos])) { pos++; } }
  bool take(String char) { if (pos < text.length && text[pos] == char) { pos++; return true; } return false; }
  String string() {
    final start = pos;
    need(take('"'));
    while (pos < text.length && text[pos] != '"') {
      if (text[pos] == '\\') pos++;
      pos++;
    }
    need(take('"'));
    final value = jsonDecode(text.substring(start, pos)) as String;
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        need(++i < value.length);
        final low = value.codeUnitAt(i);
        need(low >= 0xdc00 && low <= 0xdfff);
      } else { need(c < 0xdc00 || c > 0xdfff); }
    }
    return value;
  }
  dynamic value(int depth) {
    need(depth <= 128); space(); need(pos < text.length);
    if (text[pos] == '"') return string();
    if (take('{')) {
      final out = <String, dynamic>{}; space();
      if (take('}')) return out;
      do {
        space(); final key = string(); need(!out.containsKey(key)); space(); need(take(':'));
        out[key] = value(depth + 1); space();
        if (take('}')) return out;
        need(take(','));
      } while (true);
    }
    if (take('[')) {
      final out = <dynamic>[]; space();
      if (take(']')) return out;
      do {
        out.add(value(depth + 1)); space();
        if (take(']')) return out;
        need(take(','));
      } while (true);
    }
    for (final literal in ['null', 'true', 'false']) {
      if (text.startsWith(literal, pos)) { pos += literal.length; return jsonDecode(literal); }
    }
    final match = RegExp(r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?').matchAsPrefix(text, pos);
    need(match != null); pos = match!.end;
    // The wire's JSON number domain is binary64, including integer lexemes.
    final result = double.parse(match.group(0)!);
    need(result.isFinite); return result;
  }
  dynamic parse() { final result = value(0); space(); need(pos == text.length); return result; }
}

String number(num value) {
  if (value == 0) return '0';
  if (value is int) return value.toString();
  final negative = value < 0;
  final raw = value.abs().toString().toLowerCase().split('e');
  final exponent = raw.length == 2 ? int.parse(raw[1]) : 0;
  final point = raw[0].indexOf('.');
  var n = (point < 0 ? raw[0].length : point) + exponent;
  var digits = raw[0].replaceAll('.', '');
  while (digits.length > 1 && digits.startsWith('0')) { digits = digits.substring(1); n--; }
  while (digits.length > 1 && digits.endsWith('0')) { digits = digits.substring(0, digits.length - 1); }
  String out;
  if (n > 0 && n <= 21) {
    out = digits.length <= n ? digits + '0' * (n - digits.length) : '${digits.substring(0, n)}.${digits.substring(n)}';
  } else if (n <= 0 && n > -6) {
    out = '0.${'0' * -n}$digits';
  } else {
    out = digits[0] + (digits.length == 1 ? '' : '.${digits.substring(1)}') + 'e${n - 1 >= 0 ? '+' : ''}${n - 1}';
  }
  return (negative ? '-' : '') + out;
}

String canonical(dynamic value) {
  if (value is num) return number(value);
  if (value is List) return '[${value.map(canonical).join(',')}]';
  if (value is Map) {
    final keys = value.keys.cast<String>().toList()..sort();
    return '{${keys.map((key) => '${jsonEncode(key)}:${canonical(value[key])}').join(',')}}';
  }
  return jsonEncode(value);
}

bool date(String value) {
  if (!RegExp(r'^[0-9]{4}-[0-9]{2}-[0-9]{2}$').hasMatch(value)) return false;
  final y = int.parse(value.substring(0, 4)), m = int.parse(value.substring(5, 7)), d = int.parse(value.substring(8));
  final days = [0,31,28,31,30,31,30,31,31,30,31,30,31];
  if (y < 1 || m < 1 || m > 12 || d < 1) return false;
  return d <= days[m] + (m == 2 && y % 4 == 0 && (y % 100 != 0 || y % 400 == 0) ? 1 : 0);
}

bool format(String name, String value) {
  if (name == 'date') return date(value);
  if (name == 'email') return value.contains('@');
  if (name == 'uuid') return RegExp(r'^[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$').hasMatch(value);
  if (name == 'date-time') {
    final match = RegExp(r'^([0-9]{4}-[0-9]{2}-[0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})$').firstMatch(value);
    if (match == null || !date(match[1]!) || int.parse(match[2]!) > 23 || int.parse(match[3]!) > 59 || int.parse(match[4]!) > 59) return false;
    final offset = match[5]!;
    return offset.length == 1 || int.parse(offset.substring(1,3)) <= 23 && int.parse(offset.substring(4)) <= 59;
  }
  throw StateError('Unsupported format');
}

bool type(String name, dynamic value) {
  switch (name) {
    case 'null': return value == null;
    case 'boolean': return value is bool;
    case 'object': return value is Map;
    case 'array': return value is List;
    case 'string': return value is String;
    case 'number': return value is num && value.isFinite;
    case 'integer': return value is num && value.isFinite && value == value.truncateToDouble();
    default: throw StateError('Unsupported type');
  }
}

class Assertions {
  final List<dynamic> nodes;
  Assertions(this.nodes);
  bool valid(int index, dynamic value, [int depth = 0]) {
    if (depth > 256) return false;
    final rule = nodes[index] as Map<String, dynamic>;
    bool child(dynamic index, dynamic value) => valid((index as num).toInt(), value, depth + 1);
    bool smaller(String name, num value) => rule.containsKey(name) && value < (rule[name] as num);
    bool larger(String name, num value) => rule.containsKey(name) && value > (rule[name] as num);
    if (rule.containsKey('boolean')) return rule['boolean'] as bool;
    if (rule.containsKey('ref') && !child(rule['ref'], value)) return false;
    if (rule.containsKey('type')) {
      final types = rule['type'];
      if (types is String ? !type(types, value) : !(types as List).any((t) => type(t as String, value))) return false;
    }
    if (rule.containsKey('const') && canonical(rule['const']) != canonical(value)) return false;
    if (rule.containsKey('enum') && !(rule['enum'] as List).any((v) => canonical(v) == canonical(value))) return false;
    for (final name in ['allOf', 'anyOf', 'oneOf']) {
      if (!rule.containsKey(name)) continue;
      final list = rule[name] as List, count = (rule[name] as List).where((n) => child(n, value)).length;
      if (name == 'allOf' && count != list.length || name == 'anyOf' && count == 0 || name == 'oneOf' && count != 1) return false;
    }
    if (rule.containsKey('not') && child(rule['not'], value)) return false;
    if (rule.containsKey('if')) {
      final branch = child(rule['if'], value) ? 'then' : 'else';
      if (rule.containsKey(branch) && !child(rule[branch], value)) return false;
    }
    if (value is num && (smaller('minimum', value) || larger('maximum', value))) return false;
    if (value is String) {
      if (smaller('minLength', value.runes.length) || larger('maxLength', value.runes.length)) return false;
      if (rule.containsKey('pattern') && !RegExp(rule['pattern'] as String, unicode: true).hasMatch(value)) return false;
      if (rule.containsKey('format') && !format(rule['format'] as String, value)) return false;
    }
    if (value is List) {
      if (smaller('minItems', value.length) || larger('maxItems', value.length)) return false;
      if (rule['uniqueItems'] == true && value.map(canonical).toSet().length != value.length) return false;
      if (rule.containsKey('items') && value.any((v) => !child(rule['items'], v))) return false;
    }
    if (value is Map) {
      if (smaller('minProperties', value.length) || larger('maxProperties', value.length)) return false;
      if (rule.containsKey('required') && (rule['required'] as List).any((key) => !value.containsKey(key))) return false;
      final properties = (rule['properties'] ?? <String, dynamic>{}) as Map, patterns = (rule['patternProperties'] ?? <String, dynamic>{}) as Map;
      for (final entry in value.entries) {
        final key = entry.key as String; var matched = properties.containsKey(key);
        if (matched && !child(properties[key], entry.value)) return false;
        for (final p in patterns.entries) { if (RegExp(p.key as String, unicode: true).hasMatch(key)) { matched = true; if (!child(p.value, entry.value)) return false; } }
        if (!matched && rule.containsKey('additionalProperties') && !child(rule['additionalProperties'], entry.value)) return false;
        if (rule.containsKey('propertyNames') && !child(rule['propertyNames'], key)) return false;
      }
      if (rule.containsKey('dependentRequired')) {
        for (final entry in (rule['dependentRequired'] as Map).entries) {
          if (value.containsKey(entry.key) && (entry.value as List).any((key) => !value.containsKey(key))) return false;
        }
      }
    }
    return true;
  }
}

void main(List<String> args) {
  final bundle = StrictJson(File(args.single).readAsStringSync()).parse() as Map;
  final assertions = Assertions(bundle['nodes'] as List);
  for (final entry in bundle['cases'] as List) {
    try {
      final item = entry as Map, root = (entry['root'] as num).toInt();
      final value = StrictJson(item['input_json'] as String).parse();
      if (!assertions.valid(root, value)) { stdout.writeln('REJECT'); continue; }
      final encoded = canonical(value), again = StrictJson(canonical(value)).parse();
      if (!assertions.valid(root, again) || canonical(again) != encoded) throw const FormatException('Round trip changed');
      stdout.writeln('VALID\t${utf8.encode(encoded).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}');
    } on FormatException { stdout.writeln('REJECT'); }
  }
}

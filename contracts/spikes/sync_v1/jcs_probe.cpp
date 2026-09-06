// Isolated RFC 8785 feasibility consumer. No production dependency or writer.
// Requires the C numeric locale and FE_TONEAREST; the executable establishes both.
#include <algorithm>
#include <cfenv>
#include <charconv>
#include <clocale>
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <iostream>
#include <limits>
#include <set>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>
#include "sha256_probe.hpp"

namespace jcs {
void check(bool value) { if (!value) throw std::invalid_argument("Invalid JSON"); }
double parse_number(const std::string& raw) {
#if defined(__ANDROID__)
  // The pinned NDK has floating to_chars but no floating from_chars. Bionic's
  // decimal reader is checked against the same systematic IEEE boundary oracle.
  char* end = nullptr;
  const double value = std::strtod(raw.c_str(), &end);
  check(end == raw.c_str() + raw.size() && std::isfinite(value));
  return value;
#else
  // MinGW's legacy CRT strtod misrounds some powers-of-two neighbours. Use the
  // existing standard library's correctly rounded reader instead of that CRT.
  double value = 0;
  const auto result = std::from_chars(raw.data(), raw.data() + raw.size(), value);
  check(result.ptr == raw.data() + raw.size());
  if (result.ec == std::errc::result_out_of_range) {
    // from_chars reports both overflow and rounding-to-zero as out_of_range.
    // Classify using the decimal order, without a second inexact conversion.
    const auto start = raw.front() == '-' ? 1U : 0U;
    const auto e = raw.find_first_of("eE");
    const auto end = e == std::string::npos ? raw.size() : e;
    long long exponent = 0;
    if (e != std::string::npos) {
      std::size_t i = e + 1; const bool negative = raw[i] == '-';
      if (raw[i] == '+' || raw[i] == '-') ++i;
      for (; i < raw.size(); ++i) exponent = std::min(1000000000LL, exponent * 10 + raw[i] - '0');
      if (negative) exponent = -exponent;
    }
    long long digits = 0, before_point = 0, first_nonzero = -1;
    bool point = false;
    for (std::size_t i = start; i < end; ++i) {
      if (raw[i] == '.') { point = true; continue; }
      if (!point) ++before_point;
      if (raw[i] != '0' && first_nonzero == -1) first_nonzero = digits;
      ++digits;
    }
    check(first_nonzero < 0 || before_point - first_nonzero - 1 + exponent < 0);
    return 0;
  }
  check(result.ec == std::errc{} && std::isfinite(value));
  return value;
#endif
}
struct Value {
  enum Kind { Null, Boolean, Number, String, Array, Object } kind = Null;
  bool boolean = false;
  double number = 0;
  std::string string;
  std::vector<Value> array;
  std::vector<std::pair<std::string, Value>> object;
};
void append_utf8(std::string& out, unsigned cp) {
  check(cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff));
  if (cp < 0x80) out += static_cast<char>(cp);
  else if (cp < 0x800) {
    out += static_cast<char>(0xc0 | (cp >> 6)); out += static_cast<char>(0x80 | (cp & 63));
  } else if (cp < 0x10000) {
    out += static_cast<char>(0xe0 | (cp >> 12)); out += static_cast<char>(0x80 | ((cp >> 6) & 63));
    out += static_cast<char>(0x80 | (cp & 63));
  } else {
    out += static_cast<char>(0xf0 | (cp >> 18)); out += static_cast<char>(0x80 | ((cp >> 12) & 63));
    out += static_cast<char>(0x80 | ((cp >> 6) & 63)); out += static_cast<char>(0x80 | (cp & 63));
  }
}
unsigned next_utf8(const std::string& s, std::size_t& i) {
  check(i < s.size());
  unsigned first = static_cast<unsigned char>(s[i++]);
  if (first < 0x80) return first;
  const unsigned n = first >= 0xc2 && first <= 0xdf ? 2 :
                     first >= 0xe0 && first <= 0xef ? 3 : first >= 0xf0 && first <= 0xf4 ? 4 : 0;
  check(n != 0 && i + n - 1 <= s.size());
  unsigned cp = first & ((1U << (7 - n)) - 1);
  for (unsigned k = 1; k < n; ++k) {
    unsigned b = static_cast<unsigned char>(s[i++]); check((b & 0xc0) == 0x80); cp = (cp << 6) | (b & 63);
  }
  check(cp >= (n == 2 ? 0x80U : n == 3 ? 0x800U : 0x10000U) && cp <= 0x10ffff && !(cp >= 0xd800 && cp <= 0xdfff));
  return cp;
}
std::vector<unsigned> utf16(const std::string& s) {
  std::vector<unsigned> result;
  for (std::size_t i = 0; i < s.size();) {
    unsigned cp = next_utf8(s, i);
    if (cp > 0xffff) { cp -= 0x10000; result.push_back(0xd800 + (cp >> 10)); result.push_back(0xdc00 + (cp & 1023)); }
    else result.push_back(cp);
  }
  return result;
}
class Parser {
  const std::string& input; std::size_t i = 0;
  char peek() const { return i < input.size() ? input[i] : '\0'; }
  void space() { while (peek() == ' ' || peek() == '\n' || peek() == '\r' || peek() == '\t') ++i; }
  bool take(char c) { if (peek() == c && i < input.size()) { ++i; return true; } return false; }
  void expect(char c) { check(take(c)); }
  static bool digit(char c) { return c >= '0' && c <= '9'; }
  unsigned hex4() {
    unsigned cp = 0;
    for (int k = 0; k < 4; ++k) {
      check(i < input.size()); char c = input[i++];
      int n = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
      check(n >= 0); cp = cp * 16 + static_cast<unsigned>(n);
    }
    return cp;
  }
  std::string string() {
    expect('"'); std::string out;
    while (!take('"')) {
      check(i < input.size()); unsigned c = static_cast<unsigned char>(input[i]);
      if (c == '\\') {
        ++i; check(i < input.size()); char escaped = input[i++];
        switch (escaped) {
          case '"': case '\\': case '/': out += escaped; break;
          case 'b': out += '\b'; break; case 'f': out += '\f'; break;
          case 'n': out += '\n'; break; case 'r': out += '\r'; break; case 't': out += '\t'; break;
          case 'u': {
            unsigned cp = hex4();
            if (cp >= 0xd800 && cp <= 0xdbff) {
              expect('\\'); expect('u'); unsigned low = hex4(); check(low >= 0xdc00 && low <= 0xdfff);
              cp = 0x10000 + ((cp - 0xd800) << 10) + low - 0xdc00;
            }
            append_utf8(out, cp); break;
          }
          default: check(false);
        }
      } else { check(c >= 0x20); append_utf8(out, next_utf8(input, i)); }
    }
    return out;
  }
  Value value(unsigned depth) {
    check(depth <= 128); space(); Value v;
    if (peek() == '"') { v.kind = Value::String; v.string = string(); }
    else if (take('[')) {
      v.kind = Value::Array; space();
      if (!take(']')) { do { v.array.push_back(value(depth + 1)); space(); } while (take(',')); expect(']'); }
    } else if (take('{')) {
      v.kind = Value::Object; space(); std::set<std::string> keys;
      if (!take('}')) {
        do { space(); auto key = string(); check(keys.insert(key).second); space(); expect(':'); v.object.emplace_back(key, value(depth + 1)); space(); } while (take(','));
        expect('}');
      }
    } else if (input.compare(i, 4, "null") == 0) i += 4;
    else if (input.compare(i, 4, "true") == 0) { i += 4; v.kind = Value::Boolean; v.boolean = true; }
    else if (input.compare(i, 5, "false") == 0) { i += 5; v.kind = Value::Boolean; }
    else {
      v.kind = Value::Number; const std::size_t start = i;
      take('-'); check(digit(peek()));
      if (!take('0')) { while (digit(peek())) ++i; }
      if (take('.')) { check(digit(peek())); while (digit(peek())) ++i; }
      if (take('e') || take('E')) { if (!take('+')) take('-'); check(digit(peek())); while (digit(peek())) ++i; }
      v.number = parse_number(input.substr(start, i - start));
    }
    return v;
  }
 public:
  explicit Parser(const std::string& s) : input(s) { check(s.size() <= 32U * 1024U * 1024U); }
  Value parse() { auto v = value(0); space(); check(i == input.size()); return v; }
};
std::string number(double value) {
  check(std::isfinite(value)); if (value == 0) return "0";
  const bool negative = value < 0; value = std::abs(value);
  char buffer[64]{};
  // Both existing standard libraries provide the shortest round-trip formatter.
  // Do not approximate it by increasing printf precision: midpoint intervals
  // are asymmetric at binary exponent boundaries.
  const auto converted = std::to_chars(buffer, buffer + sizeof(buffer), value, std::chars_format::general);
  check(converted.ec == std::errc{});
  std::string raw(buffer, converted.ptr); const auto e = raw.find_first_of("eE");
  int exponent = e == std::string::npos ? 0 : std::stoi(raw.substr(e + 1));
  std::string digits = raw.substr(0, e); const auto dot = digits.find('.');
  if (dot != std::string::npos) { exponent -= static_cast<int>(digits.size() - dot - 1); digits.erase(dot, 1); }
  while (digits.size() > 1 && digits.front() == '0') digits.erase(0, 1);
  while (digits.size() > 1 && digits.back() == '0') { digits.pop_back(); ++exponent; }
  const int point = static_cast<int>(digits.size()) + exponent; std::string out;
  if (point > 0 && point <= 21) {
    out = digits;
    if (point >= static_cast<int>(out.size())) out.append(point - out.size(), '0'); else out.insert(point, 1, '.');
  } else if (point <= 0 && point > -6) out = "0." + std::string(-point, '0') + digits;
  else {
    out = digits.substr(0, 1); if (digits.size() > 1) out += "." + digits.substr(1);
    out += "e"; if (point - 1 >= 0) out += '+'; out += std::to_string(point - 1);
  }
  return negative ? "-" + out : out;
}
std::string quoted(const std::string& value) {
  std::string out = "\""; constexpr char hex[] = "0123456789abcdef";
  for (unsigned char c : value) {
    switch (c) {
      case '"': out += "\\\""; break; case '\\': out += "\\\\"; break;
      case '\b': out += "\\b"; break; case '\t': out += "\\t"; break; case '\n': out += "\\n"; break;
      case '\f': out += "\\f"; break; case '\r': out += "\\r"; break;
      default: if (c < 32) { out += "\\u00"; out += hex[c >> 4]; out += hex[c & 15]; } else out += static_cast<char>(c);
    }
  }
  return out + '"';
}
std::string encode(const Value& v) {
  switch (v.kind) {
    case Value::Null: return "null";
    case Value::Boolean: return v.boolean ? "true" : "false";
    case Value::Number: return number(v.number);
    case Value::String: return quoted(v.string);
    case Value::Array: {
      std::string out = "["; bool comma = false;
      for (const auto& item : v.array) { if (comma) out += ','; comma = true; out += encode(item); } return out + ']';
    }
    case Value::Object: {
      std::vector<const std::pair<std::string, Value>*> fields;
      for (const auto& field : v.object) fields.push_back(&field);
      std::sort(fields.begin(), fields.end(), [](const auto* a, const auto* b) { return utf16(a->first) < utf16(b->first); });
      std::string out = "{"; bool comma = false;
      for (const auto* field : fields) { if (comma) out += ','; comma = true; out += quoted(field->first) + ':' + encode(field->second); } return out + '}';
    }
  }
  throw std::logic_error("Unreachable JSON kind");
}
std::string hex(const std::string& bytes) {
  constexpr char alphabet[] = "0123456789abcdef"; std::string out;
  for (unsigned char c : bytes) { out += alphabet[c >> 4]; out += alphabet[c & 15]; } return out;
}
} // namespace jcs
std::string sha256(const std::string& value) {
  sync_spike::Sha256 hash;
  for (std::size_t i = 0; i < value.size(); i += 17) {
    hash.update(reinterpret_cast<const std::uint8_t*>(value.data() + i), std::min<std::size_t>(17, value.size() - i));
  }
  const auto bytes = hash.finish();
  return jcs::hex(std::string(reinterpret_cast<const char*>(bytes.data()), bytes.size()));
}
int main(int argc, char** argv) {
  if (!std::setlocale(LC_NUMERIC, "C") || std::fesetround(FE_TONEAREST) != 0) return 2;
  std::string line;
  while (std::getline(std::cin, line)) {
    try {
      if (argc == 2 && std::string(argv[1]) == "--sha256") { std::cout << sha256(line) << '\n'; continue; }
      const auto canonical = jcs::encode(jcs::Parser(line).parse());
      std::cout << "OK\t" << jcs::hex(canonical) << '\t' << sha256(canonical) << '\n';
    }
    catch (const std::exception&) { std::cout << "ERROR\n"; }
  }
}

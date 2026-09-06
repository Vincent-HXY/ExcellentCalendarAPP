// Isolated RFC 8785 consumer using the existing JDK only. Not a Backend service.
import java.io.*;
import java.math.*;
import java.nio.charset.*;
import java.security.MessageDigest;
import java.util.*;

public final class JcsProbe {
    private static void check(boolean value) {
        if (!value) throw new IllegalArgumentException("Invalid JSON");
    }
    private static void scalarString(String value) {
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            if (Character.isHighSurrogate(c)) {
                check(++i < value.length() && Character.isLowSurrogate(value.charAt(i)));
            } else check(!Character.isLowSurrogate(c));
        }
    }
    private static final class Parser {
        private final String text;
        private int pos;
        Parser(String text) { this.text = text; check(text.length() <= 32 * 1024 * 1024); }
        private char peek() { return pos < text.length() ? text.charAt(pos) : '\0'; }
        private boolean take(char c) {
            if (pos < text.length() && text.charAt(pos) == c) { pos++; return true; }
            return false;
        }
        private void expect(char c) { check(take(c)); }
        private void space() { while (peek() == ' ' || peek() == '\r' || peek() == '\n' || peek() == '\t') pos++; }
        private static boolean digit(char c) { return c >= '0' && c <= '9'; }
        private char hex4() {
            int result = 0;
            for (int i = 0; i < 4; i++) {
                check(pos < text.length()); char c = text.charAt(pos++);
                int n = c >= '0' && c <= '9' ? c - '0' : c >= 'a' && c <= 'f' ? c - 'a' + 10 : c >= 'A' && c <= 'F' ? c - 'A' + 10 : -1;
                check(n >= 0); result = result * 16 + n;
            }
            return (char) result;
        }
        private String string() {
            expect('"'); StringBuilder out = new StringBuilder();
            while (!take('"')) {
                check(pos < text.length()); char c = text.charAt(pos++);
                if (c == '\\') {
                    check(pos < text.length()); char e = text.charAt(pos++);
                    switch (e) {
                        case '"', '\\', '/' -> out.append(e);
                        case 'b' -> out.append('\b'); case 'f' -> out.append('\f');
                        case 'n' -> out.append('\n'); case 'r' -> out.append('\r'); case 't' -> out.append('\t');
                        case 'u' -> out.append(hex4());
                        default -> check(false);
                    }
                } else { check(c >= 32); out.append(c); }
            }
            String result = out.toString(); scalarString(result); return result;
        }
        private Object value(int depth) {
            check(depth <= 128); space();
            if (peek() == '"') return string();
            if (take('[')) {
                List<Object> result = new ArrayList<>(); space();
                if (!take(']')) { do { result.add(value(depth + 1)); space(); } while (take(',')); expect(']'); }
                return result;
            }
            if (take('{')) {
                Map<String, Object> result = new TreeMap<>(); space();
                if (!take('}')) {
                    do { space(); String key = string(); check(!result.containsKey(key)); space(); expect(':'); result.put(key, value(depth + 1)); space(); } while (take(','));
                    expect('}');
                }
                return result;
            }
            if (text.startsWith("null", pos)) { pos += 4; return null; }
            if (text.startsWith("true", pos)) { pos += 4; return Boolean.TRUE; }
            if (text.startsWith("false", pos)) { pos += 5; return Boolean.FALSE; }
            int start = pos; take('-'); check(digit(peek()));
            if (!take('0')) while (digit(peek())) pos++;
            if (take('.')) { check(digit(peek())); while (digit(peek())) pos++; }
            if (take('e') || take('E')) { if (!take('+')) take('-'); check(digit(peek())); while (digit(peek())) pos++; }
            double result = Double.parseDouble(text.substring(start, pos)); check(Double.isFinite(result)); return result;
        }
        Object parse() { Object result = value(0); space(); check(pos == text.length()); return result; }
    }
    private static String number(double value) {
        check(Double.isFinite(value)); if (value == 0) return "0";
        boolean negative = value < 0; value = Math.abs(value);
        BigDecimal exact = new BigDecimal(value), shortest = null;
        int order = exact.precision() - exact.scale() - 1;
        for (int precision = 1; precision <= 17; precision++) {
            // At powers of two the rounding interval is asymmetric. The closest
            // rounded decimal can be outside it while the neighbour is inside.
            BigDecimal floor = exact.setScale(precision - order - 1, RoundingMode.FLOOR);
            BigDecimal ceil = exact.setScale(precision - order - 1, RoundingMode.CEILING);
            boolean floorFits = floor.doubleValue() == value, ceilFits = ceil.doubleValue() == value;
            if (!floorFits && !ceilFits) continue;
            if (!floorFits) shortest = ceil;
            else if (!ceilFits) shortest = floor;
            else {
                int distance = exact.subtract(floor).compareTo(ceil.subtract(exact));
                shortest = distance < 0 ? floor : distance > 0 ? ceil
                    : exact.setScale(precision - order - 1, RoundingMode.HALF_EVEN);
            }
            break;
        }
        check(shortest != null);
        shortest = shortest.stripTrailingZeros();
        String digits = shortest.unscaledValue().toString(); int point = digits.length() - shortest.scale();
        String out;
        if (point > 0 && point <= 21) {
            out = point >= digits.length() ? digits + "0".repeat(point - digits.length()) : digits.substring(0, point) + "." + digits.substring(point);
        } else if (point <= 0 && point > -6) out = "0." + "0".repeat(-point) + digits;
        else out = digits.substring(0, 1) + (digits.length() > 1 ? "." + digits.substring(1) : "") + "e" + (point - 1 >= 0 ? "+" : "") + (point - 1);
        return negative ? "-" + out : out;
    }
    private static String quote(String value) {
        StringBuilder out = new StringBuilder("\"");
        for (int i = 0; i < value.length(); i++) {
            char c = value.charAt(i);
            switch (c) {
                case '"' -> out.append("\\\""); case '\\' -> out.append("\\\\");
                case '\b' -> out.append("\\b"); case '\t' -> out.append("\\t"); case '\n' -> out.append("\\n");
                case '\f' -> out.append("\\f"); case '\r' -> out.append("\\r");
                default -> { if (c < 32) out.append(String.format(Locale.ROOT, "\\u%04x", (int)c)); else out.append(c); }
            }
        }
        return out.append('"').toString();
    }
    private static String encode(Object value) {
        if (value == null) return "null";
        if (value instanceof Boolean b) return b.toString();
        if (value instanceof Double d) return number(d);
        if (value instanceof String s) return quote(s);
        StringJoiner result;
        if (value instanceof List<?> list) {
            result = new StringJoiner(",", "[", "]"); for (Object item : list) result.add(encode(item));
        } else {
            result = new StringJoiner(",", "{", "}");
            for (var entry : ((Map<?, ?>) value).entrySet()) result.add(quote((String) entry.getKey()) + ":" + encode(entry.getValue()));
        }
        return result.toString();
    }
    public static void main(String[] args) throws Exception {
        var decoder = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
        try (BufferedReader input = new BufferedReader(new InputStreamReader(System.in, decoder))) {
            String line;
            while ((line = input.readLine()) != null) {
                try {
                    byte[] bytes = encode(new Parser(line).parse()).getBytes(StandardCharsets.UTF_8);
                    System.out.println("OK\t" + HexFormat.of().formatHex(bytes) + "\t" + HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)));
                } catch (IllegalArgumentException ex) { System.out.println("ERROR"); }
            }
        } catch (CharacterCodingException ex) { System.out.println("ERROR"); }
    }
}

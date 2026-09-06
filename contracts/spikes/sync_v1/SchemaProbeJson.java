// Test-only access to the already audited strict JSON parser and JCS serializer.
// Java and Kotlin share this JVM parsing primitive; assertion consumers differ.
import java.lang.reflect.*;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;

public final class SchemaProbeJson {
    private static final Constructor<?> constructor;
    private static final Method parse;
    private static final Method encode;
    static {
        try {
            Class<?> parser = Class.forName("JcsProbe$Parser");
            constructor = parser.getDeclaredConstructor(String.class);
            parse = parser.getDeclaredMethod("parse");
            encode = JcsProbe.class.getDeclaredMethod("encode", Object.class);
            constructor.setAccessible(true); parse.setAccessible(true); encode.setAccessible(true);
        } catch (ReflectiveOperationException error) { throw new ExceptionInInitializerError(error); }
    }
    public static Object parse(String text) {
        try { return parse.invoke(constructor.newInstance(text)); }
        catch (ReflectiveOperationException error) { throw new IllegalArgumentException("Invalid JSON", error); }
    }
    public static String canonical(Object value) {
        try { return (String)encode.invoke(null, value); }
        catch (ReflectiveOperationException error) { throw new IllegalArgumentException("Invalid JSON", error); }
    }
    public static String hex(String value) { return HexFormat.of().formatHex(value.getBytes(StandardCharsets.UTF_8)); }
}

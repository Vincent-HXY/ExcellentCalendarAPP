// Independent JDK binary cursor encoder/authenticator. No Backend business code.
import java.io.*;
import java.nio.*;
import java.nio.charset.*;
import java.security.*;
import java.util.*;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

public final class CursorProbe {
    static final long MAX = 9007199254740991L;
    static final byte[] MAGIC = "ECSCUR01".getBytes(StandardCharsets.US_ASCII);
    static final byte[] DOMAIN = "ExcellentCalendar.SyncCursor.v1\n".getBytes(StandardCharsets.US_ASCII);
    static final String[] FIELDS = {"kind", "key_id", "account_id", "device_id", "protocol_version", "account_generation", "snapshot_upper_bound",
        "position", "bootstrap_id", "sync_transport_generation", "expires_at_epoch_seconds", "retention_floor_server_sequence", "resolved_cleanup_before_epoch_seconds"};
    static void require(boolean valid, String code) { if (!valid) throw new IllegalArgumentException(code); }
    static long number(Object value) {
        require(value instanceof Number, "SYNC_CURSOR_INVALID");
        double n = ((Number)value).doubleValue();
        require(Double.isFinite(n) && n >= 0 && n <= MAX && n == Math.rint(n), "SYNC_CURSOR_INVALID");
        return (long)n;
    }
    static UUID uuid(Object value, boolean v4) {
        require(value instanceof String, "SYNC_CURSOR_INVALID");
        UUID id = UUID.fromString((String)value);
        require(id.toString().equals(value) && id.variant() == 2 && (!v4 || id.version() == 4), "SYNC_CURSOR_INVALID");
        return id;
    }
    static void putUuid(ByteBuffer buffer, Object value, boolean v4) {
        UUID id = value == null ? new UUID(0, 0) : uuid(value, v4);
        buffer.putLong(id.getMostSignificantBits()).putLong(id.getLeastSignificantBits());
    }
    static String getUuid(ByteBuffer buffer) {
        UUID id = new UUID(buffer.getLong(), buffer.getLong());
        return id.getMostSignificantBits() == 0 && id.getLeastSignificantBits() == 0 ? null : id.toString();
    }
    static byte[] raw(Map<String,Object> claims) {
        require(claims.keySet().equals(new HashSet<>(Arrays.asList(FIELDS))), "SYNC_CURSOR_INVALID");
        boolean bootstrap = "bootstrap".equals(claims.get("kind"));
        require(bootstrap || "sync".equals(claims.get("kind")), "SYNC_CURSOR_INVALID");
        require(number(claims.get("protocol_version")) == 1, "SYNC_CURSOR_INVALID");
        long upper = number(claims.get("snapshot_upper_bound")), position = number(claims.get("position"));
        long transport = number(claims.get("sync_transport_generation")), expiry = number(claims.get("expires_at_epoch_seconds"));
        require(number(claims.get("retention_floor_server_sequence")) <= upper, "SYNC_CURSOR_INVALID");
        if (bootstrap) { uuid(claims.get("bootstrap_id"), true); require(expiry > 0, "SYNC_CURSOR_INVALID"); }
        else require(claims.get("bootstrap_id") == null && transport == 0 && expiry == 0 && position <= upper, "SYNC_CURSOR_INVALID");
        ByteBuffer buffer = ByteBuffer.allocate(133).order(ByteOrder.BIG_ENDIAN);
        buffer.put(MAGIC).put((byte)(bootstrap ? 1 : 0));
        uuid(claims.get("key_id"), true); uuid(claims.get("account_id"), false); uuid(claims.get("device_id"), true);
        putUuid(buffer, claims.get("key_id"), true); putUuid(buffer, claims.get("account_id"), false); putUuid(buffer, claims.get("device_id"), true);
        buffer.putInt(1);
        for (int i = 5; i <= 7; i++) buffer.putLong(number(claims.get(FIELDS[i])));
        putUuid(buffer, claims.get("bootstrap_id"), true);
        for (int i = 9; i < FIELDS.length; i++) buffer.putLong(number(claims.get(FIELDS[i])));
        return buffer.array();
    }
    static byte[] mac(byte[] key, byte[] data) throws Exception {
        require(key.length == 32, "SYNC_CURSOR_INVALID");
        Mac mac = Mac.getInstance("HmacSHA256"); mac.init(new SecretKeySpec(key, "HmacSHA256"));
        mac.update(DOMAIN); return mac.doFinal(data);
    }
    static String issue(Map<String,Object> claims, Map<String,byte[]> keys) throws Exception {
        byte[] data = raw(claims); byte[] key = keys.get(claims.get("key_id"));
        require(key != null, "SYNC_CURSOR_INVALID");
        ByteBuffer buffer = ByteBuffer.allocate(165); buffer.put(data).put(mac(key, data));
        return Base64.getUrlEncoder().withoutPadding().encodeToString(buffer.array());
    }
    static Map<String,Object> authenticate(String token, Map<String,byte[]> keys) throws Exception {
        require(token.matches("[A-Za-z0-9_-]{220}"), "SYNC_CURSOR_INVALID");
        byte[] signed = Base64.getUrlDecoder().decode(token);
        require(signed.length == 165 && Base64.getUrlEncoder().withoutPadding().encodeToString(signed).equals(token), "SYNC_CURSOR_INVALID");
        ByteBuffer buffer = ByteBuffer.wrap(signed, 0, 133).order(ByteOrder.BIG_ENDIAN);
        byte[] magic = new byte[8]; buffer.get(magic); int kind = buffer.get() & 255;
        String keyId = getUuid(buffer); byte[] key = keys.get(keyId);
        require(key != null && MessageDigest.isEqual(Arrays.copyOfRange(signed, 133, 165), mac(key, Arrays.copyOf(signed, 133))), "SYNC_CURSOR_INVALID");
        require(Arrays.equals(magic, MAGIC) && kind <= 1, "SYNC_CURSOR_INVALID");
        Map<String,Object> c = new HashMap<>(); c.put("kind", kind == 0 ? "sync" : "bootstrap"); c.put("key_id", keyId);
        c.put("account_id", getUuid(buffer)); c.put("device_id", getUuid(buffer)); c.put("protocol_version", (long)buffer.getInt());
        for (int i = 5; i <= 7; i++) c.put(FIELDS[i], buffer.getLong());
        c.put("bootstrap_id", getUuid(buffer));
        for (int i = 9; i < FIELDS.length; i++) c.put(FIELDS[i], buffer.getLong());
        raw(c); return c;
    }
    static void validate(String token, Map<String,byte[]> keys, Map<String,Object> context) throws Exception {
        Map<String,Object> c = authenticate(token, keys);
        require(c.get("account_id").equals(context.get("account_id")), "SYNC_CURSOR_ACCOUNT_MISMATCH");
        require(c.get("device_id").equals(context.get("device_id")), "SYNC_CURSOR_DEVICE_MISMATCH");
        boolean bootstrap = "bootstrap".equals(c.get("kind"));
        require(number(c.get("account_generation")) == number(context.get("account_generation")), bootstrap ? "SYNC_BOOTSTRAP_GENERATION_CHANGED" : "SYNC_CURSOR_GENERATION_MISMATCH");
        if (bootstrap) {
            require(number(c.get("sync_transport_generation")) == number(context.get("sync_transport_generation")), "SYNC_TRANSPORT_GENERATION_MISMATCH");
            require(number(context.get("now_epoch_seconds")) < number(c.get("expires_at_epoch_seconds")), "SYNC_BOOTSTRAP_EXPIRED");
        } else require(number(c.get("position")) >= number(context.get("retention_floor_server_sequence")), "SYNC_CURSOR_EXPIRED");
    }
    @SuppressWarnings("unchecked") public static void main(String[] args) throws Exception {
        var decoder = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
        try (var reader = new BufferedReader(new InputStreamReader(System.in, decoder))) {
            String line;
            while ((line = reader.readLine()) != null) {
                try {
                    Map<String,Object> request = (Map<String,Object>)ProofCapsuleProbe.parse(line);
                    Map<String,byte[]> keys = new HashMap<>();
                    for (var entry : ((Map<String,Object>)request.get("keys")).entrySet()) keys.put(entry.getKey(), HexFormat.of().parseHex((String)entry.getValue()));
                    if ("issue".equals(request.get("action"))) System.out.println("SIGNED\t" + issue((Map<String,Object>)request.get("claims"), keys));
                    else { validate((String)request.get("token"), keys, (Map<String,Object>)request.get("context")); System.out.println("VALID"); }
                } catch (Exception error) {
                    String message = error.getMessage();
                    System.out.println(message != null && message.startsWith("SYNC_") ? message : "SYNC_CURSOR_INVALID");
                }
            }
        }
    }
}

// Independent JDK capsule consumer and one-shot public golden signer. Reflection
// reuses the already audited private JCS probe, without changing its hash/sources.
import java.io.*;
import java.lang.reflect.*;
import java.nio.charset.*;
import java.security.*;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.*;
import java.util.*;

public final class ProofCapsuleProbe {
    static Object parse(String input) throws Exception {
        Class<?> type = Class.forName("JcsProbe$Parser");
        Constructor<?> constructor = type.getDeclaredConstructor(String.class); constructor.setAccessible(true);
        Method method = type.getDeclaredMethod("parse"); method.setAccessible(true);
        return method.invoke(constructor.newInstance(input));
    }
    static String jcs(Object value) throws Exception {
        Method method = JcsProbe.class.getDeclaredMethod("encode", Object.class); method.setAccessible(true);
        return (String)method.invoke(null, value);
    }
    static byte[] utf8(String text) { return text.getBytes(StandardCharsets.UTF_8); }
    static String decodeUtf8(byte[] bytes) throws Exception {
        return StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(java.nio.ByteBuffer.wrap(bytes)).toString();
    }
    static String sha(byte[] bytes) throws Exception { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(bytes)); }
    static String hash(Object value) throws Exception { return sha(utf8(jcs(value))); }
    static void check(boolean condition) { if (!condition) throw new IllegalArgumentException("invalid proof"); }
    @SuppressWarnings("unchecked") static Map<String,Object> map(Object value) { check(value instanceof Map); return (Map<String,Object>)value; }
    static String str(Object value) { check(value instanceof String); return (String)value; }
    static void keys(Map<String,Object> map, String... names) { check(map.keySet().equals(Set.of(names))); }
    static void number(Object value, double expected) { check(value instanceof Double && (Double)value == expected); }
    static void hashString(String value) { check(value.matches("[0-9a-f]{64}")); }
    static byte[] unb64(String text) {
        check(!text.isEmpty() && text.matches("[A-Za-z0-9_-]+"));
        byte[] bytes = Base64.getUrlDecoder().decode(text);
        check(Base64.getUrlEncoder().withoutPadding().encodeToString(bytes).equals(text)); return bytes;
    }
    static String keyId(byte[] modulus) throws Exception {
        ByteArrayOutputStream input = new ByteArrayOutputStream(); input.write(utf8("ExcellentCalendar.RSAKey.v1\n"));
        input.write(new byte[]{1,0,1}); input.write(modulus); return sha(input.toByteArray());
    }
    static boolean authenticated(String line) {
        try {
            check(utf8(line).length <= 4 * 1024 * 1024);
            Map<String,Object> request = map(parse(line));
            keys(request, "trust_store", "locally_revoked_keys", "token", "expected_account_id", "expected_purpose", "claim_data", "claimed_hash");
            String account = str(request.get("expected_account_id")); check(account.matches("[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}"));
            String purpose = str(request.get("expected_purpose")); check(Set.of("device_fence", "import_range_close", "account_deleted").contains(purpose));
            Set<String> revoked = new HashSet<>(); check(request.get("locally_revoked_keys") instanceof List);
            for (Object item : (List<?>)request.get("locally_revoked_keys")) { String id = str(item); hashString(id); check(revoked.add(id)); }
            String token = str(request.get("token")); check(token.length() <= 2048);
            String raw = decodeUtf8(unb64(token)); Map<String,Object> capsule = map(parse(raw));
            check(jcs(capsule).equals(raw)); keys(capsule, "claims", "signature");
            Map<String,Object> claims = map(capsule.get("claims"));
            keys(claims, "proof_version", "algorithm", "key_id", "account_id", "purpose", "claims_sha256");
            number(claims.get("proof_version"), 1); check(str(claims.get("algorithm")).equals("rsa_pss_sha256"));
            check(str(claims.get("account_id")).equals(account) && str(claims.get("purpose")).equals(purpose));
            String claimed = str(request.get("claimed_hash")); hashString(claimed);
            check(str(claims.get("claims_sha256")).equals(claimed) && hash(request.get("claim_data")).equals(claimed));
            String id = str(claims.get("key_id")); hashString(id); check(!revoked.contains(id));
            byte[] signature = unb64(str(capsule.get("signature"))); check(signature.length == 256);
            Map<String,Object> trust = map(request.get("trust_store")); keys(trust, "schema_version", "trust_store_id", "keys");
            number(trust.get("schema_version"), 1); Map<String,Object> addressed = new TreeMap<>(trust); addressed.remove("trust_store_id");
            check(hash(addressed).equals(str(trust.get("trust_store_id"))));
            check(trust.get("keys") instanceof List); List<?> entries = (List<?>)trust.get("keys"); check(!entries.isEmpty() && entries.size() <= 32);
            byte[] selected = null; String previous = "";
            for (Object item : entries) {
                Map<String,Object> entry = map(item); keys(entry, "key_id", "algorithm", "exponent", "modulus_hex", "verification_status");
                String entryId = str(entry.get("key_id")); hashString(entryId); check(entryId.compareTo(previous) > 0); previous = entryId;
                check(str(entry.get("algorithm")).equals("rsa_pss_sha256")); number(entry.get("exponent"), 65537);
                String hex = str(entry.get("modulus_hex")); check(hex.matches("[89a-f][0-9a-f]{511}")); byte[] modulus = HexFormat.of().parseHex(hex);
                check(keyId(modulus).equals(entryId)); String status = str(entry.get("verification_status")); check(Set.of("trusted", "revoked").contains(status));
                if (entryId.equals(id)) { check(status.equals("trusted")); selected = modulus; }
            }
            check(selected != null);
            return ProofSignatureProbe.verifyPlatform(selected, utf8("ExcellentCalendar.SyncProof.v1\n" + jcs(claims)), signature);
        } catch (Exception error) { return false; }
    }
    static void generate(BufferedReader input) throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA"); generator.initialize(new RSAKeyGenParameterSpec(2048, RSAKeyGenParameterSpec.F4));
        KeyPair[] pairs = {generator.generateKeyPair(), generator.generateKeyPair()}; List<Object> keys = new ArrayList<>();
        for (KeyPair pair : pairs) {
            byte[] signed = ((RSAPublicKey)pair.getPublic()).getModulus().toByteArray(); check(signed.length == 257 && signed[0] == 0);
            byte[] modulus = Arrays.copyOfRange(signed, 1, 257);
            keys.add(new TreeMap<>(Map.of("key_id", keyId(modulus), "algorithm", "rsa_pss_sha256", "exponent", 65537.0,
                "modulus_hex", HexFormat.of().formatHex(modulus), "verification_status", "trusted")));
        }
        System.out.println(jcs(new TreeMap<>(Map.of("keys", keys))));
        for (String line; (line = input.readLine()) != null;) {
            Map<String,Object> request = map(parse(line)); int slot = ((Double)request.get("key_slot")).intValue(); check(slot == 0 || slot == 1);
            Map<String,Object> claims = new TreeMap<>(Map.of("proof_version", 1.0, "algorithm", "rsa_pss_sha256",
                "key_id", map(keys.get(slot)).get("key_id"), "account_id", request.get("account_id"), "purpose", request.get("purpose"), "claims_sha256", hash(request.get("data"))));
            if (request.containsKey("claims_override")) claims.putAll(map(request.get("claims_override")));
            Signature signer = Signature.getInstance("RSASSA-PSS"); signer.setParameter(new PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, 32, 1));
            signer.initSign(pairs[slot].getPrivate()); signer.update(utf8("ExcellentCalendar.SyncProof.v1\n" + jcs(claims)));
            Map<String,Object> capsule = new TreeMap<>(Map.of("claims", claims, "signature", Base64.getUrlEncoder().withoutPadding().encodeToString(signer.sign())));
            System.out.println(jcs(new TreeMap<>(Map.of("id", request.get("id"), "token", Base64.getUrlEncoder().withoutPadding().encodeToString(utf8(jcs(capsule))), "claimed_hash", hash(request.get("data"))))));
        }
        // No key serialization; all committed outputs are public verification data.
    }
    public static void main(String[] args) throws Exception {
        var decoder = StandardCharsets.UTF_8.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT);
        try (BufferedReader input = new BufferedReader(new InputStreamReader(System.in, decoder))) {
            if (args.length == 1 && args[0].equals("--generate-public-golden")) { generate(input); return; }
            if (args.length != 1 || !args[0].equals("--verify-lines")) throw new IllegalArgumentException("arguments");
            for (String line; (line = input.readLine()) != null;) System.out.println(authenticated(line) ? "VALID" : "REJECT");
        }
    }
}

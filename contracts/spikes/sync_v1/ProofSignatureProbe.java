// Isolated RSA-PSS primitive/JNI feasibility. No production signing key or dependency.
import java.io.*;
import java.math.BigInteger;
import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.interfaces.RSAPublicKey;
import java.security.spec.*;
import java.util.*;

public final class ProofSignatureProbe {
    private static final PSSParameterSpec PARAMETERS = new PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, 32, 1);
    private static native boolean nativeVerify(byte[] modulus, byte[] message, byte[] signature);

    public static boolean verifyPlatform(byte[] modulus, byte[] message, byte[] signature) {
        try {
            if (modulus.length != 256 || (modulus[0] & 0x80) == 0 || signature.length != 256 || message.length > 1048576) return false;
            PublicKey key = KeyFactory.getInstance("RSA").generatePublic(new RSAPublicKeySpec(new BigInteger(1, modulus), BigInteger.valueOf(65537)));
            // Android uses its documented API 23+ name. Do not fall back to a
            // provider default: MGF digest and salt length must be explicit.
            String algorithm = System.getProperty("java.vm.name", "").equals("Dalvik") ? "SHA256withRSA/PSS" : "RSASSA-PSS";
            Signature verifier = Signature.getInstance(algorithm);
            verifier.setParameter(PARAMETERS);
            verifier.initVerify(key);
            verifier.update(message);
            return verifier.verify(signature);
        } catch (GeneralSecurityException | IllegalArgumentException error) {
            return false;
        }
    }

    private static byte[] sign(PrivateKey key, byte[] message, String algorithm, PSSParameterSpec parameters) throws Exception {
        Signature signer = Signature.getInstance(algorithm);
        if (parameters != null) signer.setParameter(parameters);
        signer.initSign(key);
        signer.update(message);
        return signer.sign();
    }

    private static String hex(byte[] bytes) {
        char[] out = new char[bytes.length * 2];
        String alphabet = "0123456789abcdef";
        for (int i = 0; i < bytes.length; i++) {
            out[2 * i] = alphabet.charAt((bytes[i] & 255) >>> 4);
            out[2 * i + 1] = alphabet.charAt(bytes[i] & 15);
        }
        return new String(out);
    }

    private static byte[] unhex(String value) {
        if (value.length() % 2 != 0 || !value.matches("[0-9a-f]*")) throw new IllegalArgumentException("hex");
        byte[] out = new byte[value.length() / 2];
        for (int i = 0; i < out.length; i++) out[i] = (byte) Integer.parseInt(value.substring(i * 2, i * 2 + 2), 16);
        return out;
    }

    private static void emit(PrintWriter out, String id, byte[] modulus, byte[] message, byte[] signature, boolean valid) {
        out.println(id + "\t" + hex(modulus) + "\t" + hex(message) + "\t" + hex(signature) + "\t" + (valid ? "1" : "0"));
    }

    private static void generate(File file) throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("RSA");
        generator.initialize(new RSAKeyGenParameterSpec(2048, RSAKeyGenParameterSpec.F4));
        KeyPair pair = generator.generateKeyPair();
        byte[] signedModulus = ((RSAPublicKey) pair.getPublic()).getModulus().toByteArray();
        byte[] modulus = Arrays.copyOfRange(signedModulus, 1, signedModulus.length);
        if (modulus.length != 256) throw new IllegalStateException("RSA modulus");
        List<byte[]> messages = Arrays.asList(new byte[0], "ExcellentCalendar.SyncProof.v1\n{}".getBytes(StandardCharsets.UTF_8),
            "中文😀\u0000proof".getBytes(StandardCharsets.UTF_8), new byte[] {0, 1, 127, (byte)128, (byte)255}, new byte[1024]);
        try (PrintWriter out = new PrintWriter(new OutputStreamWriter(new FileOutputStream(file), StandardCharsets.UTF_8))) {
            for (int i = 0; i < messages.size(); i++) emit(out, "PS-POS-" + i, modulus, messages.get(i), sign(pair.getPrivate(), messages.get(i), "RSASSA-PSS", PARAMETERS), true);
            byte[] message = messages.get(1);
            byte[] signature = sign(pair.getPrivate(), message, "RSASSA-PSS", PARAMETERS);
            byte[] changedMessage = message.clone(); changedMessage[0] ^= 1;
            emit(out, "PS-NEG-message", modulus, changedMessage, signature, false);
            byte[] changedSignature = signature.clone(); changedSignature[128] ^= 1;
            emit(out, "PS-NEG-signature", modulus, message, changedSignature, false);
            emit(out, "PS-NEG-short", modulus, message, Arrays.copyOf(signature, 255), false);
            emit(out, "PS-NEG-zero", modulus, message, new byte[256], false);
            byte[] changedKey = modulus.clone(); changedKey[127] ^= 1;
            emit(out, "PS-NEG-key", changedKey, message, signature, false);
            emit(out, "PS-NEG-small-key", Arrays.copyOf(modulus, 255), message, signature, false);
            emit(out, "PS-NEG-pkcs1", modulus, message, sign(pair.getPrivate(), message, "SHA256withRSA", null), false);
            emit(out, "PS-NEG-salt0", modulus, message, sign(pair.getPrivate(), message, "RSASSA-PSS", new PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA256, 0, 1)), false);
            emit(out, "PS-NEG-mgf-sha1", modulus, message, sign(pair.getPrivate(), message, "RSASSA-PSS", new PSSParameterSpec("SHA-256", "MGF1", MGF1ParameterSpec.SHA1, 32, 1)), false);
        }
        // The private key is never written or printed. The committed fixture
        // contains only public verification inputs, not reusable signing keys.
    }

    public static void main(String[] args) throws Exception {
        if (args.length == 2 && args[0].equals("generate")) { generate(new File(args[1])); return; }
        if (args.length < 2 || !args[0].equals("verify")) throw new IllegalArgumentException("mode");
        boolean nativeMode = args.length == 3;
        if (nativeMode) System.load(args[2]);
        int total = 0;
        try (BufferedReader reader = new BufferedReader(new InputStreamReader(new FileInputStream(args[1]), StandardCharsets.UTF_8))) {
            for (String line; (line = reader.readLine()) != null;) {
                String[] fields = line.split("\t", -1);
                if (fields.length != 5) throw new IllegalArgumentException("fixture");
                byte[] modulus = unhex(fields[1]), message = unhex(fields[2]), signature = unhex(fields[3]);
                boolean actual = nativeMode ? nativeVerify(modulus, message, signature) : verifyPlatform(modulus, message, signature);
                if (actual != fields[4].equals("1")) throw new IllegalStateException("case " + fields[0]);
                total++;
                System.out.println(fields[0] + "\tPASS");
            }
        }
        if (total != 14) throw new IllegalStateException("fixture count");
        System.out.println("PASS\t" + total);
    }
}

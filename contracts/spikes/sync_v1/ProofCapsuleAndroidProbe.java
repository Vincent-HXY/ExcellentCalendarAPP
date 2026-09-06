// Android harness: full C++ capsule validation with only RSA verification in JCA.
import java.io.*;
import java.nio.charset.StandardCharsets;

public final class ProofCapsuleAndroidProbe {
    private static native boolean nativeAuthenticate(byte[] request);
    public static boolean verifyPlatform(byte[] modulus, byte[] message, byte[] signature) {
        return ProofSignatureProbe.verifyPlatform(modulus, message, signature);
    }
    public static void main(String[] args) throws Exception {
        if (args.length != 2) throw new IllegalArgumentException("arguments");
        System.load(args[1]);
        try (BufferedReader input = new BufferedReader(new InputStreamReader(new FileInputStream(args[0]), StandardCharsets.UTF_8))) {
            for (String line; (line = input.readLine()) != null;)
                System.out.println(nativeAuthenticate(line.getBytes(StandardCharsets.UTF_8)) ? "VALID" : "REJECT");
        }
    }
}

// Isolated JCE AEAD feasibility probe. Android Keystore ownership is separately
// verified by android_key_spike_result.json; this class does not simulate it.
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.HexFormat;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;
public final class PrivateRecordProbe {
  public static void main(String[] args) throws Exception {
    var hex=HexFormat.of(); byte[] key=hex.parseHex(args[1]), aad=hex.parseHex(args[2]), input=hex.parseHex(args[3]);
    try {
      var cipher=Cipher.getInstance("AES/GCM/NoPadding");
      if(args[0].equals("seal")) {
        byte[] nonce=new byte[12]; new SecureRandom().nextBytes(nonce);
        cipher.init(Cipher.ENCRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,nonce)); cipher.updateAAD(aad);
        byte[] ciphertext=cipher.doFinal(input), result=Arrays.copyOf(nonce,nonce.length+ciphertext.length);
        System.arraycopy(ciphertext,0,result,nonce.length,ciphertext.length); System.out.print(hex.formatHex(result));
      } else if(args[0].equals("open") && input.length>=28) {
        cipher.init(Cipher.DECRYPT_MODE,new SecretKeySpec(key,"AES"),new GCMParameterSpec(128,Arrays.copyOf(input,12))); cipher.updateAAD(aad);
        System.out.print(hex.formatHex(cipher.doFinal(Arrays.copyOfRange(input,12,input.length))));
      } else throw new IllegalArgumentException("Invalid probe input");
    } finally { Arrays.fill(key,(byte)0); }
  }
}

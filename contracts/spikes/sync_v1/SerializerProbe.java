import java.io.BufferedReader;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.HexFormat;
import tools.jackson.databind.json.JsonMapper;

/** CT0 audit of the existing Jackson dependency, never a production canonicalizer. */
public class SerializerProbe {
    public static void main(String[] args) throws Exception {
        var mapper = JsonMapper.builder().build();
        var reader = new BufferedReader(new InputStreamReader(System.in, StandardCharsets.UTF_8));
        String line;
        while ((line = reader.readLine()) != null) {
            try {
                var bytes = mapper.writeValueAsBytes(mapper.readTree(line));
                System.out.println("OK\t" + HexFormat.of().formatHex(bytes));
            } catch (RuntimeException error) {
                System.out.println("ERROR");
            }
        }
    }
}

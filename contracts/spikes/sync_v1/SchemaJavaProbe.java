// Independent Java assertion consumer for the derived Contract graph.
import java.nio.file.*;
import java.time.*;
import java.util.*;
import java.util.regex.Pattern;

public final class SchemaJavaProbe {
    private final List<?> nodes;
    private SchemaJavaProbe(List<?> nodes) { this.nodes = nodes; }
    private static boolean type(String type, Object value) {
        return switch (type) {
            case "null" -> value == null;
            case "boolean" -> value instanceof Boolean;
            case "object" -> value instanceof Map;
            case "array" -> value instanceof List;
            case "string" -> value instanceof String;
            case "number" -> value instanceof Double d && Double.isFinite(d);
            case "integer" -> value instanceof Double d && Double.isFinite(d) && d == Math.rint(d);
            default -> throw new IllegalArgumentException("Unsupported schema type");
        };
    }
    private static boolean same(Object a, Object b) { return SchemaProbeJson.canonical(a).equals(SchemaProbeJson.canonical(b)); }
    private static boolean format(String name, String text) {
        try {
            switch (name) {
                case "date": return text.matches("[0-9]{4}-[0-9]{2}-[0-9]{2}") && LocalDate.parse(text).getYear() >= 1 && LocalDate.parse(text).toString().equals(text);
                case "date-time": {
                    var m = Pattern.compile("([0-9]{4}-[0-9]{2}-[0-9]{2})[Tt]([0-9]{2}):([0-9]{2}):([0-9]{2})(?:\\.[0-9]+)?([Zz]|[+-][0-9]{2}:[0-9]{2})").matcher(text);
                    if (!m.matches() || !format("date", m.group(1)) || Integer.parseInt(m.group(2)) > 23 || Integer.parseInt(m.group(3)) > 59 || Integer.parseInt(m.group(4)) > 59) return false;
                    String offset = m.group(5);
                    return offset.length() == 1 || Integer.parseInt(offset.substring(1, 3)) <= 23 && Integer.parseInt(offset.substring(4)) <= 59;
                }
                case "uuid": return text.length() == 36 && UUID.fromString(text).toString().equalsIgnoreCase(text);
                case "email": return text.contains("@");
                default: throw new IllegalArgumentException("Unsupported format");
            }
        } catch (DateTimeException | IllegalArgumentException error) { return false; }
    }
    @SuppressWarnings("unchecked")
    private boolean valid(int index, Object value, int depth) {
        if (depth > 256) return false;
        Map<String,Object> rule = (Map<String,Object>)nodes.get(index);
        if (rule.containsKey("boolean")) return (Boolean)rule.get("boolean");
        if (rule.containsKey("ref") && !child(rule.get("ref"),value,depth)) return false;
        if (rule.containsKey("type")) {
            Object types=rule.get("type");
            if (types instanceof String s) { if (!type(s,value)) return false; }
            else if (((List<String>)types).stream().noneMatch(t -> type(t,value))) return false;
        }
        if (rule.containsKey("const") && !same(rule.get("const"),value)) return false;
        if (rule.containsKey("enum") && ((List<?>)rule.get("enum")).stream().noneMatch(item -> same(item,value))) return false;
        for (String name : List.of("allOf","anyOf","oneOf")) if (rule.containsKey(name)) {
            int count=0; List<?> list=(List<?>)rule.get(name);
            for (Object item:list) if(child(item,value,depth)) count++;
            if (name.equals("allOf") && count!=list.size() || name.equals("anyOf") && count==0 || name.equals("oneOf") && count!=1) return false;
        }
        if (rule.containsKey("not") && child(rule.get("not"),value,depth)) return false;
        if (rule.containsKey("if")) {
            String branch=child(rule.get("if"),value,depth)?"then":"else";
            if(rule.containsKey(branch) && !child(rule.get(branch),value,depth)) return false;
        }
        if(value instanceof Double number) {
            if(rule.containsKey("minimum") && number<(Double)rule.get("minimum") || rule.containsKey("maximum") && number>(Double)rule.get("maximum")) return false;
        }
        if(value instanceof String text) {
            int length=text.codePointCount(0,text.length());
            if(rule.containsKey("minLength") && length<(Double)rule.get("minLength") || rule.containsKey("maxLength") && length>(Double)rule.get("maxLength")) return false;
            if(rule.containsKey("pattern") && !Pattern.compile((String)rule.get("pattern"),Pattern.UNICODE_CHARACTER_CLASS).matcher(text).find()) return false;
            if(rule.containsKey("format") && !format((String)rule.get("format"),text)) return false;
        }
        if(value instanceof List<?> list) {
            if(rule.containsKey("minItems") && list.size()<(Double)rule.get("minItems") || rule.containsKey("maxItems") && list.size()>(Double)rule.get("maxItems")) return false;
            if(Boolean.TRUE.equals(rule.get("uniqueItems")) && new HashSet<>(list.stream().map(SchemaProbeJson::canonical).toList()).size()!=list.size()) return false;
            if(rule.containsKey("items")) for(Object item:list) if(!child(rule.get("items"),item,depth)) return false;
        }
        if(value instanceof Map<?,?> map) {
            if(rule.containsKey("minProperties") && map.size()<(Double)rule.get("minProperties") || rule.containsKey("maxProperties") && map.size()>(Double)rule.get("maxProperties")) return false;
            if(rule.containsKey("required")) for(Object key:(List<?>)rule.get("required")) if(!map.containsKey(key)) return false;
            Map<String,Object> properties=(Map<String,Object>)rule.getOrDefault("properties",Map.of());
            Map<String,Object> patterns=(Map<String,Object>)rule.getOrDefault("patternProperties",Map.of());
            for(var entry:map.entrySet()) {
                String key=(String)entry.getKey(); Object member=entry.getValue(); boolean matched=properties.containsKey(key);
                if(matched && !child(properties.get(key),member,depth)) return false;
                for(var pattern:patterns.entrySet()) if(Pattern.compile(pattern.getKey()).matcher(key).find()) {matched=true;if(!child(pattern.getValue(),member,depth)) return false;}
                if(!matched && rule.containsKey("additionalProperties") && !child(rule.get("additionalProperties"),member,depth)) return false;
                if(rule.containsKey("propertyNames") && !child(rule.get("propertyNames"),key,depth)) return false;
            }
            if(rule.containsKey("dependentRequired")) for(var entry:((Map<String,List<String>>)rule.get("dependentRequired")).entrySet())
                if(map.containsKey(entry.getKey())) for(String key:entry.getValue()) if(!map.containsKey(key)) return false;
        }
        return true;
    }
    private boolean child(Object index,Object value,int depth) {return valid(((Double)index).intValue(),value,depth+1);}
    public static void main(String[] args) throws Exception {
        Map<?,?> bundle=(Map<?,?>)SchemaProbeJson.parse(Files.readString(Path.of(args[0])));
        SchemaJavaProbe validator=new SchemaJavaProbe((List<?>)bundle.get("nodes"));
        for(Object row:(List<?>)bundle.get("cases")) {
            try {
                Map<?,?> item=(Map<?,?>)row; int root=((Double)item.get("root")).intValue();
                Object value=SchemaProbeJson.parse((String)item.get("input_json"));
                if(!validator.valid(root,value,0)) {System.out.println("REJECT");continue;}
                String canonical=SchemaProbeJson.canonical(value); Object again=SchemaProbeJson.parse(canonical);
                if(!validator.valid(root,again,0) || !canonical.equals(SchemaProbeJson.canonical(again))) throw new IllegalArgumentException("Round trip changed");
                System.out.println("VALID\t"+SchemaProbeJson.hex(canonical));
            } catch (IllegalArgumentException error) {System.out.println("REJECT");}
        }
    }
}

import jakarta.validation.Validation;
import jakarta.validation.Validator;
import jakarta.validation.metadata.ConstraintDescriptor;
import jakarta.validation.metadata.ContainerElementTypeDescriptor;
import jakarta.validation.metadata.PropertyDescriptor;
import java.lang.reflect.Array;
import java.lang.reflect.RecordComponent;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.Comparator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.TreeSet;
import tools.jackson.databind.json.JsonMapper;

/** Read compiled DTO metadata only. Never constructs a request, session or application context. */
public final class BackendShapeProbe {
    private static Object plain(Object value) {
        if (value instanceof Class<?> type) return type.getName();
        if (value instanceof Enum<?> member) return member.name();
        if (value != null && value.getClass().isArray()) {
            List<Object> result = new ArrayList<>();
            for (int i = 0; i < Array.getLength(value); i++) result.add(plain(Array.get(value, i)));
            return result;
        }
        return value;
    }

    private static List<Map<String, Object>> constraints(Set<ConstraintDescriptor<?>> values) {
        List<Map<String, Object>> result = new ArrayList<>();
        for (var constraint : values) {
            Map<String, Object> attributes = new TreeMap<>();
            constraint.getAttributes().forEach((key, value) -> {
                if (!Set.of("message", "groups", "payload").contains(key)) attributes.put(key, plain(value));
            });
            result.add(Map.of("annotation", constraint.getAnnotation().annotationType().getName(), "attributes", attributes));
        }
        result.sort(Comparator.comparing(row -> (String) row.get("annotation")));
        return result;
    }

    private static List<Map<String, Object>> containers(Set<ContainerElementTypeDescriptor> values) {
        List<Map<String, Object>> result = new ArrayList<>();
        for (var value : values) {
            Map<String, Object> row = new LinkedHashMap<>();
            row.put("type_argument_index", value.getTypeArgumentIndex());
            row.put("java_type", value.getElementClass().getTypeName());
            row.put("cascaded", value.isCascaded());
            row.put("constraints", constraints(value.getConstraintDescriptors()));
            row.put("container_elements", containers(value.getConstrainedContainerElementTypes()));
            result.add(row);
        }
        result.sort(Comparator.comparing(row -> String.valueOf(row.get("type_argument_index"))));
        return result;
    }

    private static void inspect(Class<?> type, Validator validator, Map<String, Object> records) {
        if (!type.isRecord() || records.containsKey(type.getName())) return;
        Map<String, Object> record = new LinkedHashMap<>();
        records.put(type.getName(), record);
        var bean = validator.getConstraintsForClass(type);
        record.put("class_constraints", constraints(bean.getConstraintDescriptors()));
        Map<String, Object> fields = new TreeMap<>();
        record.put("fields", fields);
        for (RecordComponent component : type.getRecordComponents()) {
            String name = component.getName().replaceAll("([a-z0-9])([A-Z])", "$1_$2").toLowerCase(java.util.Locale.ROOT);
            Map<String, Object> field = new LinkedHashMap<>();
            field.put("java_name", component.getName());
            field.put("java_type", component.getGenericType().getTypeName());
            field.put("primitive", component.getType().isPrimitive());
            PropertyDescriptor property = bean.getConstraintsForProperty(component.getName());
            field.put("constraints", property == null ? List.of() : constraints(property.getConstraintDescriptors()));
            field.put("cascaded", property != null && property.isCascaded());
            field.put("container_elements", property == null ? List.of() : containers(property.getConstrainedContainerElementTypes()));
            field.put("size_unit", component.getType() == String.class ? "UTF16_code_units" : "container_cardinality");
            fields.put(name, field);
            inspect(component.getType(), validator, records);
        }
    }

    public static void main(String[] args) throws Exception {
        var mapper = JsonMapper.builder().build();
        var input = mapper.readTree(Files.readString(Path.of(args[0])));
        Map<String, Object> records = new TreeMap<>();
        Set<String> roots = new TreeSet<>();
        try (var factory = Validation.buildDefaultValidatorFactory()) {
            var validator = factory.getValidator();
            for (var root : input) {
                String name = root.asString();
                roots.add(name);
                inspect(Class.forName(name, false, BackendShapeProbe.class.getClassLoader()), validator, records);
            }
        }
        Files.writeString(Path.of(args[1]), mapper.writeValueAsString(Map.of("roots", roots, "records", records,
            "request_instances_created", false, "application_context_started", false)) + "\n");
    }
}

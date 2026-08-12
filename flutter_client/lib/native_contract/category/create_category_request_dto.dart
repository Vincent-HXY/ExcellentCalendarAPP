class CreateCategoryRequestDto {
  const CreateCategoryRequestDto({
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
    required this.sortOrder,
  });

  final String name;
  final String? description;
  final String color;
  final String? icon;
  final int? sortOrder;

  Map<String, dynamic> toJson() {
    CategoryContractValue.nonBlankText(
      name,
      'CreateCategoryRequest.name',
      maximumLength: 40,
    );
    CategoryContractValue.optionalInputText(
      description,
      'CreateCategoryRequest.description',
      maximumLength: 200,
    );
    CategoryContractValue.inputColor(color, 'CreateCategoryRequest.color');
    CategoryContractValue.optionalInputText(
      icon,
      'CreateCategoryRequest.icon',
      maximumLength: 64,
    );
    if (sortOrder != null &&
        (sortOrder! < 0 ||
            sortOrder! > CategoryContractValue.maximumSortOrder)) {
      throw const FormatException(
        'CreateCategoryRequest.sort_order must be null or in the Contract range.',
      );
    }
    return {
      'name': name,
      'description': description,
      'color': color,
      'icon': icon,
      'sort_order': sortOrder,
    };
  }
}

abstract final class CategoryContractValue {
  static const maximumSortOrder = 9007199254740991;

  static final RegExp _uuidV4Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
  static final RegExp _inputColorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
  static final RegExp _canonicalColorPattern = RegExp(r'^#[0-9A-F]{6}$');

  static void uuidV4(String value, String field) {
    if (!_uuidV4Pattern.hasMatch(value)) {
      throw FormatException('$field must be a canonical lowercase UUIDv4.');
    }
  }

  static void nonBlankText(
    String value,
    String field, {
    required int maximumLength,
  }) {
    if (value.trim().isEmpty || value.runes.length > maximumLength) {
      throw FormatException(
        '$field must be non-blank and at most $maximumLength characters.',
      );
    }
  }

  static void optionalNonBlankText(
    String? value,
    String field, {
    required int maximumLength,
  }) {
    if (value != null) {
      nonBlankText(value, field, maximumLength: maximumLength);
    }
  }

  static void optionalInputText(
    String? value,
    String field, {
    required int maximumLength,
  }) {
    if (value != null &&
        (value.isEmpty || value.runes.length > maximumLength)) {
      throw FormatException(
        '$field must be null or contain 1 to $maximumLength characters.',
      );
    }
  }

  static void inputColor(String value, String field) {
    if (!_inputColorPattern.hasMatch(value)) {
      throw FormatException('$field must use #RRGGBB.');
    }
  }

  static void optionalCanonicalColor(String? value, String field) {
    if (value != null && !_canonicalColorPattern.hasMatch(value)) {
      throw FormatException(
        '$field must be null or canonical uppercase #RRGGBB.',
      );
    }
  }
}

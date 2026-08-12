import 'dart:collection';

import '../../application/category/category_models.dart';
import '../../gateway_interfaces/category_repository.dart';
import '../../native_contract/category/create_category_request_dto.dart';

typedef CategoryClock = DateTime Function();
typedef FakeCategoryIdGenerator = String Function(int sequence);

class FakeCategoryRepository implements CategoryRepository {
  FakeCategoryRepository({
    CategoryClock? clock,
    FakeCategoryIdGenerator? idGenerator,
    Iterable<Category> initialCategories = const [],
    bool seedDefault = true,
    this.operationDelay = Duration.zero,
  }) : _clock = clock ?? _systemUtcNow,
       _idGenerator = idGenerator ?? _defaultIdGenerator {
    if (seedDefault) {
      final createdAt = _wholeSecondUtc(_clock());
      _entries[defaultCategoryId] = Category(
        id: defaultCategoryId,
        name: '默认日程',
        description: null,
        color: '#5C93E5',
        icon: null,
        sortOrder: 0,
        createdAt: createdAt,
        updatedAt: createdAt,
        deletedAt: null,
      );
    }
    for (final category in initialCategories) {
      _validateFixture(category);
      _entries[category.id] = category;
    }
  }

  final CategoryClock _clock;
  final FakeCategoryIdGenerator _idGenerator;
  final Duration operationDelay;
  final LinkedHashMap<String, Category> _entries =
      LinkedHashMap<String, Category>();

  CategoryFailureCode? _nextListFailure;
  CategoryFailureCode? _nextCreateFailure;
  int _nextId = 1;

  int listCallCount = 0;
  int createCallCount = 0;

  void failNextList({
    CategoryFailureCode code = CategoryFailureCode.serviceUnavailable,
  }) {
    _nextListFailure = code;
  }

  void failNextCreate({
    CategoryFailureCode code = CategoryFailureCode.serviceUnavailable,
  }) {
    _nextCreateFailure = code;
  }

  @override
  Future<List<Category>> listActiveCategories() async {
    listCallCount += 1;
    await _waitForOperation();
    final failure = _nextListFailure;
    _nextListFailure = null;
    if (failure != null) {
      throw CategoryRepositoryException(failure, retryable: true);
    }
    return sortCategories(
      _entries.values.where((category) => category.deletedAt == null),
    );
  }

  @override
  Future<Category> createCategory(CreateCategoryCommand command) async {
    createCallCount += 1;
    await _waitForOperation();
    final failure = _nextCreateFailure;
    _nextCreateFailure = null;
    if (failure != null) {
      throw CategoryRepositoryException(failure, retryable: true);
    }

    if (command.name.trim().isEmpty) {
      throw const CategoryRepositoryException(CategoryFailureCode.nameEmpty);
    }
    if (command.name.runes.length > 40 ||
        (command.description != null && command.description!.isEmpty) ||
        (command.description?.runes.length ?? 0) > 200 ||
        (command.icon != null && command.icon!.isEmpty) ||
        (command.icon?.runes.length ?? 0) > 64 ||
        (command.sortOrder != null &&
            (command.sortOrder! < 0 ||
                command.sortOrder! > CategoryContractValue.maximumSortOrder)) ||
        !_inputHexColorPattern.hasMatch(command.color)) {
      throw const CategoryRepositoryException(
        CategoryFailureCode.contractValidation,
      );
    }

    final name = command.name.trim();
    final description = _optionalText(command.description);
    final color = command.color.trim().toUpperCase();
    if (name.runes.length > 40 ||
        (description?.runes.length ?? 0) > 200 ||
        !_hexColorPattern.hasMatch(color)) {
      throw const CategoryRepositoryException(
        CategoryFailureCode.contractValidation,
      );
    }

    final id = _idGenerator(_nextId++);
    if (!_uuidV4Pattern.hasMatch(id) || _entries.containsKey(id)) {
      throw const CategoryRepositoryException(
        CategoryFailureCode.contractValidation,
        debugMessage:
            'Fake category ID generator must return a unique lowercase UUIDv4.',
      );
    }
    final activeSortOrders = _entries.values
        .where((category) => category.deletedAt == null)
        .map((category) => category.sortOrder)
        .whereType<int>();
    final maxSortOrder = activeSortOrders.fold<int>(
      -1,
      (current, value) => value > current ? value : current,
    );
    if (command.sortOrder == null &&
        maxSortOrder == CategoryContractValue.maximumSortOrder) {
      throw const CategoryRepositoryException(
        CategoryFailureCode.sortOrderExhausted,
      );
    }
    final now = _wholeSecondUtc(_clock());
    final icon = _optionalText(command.icon);
    if ((icon?.runes.length ?? 0) > 64) {
      throw const CategoryRepositoryException(
        CategoryFailureCode.contractValidation,
      );
    }
    final category = Category(
      id: id,
      name: name,
      description: description,
      color: color,
      icon: icon,
      sortOrder: command.sortOrder ?? maxSortOrder + 1,
      createdAt: now,
      updatedAt: now,
      deletedAt: null,
    );
    _entries[id] = category;
    return category;
  }

  Future<void> _waitForOperation() async {
    if (operationDelay != Duration.zero) {
      await Future<void>.delayed(operationDelay);
    }
  }

  static String? _optionalText(String? value) {
    final trimmed = value?.trim();
    return trimmed == null || trimmed.isEmpty ? null : trimmed;
  }

  static DateTime _systemUtcNow() => DateTime.now().toUtc();

  static DateTime _wholeSecondUtc(DateTime value) {
    final utc = value.toUtc();
    return DateTime.fromMicrosecondsSinceEpoch(
      utc.microsecondsSinceEpoch -
          utc.microsecondsSinceEpoch % Duration.microsecondsPerSecond,
      isUtc: true,
    );
  }

  static bool _isWholeSecondUtc(DateTime value) =>
      value.isUtc &&
      value.microsecondsSinceEpoch % Duration.microsecondsPerSecond == 0;

  static String _defaultIdGenerator(int sequence) =>
      '00000000-0000-4000-8000-${sequence.toString().padLeft(12, '0')}';

  static void _validateFixture(Category category) {
    final description = category.description;
    final color = category.color;
    final icon = category.icon;
    final valid =
        _uuidV4Pattern.hasMatch(category.id) &&
        category.name.trim().isNotEmpty &&
        category.name.runes.length <= 40 &&
        (description == null ||
            (description.trim().isNotEmpty &&
                description.runes.length <= 200)) &&
        (color == null || _hexColorPattern.hasMatch(color)) &&
        (icon == null || (icon.trim().isNotEmpty && icon.runes.length <= 64)) &&
        (category.sortOrder == null ||
            (category.sortOrder! >= 0 &&
                category.sortOrder! <=
                    CategoryContractValue.maximumSortOrder)) &&
        _isWholeSecondUtc(category.createdAt) &&
        _isWholeSecondUtc(category.updatedAt) &&
        !category.updatedAt.isBefore(category.createdAt) &&
        (category.deletedAt == null || _isWholeSecondUtc(category.deletedAt!));
    if (!valid) {
      throw ArgumentError.value(
        category.id,
        'initialCategories',
        'Fake Category fixtures must conform to CategoryResponse.',
      );
    }
  }

  static const defaultCategoryId = '10000000-0000-4000-8000-000000000001';

  static final RegExp _hexColorPattern = RegExp(r'^#[0-9A-F]{6}$');
  static final RegExp _inputHexColorPattern = RegExp(r'^#[0-9A-Fa-f]{6}$');
  static final RegExp _uuidV4Pattern = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
  );
}

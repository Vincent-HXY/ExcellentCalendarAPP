enum SearchTargetType {
  event('event'),
  habit('habit'),
  anniversary('anniversary');

  const SearchTargetType(this.wireValue);
  final String wireValue;

  static SearchTargetType fromWireValue(String value) => switch (value) {
    'event' => event,
    'habit' => habit,
    'anniversary' => anniversary,
    _ => throw FormatException('Unknown SearchTargetType: $value'),
  };
}

enum SearchSortBy {
  relevance('relevance'),
  occurTime('occur_time'),
  updatedAt('updated_at');

  const SearchSortBy(this.wireValue);
  final String wireValue;

  static SearchSortBy fromWireValue(String value) => switch (value) {
    'relevance' => relevance,
    'occur_time' => occurTime,
    'updated_at' => updatedAt,
    _ => throw FormatException('Unknown SearchSortBy: $value'),
  };
}

enum SearchMatchedField {
  title('title'),
  content('content'),
  description('description'),
  note('note'),
  location('location'),
  categoryName('category_name');

  const SearchMatchedField(this.wireValue);
  final String wireValue;

  static SearchMatchedField fromWireValue(String value) => switch (value) {
    'title' => title,
    'content' => content,
    'description' => description,
    'note' => note,
    'location' => location,
    'category_name' => categoryName,
    _ => throw FormatException('Unknown SearchMatchedField: $value'),
  };
}

enum SearchEventStatus {
  pending('pending'),
  inProgress('in_progress'),
  overdue('overdue'),
  completed('completed'),
  skipped('skipped');

  const SearchEventStatus(this.wireValue);
  final String wireValue;

  static SearchEventStatus fromWireValue(String value) => switch (value) {
    'pending' => pending,
    'in_progress' => inProgress,
    'overdue' => overdue,
    'completed' => completed,
    'skipped' => skipped,
    _ => throw FormatException('Unknown SearchEventStatus: $value'),
  };
}

enum SearchHabitLifecycle {
  upcoming('upcoming'),
  active('active'),
  completed('completed'),
  endedEarly('ended_early');

  const SearchHabitLifecycle(this.wireValue);
  final String wireValue;

  static SearchHabitLifecycle fromWireValue(String value) => switch (value) {
    'upcoming' => upcoming,
    'active' => active,
    'completed' => completed,
    'ended_early' => endedEarly,
    _ => throw FormatException('Unknown SearchHabitLifecycle: $value'),
  };
}

enum SearchAnniversaryRelation {
  remaining('remaining'),
  elapsed('elapsed'),
  today('today');

  const SearchAnniversaryRelation(this.wireValue);
  final String wireValue;

  static SearchAnniversaryRelation fromWireValue(String value) =>
      switch (value) {
        'remaining' => remaining,
        'elapsed' => elapsed,
        'today' => today,
        _ => throw FormatException('Unknown SearchAnniversaryRelation: $value'),
      };
}

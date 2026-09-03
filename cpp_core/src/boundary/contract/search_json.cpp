#include "excellent_calendar/boundary/contract/search_json.hpp"

#include <utility>

namespace excellent_calendar::boundary::contract {
namespace {

picojson::value nullable(const std::optional<std::string>& value) {
  return value.has_value() ? picojson::value(*value) : picojson::value();
}

picojson::value nullable(const std::optional<int>& value) {
  return value.has_value() ? picojson::value(static_cast<double>(*value))
                           : picojson::value();
}

picojson::value nullable(const std::optional<std::int64_t>& value) {
  return value.has_value() ? picojson::value(static_cast<double>(*value))
                           : picojson::value();
}

picojson::value nullable(const std::optional<domain::LocalDate>& value) {
  return value.has_value()
             ? picojson::value(domain::format_local_date(*value))
             : picojson::value();
}

picojson::value category_json(
    const std::optional<application::SearchCategoryProjection>& category) {
  if (!category.has_value()) return picojson::value();
  picojson::object value;
  value["id"] = picojson::value(category->id);
  value["name"] = picojson::value(category->name);
  value["color"] = nullable(category->color);
  value["icon"] = nullable(category->icon);
  return picojson::value(std::move(value));
}

picojson::value match_json(const domain::SearchMatch& match) {
  picojson::array matched_fields;
  for (const auto field : match.matched_fields)
    matched_fields.emplace_back(domain::search_match_field_to_string(field));
  picojson::value snippet;
  if (match.snippet.has_value()) {
    picojson::object value;
    value["field"] = picojson::value(
        domain::search_match_field_to_string(match.snippet->field));
    value["text"] = picojson::value(match.snippet->text);
    value["prefix_truncated"] =
        picojson::value(match.snippet->prefix_truncated);
    value["suffix_truncated"] =
        picojson::value(match.snippet->suffix_truncated);
    snippet = picojson::value(std::move(value));
  }
  picojson::object value;
  value["primary_field"] =
      picojson::value(domain::search_match_field_to_string(match.primary_field));
  value["matched_fields"] = picojson::value(std::move(matched_fields));
  value["snippet"] = std::move(snippet);
  return picojson::value(std::move(value));
}

picojson::value item_json(const application::SearchItem& item) {
  picojson::object value;
  if (const auto* event = std::get_if<application::SearchEventItem>(&item)) {
    value["target_type"] = picojson::value("event");
    value["target_id"] = picojson::value(event->target_id);
    value["title"] = picojson::value(event->title);
    value["match"] = match_json(event->match);
    value["category"] = category_json(event->category);
    value["updated_at"] = picojson::value(event->updated_at);
    value["status"] = picojson::value(event->status);
    value["is_all_day"] = picojson::value(event->is_all_day);
    value["is_recurring"] = picojson::value(event->is_recurring);
    value["occur_at"] = nullable(event->occur_at);
    value["occur_date"] = nullable(event->occur_date);
    value["location"] = nullable(event->location);
    value["recurrence_revision"] = nullable(event->recurrence_revision);
    value["occurrence_key"] = nullable(event->occurrence_key);
  } else if (const auto* habit =
                 std::get_if<application::SearchHabitItem>(&item)) {
    value["target_type"] = picojson::value("habit");
    value["target_id"] = picojson::value(habit->target_id);
    value["title"] = picojson::value(habit->title);
    value["match"] = match_json(habit->match);
    value["category"] = category_json(habit->category);
    value["updated_at"] = picojson::value(habit->updated_at);
    value["lifecycle_status"] = picojson::value(habit->lifecycle_status);
    value["occur_date"] =
        picojson::value(domain::format_local_date(habit->occur_date));
    value["challenge_start_date"] =
        picojson::value(domain::format_local_date(habit->challenge_start_date));
    value["challenge_end_date"] =
        picojson::value(domain::format_local_date(habit->challenge_end_date));
    value["ended_date"] = nullable(habit->ended_date);
    value["remaining_days"] =
        picojson::value(static_cast<double>(habit->remaining_days));
    value["target_count_hundredths"] =
        nullable(habit->target_count_hundredths);
    value["unit"] = nullable(habit->unit);
  } else {
    const auto& anniversary =
        std::get<application::SearchAnniversaryItem>(item);
    value["target_type"] = picojson::value("anniversary");
    value["target_id"] = picojson::value(anniversary.target_id);
    value["title"] = picojson::value(anniversary.title);
    value["match"] = match_json(anniversary.match);
    value["category"] = category_json(anniversary.category);
    value["updated_at"] = picojson::value(anniversary.updated_at);
    value["occurrence_key"] = picojson::value(anniversary.occurrence_key);
    value["occur_date"] =
        picojson::value(domain::format_local_date(anniversary.occur_date));
    value["source_date"] =
        picojson::value(domain::format_local_date(anniversary.source_date));
    value["is_repeating"] = picojson::value(anniversary.is_repeating);
    value["relation"] = picojson::value(anniversary.relation);
    value["days"] = picojson::value(static_cast<double>(anniversary.days));
    value["years_elapsed"] =
        picojson::value(static_cast<double>(anniversary.years_elapsed));
  }
  return picojson::value(std::move(value));
}

}  // namespace

picojson::value search_query_response_json(
    const application::SearchQueryResponse& response) {
  picojson::array sections;
  for (const auto& section : response.sections) {
    picojson::array items;
    for (const auto& item : section.items) items.push_back(item_json(item));
    picojson::object value;
    value["target_type"] = picojson::value(
        domain::search_target_type_to_string(section.target_type));
    value["items"] = picojson::value(std::move(items));
    value["total_count"] =
        picojson::value(static_cast<double>(section.total_count));
    value["has_more"] = picojson::value(section.has_more);
    value["next_cursor"] = nullable(section.next_cursor);
    sections.emplace_back(std::move(value));
  }
  picojson::object value;
  value["query_generation"] =
      picojson::value(static_cast<double>(response.query_generation));
  value["normalized_keyword"] = picojson::value(response.normalized_keyword);
  value["timezone"] = picojson::value(response.timezone);
  value["evaluated_at"] = picojson::value(response.evaluated_at);
  value["snapshot_token"] = picojson::value(response.snapshot_token);
  value["sections"] = picojson::value(std::move(sections));
  return picojson::value(std::move(value));
}

}  // namespace excellent_calendar::boundary::contract

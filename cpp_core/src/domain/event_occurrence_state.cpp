#include "excellent_calendar/domain/event_occurrence_state.hpp"

namespace excellent_calendar::domain {

bool is_valid_occurrence_status(std::string_view value) {
  return value == kOccurrenceScheduled || value == kOccurrenceCompleted ||
         value == kOccurrenceSkipped || value == kOccurrenceCancelled;
}

bool is_terminal_occurrence_status(std::string_view value) {
  return value == kOccurrenceCompleted || value == kOccurrenceSkipped ||
         value == kOccurrenceCancelled;
}

}  // namespace excellent_calendar::domain

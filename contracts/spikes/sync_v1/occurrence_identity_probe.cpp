// Links the unchanged Core recurrence/TZDB implementation. No product writer.
#include <filesystem>
#include <iostream>
#include <limits>
#include <stdexcept>
#include <picojson/picojson.h>
#include "excellent_calendar/application/recurrence_service.hpp"
#include "excellent_calendar/common/datetime.hpp"
#include "excellent_calendar/common/uuid.hpp"
#include "excellent_calendar/infrastructure/time/tzdb_local_time_resolver.hpp"

using excellent_calendar::application::RecurrenceService;
using excellent_calendar::domain::RecurringEventSchedule;
using excellent_calendar::domain::EventOccurrence;
using excellent_calendar::infrastructure::time::TzdbLocalTimeResolver;
void require(bool value) { if(!value) throw std::invalid_argument("IMPORT_REFERENCE_INVALID"); }
const picojson::value& get(const picojson::object& value,const std::string& key) { auto found=value.find(key); require(found!=value.end()); return found->second; }
std::string text(const picojson::object& value,const std::string& key) { const auto& v=get(value,key); require(v.is<std::string>()); return v.get<std::string>(); }
int number(const picojson::object& value,const std::string& key,int minimum) {
    const auto& v=get(value,key); require(v.is<double>()); double n=v.get<double>();
    require(n>=minimum && n<=std::numeric_limits<int>::max() && n==std::floor(n)); return static_cast<int>(n);
}
std::optional<std::string> optional(const picojson::object& value,const std::string& key) {
    const auto& v=get(value,key); if(v.is<picojson::null>()) return std::nullopt;
    require(v.is<std::string>()); return v.get<std::string>();
}
std::string remapped_key(const std::string& event,int revision,const std::string& local) {
    picojson::array name{picojson::value(event),picojson::value(static_cast<double>(revision)),picojson::value(local)};
    auto key=excellent_calendar::common::generate_uuid_v5("2fa8ebd0-958e-5eae-83d1-1aa5da893415",picojson::value(name).serialize());
    require(key.ok()); return key.value();
}

int main(int argc,char** argv) {
    if(argc!=2) return 2;
    auto loaded=TzdbLocalTimeResolver::create(std::filesystem::path(argv[1]));
    if(!loaded.ok() || loaded.value()->tzdb_version()!="2026c") return 3;
    RecurrenceService service(loaded.value());
    std::string line;
    while(std::getline(std::cin,line)) {
        try {
            picojson::value parsed; require(picojson::parse(parsed,line).empty() && parsed.is<picojson::object>());
            const auto& input=parsed.get<picojson::object>(); require(input.size()==12);
            const auto& allDay=get(input,"is_all_day"); require(allDay.is<bool>());
            RecurringEventSchedule schedule{text(input,"source_event_id"),optional(input,"start_at"),optional(input,"end_at"),
                optional(input,"start_date"),optional(input,"end_date"),allDay.get<bool>(),text(input,"timezone")};
            const int revision=number(input,"revision",1),index=number(input,"index",0);
            auto recurrence=service.derive_recurrence(schedule,{text(input,"frequency"),1,std::nullopt,std::nullopt},
                "33333333-3333-4333-8333-333333333333",revision,"2026-01-01T00:00:00Z");
            require(recurrence.ok()); auto derived=service.occurrence_at(schedule,recurrence.value(),index); require(derived.ok());
            EventOccurrence stored=derived.value();
            const auto& overrideValue=get(input,"stored_override");
            if(!overrideValue.is<picojson::null>()) {
                require(overrideValue.is<picojson::object>()); const auto& override=overrideValue.get<picojson::object>();
                for(const auto& pair:override) {
                    require(pair.second.is<std::string>());
                    if(pair.first=="occurrence_key") stored.occurrence_key=pair.second.get<std::string>();
                    else if(pair.first=="occurrence_start_at") stored.occurrence_start_at=pair.second.get<std::string>();
                    else throw std::invalid_argument("IMPORT_REFERENCE_INVALID");
                }
            }
            std::vector<EventOccurrence> candidates;
            std::string convertedWall;
            if(schedule.is_all_day) {
                using namespace excellent_calendar::domain;
                auto date=parse_local_date(*stored.occurrence_start_date); require(date.ok());
                auto listed=service.list_all_day_occurrences(schedule,recurrence.value(),format_local_date(add_local_days(date.value(),-2)),
                    format_local_date(add_local_days(date.value(),1)),200);
                require(listed.ok()); candidates=listed.value(); convertedWall=*stored.occurrence_start_date;
            } else {
                using namespace excellent_calendar::common;
                auto time=parse_iso8601_utc_epoch_seconds(*stored.occurrence_start_at); require(time.has_value());
                // Include transition overlap before the exact instant: a skipped
                // civil day may produce two keys at the same UTC instant. The
                // immutable source key, never UTC alone, selects the candidate.
                auto listed=service.list_timed_occurrences(schedule,recurrence.value(),format_epoch_seconds_utc_iso8601(*time-2*86400),
                    format_epoch_seconds_utc_iso8601(*time+1),200);
                require(listed.ok()); candidates=listed.value();
                auto local=loaded.value()->to_local(*stored.occurrence_start_at,schedule.timezone); require(local.ok());
                convertedWall=excellent_calendar::domain::format_local_date_time(local.value());
            }
            std::vector<EventOccurrence> matching; int sameInstant=0;
            for(const auto& candidate:candidates) {
                if(candidate.occurrence_start_at!=stored.occurrence_start_at || candidate.occurrence_start_date!=stored.occurrence_start_date) continue;
                ++sameInstant;
                if(candidate.occurrence_key==stored.occurrence_key) matching.push_back(candidate);
            }
            require(matching.size()==1);
            const auto& occurrence=matching.front();
            picojson::object output;
            output["original_local_start"]=picojson::value(occurrence.original_local_start);
            output["source_occurrence_key"]=picojson::value(occurrence.occurrence_key);
            output["target_occurrence_key"]=picojson::value(remapped_key(text(input,"target_event_id"),revision,occurrence.original_local_start));
            output["utc_reconverted_wall"]=picojson::value(convertedWall);
            output["same_instant_candidates"]=picojson::value(static_cast<double>(sameInstant));
            output["occurrence_start_at"]=occurrence.occurrence_start_at?picojson::value(*occurrence.occurrence_start_at):picojson::value();
            output["occurrence_start_date"]=occurrence.occurrence_start_date?picojson::value(*occurrence.occurrence_start_date):picojson::value();
            std::cout<<picojson::value(output).serialize()<<'\n';
        } catch(const std::exception&) { std::cout<<"REJECT\n"; }
    }
}

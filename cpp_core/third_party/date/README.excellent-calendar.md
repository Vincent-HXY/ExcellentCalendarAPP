# Vendored `date` timezone library

- Upstream: `https://github.com/HowardHinnant/date`
- Release: `v3.0.4`
- Commit: `f94b8f36c6180be0021876c4a397a054fe50c6f2`
- License: MIT (`LICENSE.txt`)

Only `date.h`, `tz.h`, `tz_private.h`, and `tz.cpp` are vendored because the
calendar core uses the C++17 timezone library and supplies its own pinned IANA
database.

Excellent Calendar builds with `AUTO_DOWNLOAD=0`, `HAS_REMOTE_API=0`, and
`USE_OS_TZDB=0`. On Windows it also defines
`DATE_DISABLE_WINDOWS_ZONE_MAPPING`: the application accepts only IANA IDs and
does not translate Windows timezone names, so loading CLDR `windowsZones.xml`
would add an unrelated, otherwise runtime-downloaded data source. The guarded
`tz.cpp` change is the only modification to upstream source.

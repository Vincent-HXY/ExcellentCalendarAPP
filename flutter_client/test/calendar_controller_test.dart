import 'dart:async';

import 'package:excellent_calendar/application/calendar/calendar_controller.dart';
import 'package:excellent_calendar/application/calendar/calendar_date_math.dart';
import 'package:excellent_calendar/application/calendar/calendar_models.dart';
import 'package:excellent_calendar/gateway_interfaces/calendar_gateway.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_contract_enums.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_request_dtos.dart';
import 'package:excellent_calendar/native_contract/calendar/calendar_response_dtos.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/calendar_test_support.dart';

void main() {
  group('CalendarController snapshot orchestration', () {
    test('commits range plus three first pages atomically', () async {
      final pageCompleters = {
        for (final section in CalendarSection.values)
          section: Completer<CalendarDayItemPageDto>(),
      };
      final gateway = CallbackCalendarGateway(
        onPage: (request) => pageCompleters[request.section]!.future,
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);

      final initializing = controller.initialize();
      await _flush();
      expect(gateway.pageRequests, hasLength(3));
      expect(controller.state.rangePhase, CalendarRangePhase.loading);
      expect(controller.state.snapshotToken, isNull);

      pageCompleters[CalendarSection.event]!.complete(
        calendarPageResponse(request: gateway.pageRequests[0]),
      );
      await _flush();
      expect(controller.state.snapshotToken, isNull);
      expect(controller.state.eventSection.items, isEmpty);

      pageCompleters[CalendarSection.habit]!.complete(
        calendarPageResponse(request: gateway.pageRequests[1]),
      );
      await _flush();
      expect(controller.state.snapshotToken, isNull);

      pageCompleters[CalendarSection.anniversary]!.complete(
        calendarPageResponse(request: gateway.pageRequests[2]),
      );
      await initializing;

      expect(controller.state.rangePhase, CalendarRangePhase.ready);
      expect(controller.state.snapshotToken, calendarSnapshotA);
      expect(controller.state.eventSection.items, hasLength(1));
      expect(controller.state.habitSection.items, hasLength(1));
      expect(controller.state.anniversarySection.items, hasLength(1));
    });

    test('A to B to C navigation discards every stale response', () async {
      final deferredRanges = <Completer<CalendarRangeSummaryResponseDto>>[];
      final deferredRequests = <CalendarRangeSummaryRequestDto>[];
      var rangeCall = 0;
      final gateway = CallbackCalendarGateway(
        onRange: (request) {
          rangeCall += 1;
          if (rangeCall == 1) {
            return Future.value(calendarRangeResponse(request: request));
          }
          deferredRequests.add(request);
          final completer = Completer<CalendarRangeSummaryResponseDto>();
          deferredRanges.add(completer);
          return completer.future;
        },
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      final toB = controller.navigatePeriod(1);
      final toC = controller.navigatePeriod(1);
      await _flush();
      expect(deferredRanges, hasLength(2));

      deferredRanges[1].complete(
        calendarRangeResponse(
          request: deferredRequests[1],
          snapshotToken: calendarSnapshotC,
        ),
      );
      await toC;
      expect(
        CalendarDateMath.formatDate(controller.state.selectedDate),
        '2026-09-14',
      );
      expect(controller.state.snapshotToken, calendarSnapshotC);

      deferredRanges[0].complete(
        calendarRangeResponse(
          request: deferredRequests[0],
          snapshotToken: calendarSnapshotB,
        ),
      );
      await toB;
      expect(
        CalendarDateMath.formatDate(controller.state.selectedDate),
        '2026-09-14',
      );
      expect(controller.state.snapshotToken, calendarSnapshotC);
      expect(
        gateway.pageRequests.where(
          (request) => request.snapshotToken == calendarSnapshotB,
        ),
        isEmpty,
      );
    });

    test(
      'cached day is immediate and always revalidated in background',
      () async {
        final revalidation = {
          for (final section in CalendarSection.values)
            section: Completer<CalendarDayItemPageDto>(),
        };
        var originalDateCalls = 0;
        final gateway = CallbackCalendarGateway(
          onPage: (request) {
            if (request.date == '2026-08-31') {
              originalDateCalls += 1;
              if (originalDateCalls > 3) {
                return revalidation[request.section]!.future;
              }
            }
            return Future.value(calendarPageResponse(request: request));
          },
        );
        final controller = _controller(gateway);
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.selectDate(DateTime.utc(2026, 9, 1));

        final back = controller.selectDate(DateTime.utc(2026, 8, 31));
        await _flush();
        expect(controller.state.showingCachedSnapshot, isTrue);
        expect(controller.state.rangePhase, CalendarRangePhase.refreshing);
        expect(
          controller.state.eventSection.items.single.identityKey,
          contains('1'),
        );
        expect(originalDateCalls, 6);

        for (final request in gateway.pageRequests.skip(
          gateway.pageRequests.length - 3,
        )) {
          revalidation[request.section]!.complete(
            calendarPageResponse(
              request: request,
              items: calendarItemsFor(request.section, request.date, start: 9),
            ),
          );
        }
        await back;
        expect(controller.state.showingCachedSnapshot, isFalse);
        expect(controller.state.rangePhase, CalendarRangePhase.ready);
        expect(
          controller.state.eventSection.items.single.identityKey,
          contains('9'),
        );
      },
    );

    test(
      'expired cached token is cleared before one full snapshot refresh',
      () async {
        final secondRange = Completer<CalendarRangeSummaryResponseDto>();
        CalendarRangeSummaryRequestDto? secondRangeRequest;
        var rangeCalls = 0;
        var originalDateCalls = 0;
        final gateway = CallbackCalendarGateway(
          onRange: (request) {
            rangeCalls += 1;
            if (rangeCalls == 1) {
              return Future.value(calendarRangeResponse(request: request));
            }
            secondRangeRequest = request;
            return secondRange.future;
          },
          onPage: (request) {
            if (request.date == '2026-08-31') {
              originalDateCalls += 1;
              if (originalDateCalls > 3 &&
                  request.snapshotToken == calendarSnapshotA) {
                throw const CalendarGatewayFailure(
                  code: 'CALENDAR_SNAPSHOT_EXPIRED',
                  message: 'expired',
                  retryable: true,
                );
              }
            }
            return Future.value(calendarPageResponse(request: request));
          },
        );
        final controller = _controller(gateway);
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.selectDate(DateTime.utc(2026, 9, 1));

        final back = controller.selectDate(DateTime.utc(2026, 8, 31));
        await _flush();
        expect(rangeCalls, 2);
        expect(controller.state.snapshotToken, isNull);
        expect(controller.state.eventSection.hasMore, isFalse);

        secondRange.complete(
          calendarRangeResponse(
            request: secondRangeRequest!,
            snapshotToken: calendarSnapshotB,
          ),
        );
        await back;
        expect(controller.state.snapshotToken, calendarSnapshotB);
        expect(controller.state.rangePhase, CalendarRangePhase.ready);
      },
    );

    test(
      'initial snapshot expiry retries the complete four-call unit once',
      () async {
        var rangeCalls = 0;
        var expired = false;
        final gateway = CallbackCalendarGateway(
          onRange: (request) async {
            rangeCalls += 1;
            return calendarRangeResponse(
              request: request,
              snapshotToken: rangeCalls == 1
                  ? calendarSnapshotA
                  : calendarSnapshotB,
            );
          },
          onPage: (request) async {
            if (!expired && request.section == CalendarSection.event) {
              expired = true;
              throw const CalendarGatewayFailure(
                code: 'CALENDAR_SNAPSHOT_EXPIRED',
                message: 'expired',
                retryable: true,
              );
            }
            return calendarPageResponse(request: request);
          },
        );
        final controller = _controller(gateway);
        addTearDown(controller.dispose);

        await controller.initialize();

        expect(rangeCalls, 2);
        expect(controller.state.snapshotToken, calendarSnapshotB);
        expect(controller.state.rangePhase, CalendarRangePhase.ready);
      },
    );

    test(
      'route cancellation settles interrupted load-more and permits retry',
      () async {
        final firstLoadMore = Completer<CalendarDayItemPageDto>();
        final retryLoadMore = Completer<CalendarDayItemPageDto>();
        var loadMoreCalls = 0;
        final gateway = CallbackCalendarGateway(
          onPage: (request) {
            if (request.section == CalendarSection.event &&
                request.cursor != null) {
              loadMoreCalls += 1;
              return loadMoreCalls == 1
                  ? firstLoadMore.future
                  : retryLoadMore.future;
            }
            return Future.value(
              calendarPageResponse(
                request: request,
                hasMore: request.section == CalendarSection.event,
                nextCursor: request.section == CalendarSection.event
                    ? calendarCursorA
                    : null,
              ),
            );
          },
        );
        final controller = _controller(gateway);
        addTearDown(controller.dispose);
        await controller.initialize();

        final interrupted = controller.loadMore(CalendarSection.event);
        await _flush();
        expect(
          controller.state.eventSection.phase,
          CalendarSectionPhase.loadingMore,
        );
        controller.beginRouteTransition();
        await controller.handleRouteResult(false);
        expect(controller.state.rangePhase, CalendarRangePhase.ready);
        expect(controller.state.eventSection.phase, CalendarSectionPhase.ready);

        final retried = controller.loadMore(CalendarSection.event);
        await _flush();
        expect(loadMoreCalls, 2);
        final requests = gateway.pageRequests
            .where(
              (request) =>
                  request.section == CalendarSection.event &&
                  request.cursor != null,
            )
            .toList();
        firstLoadMore.complete(
          calendarPageResponse(
            request: requests[0],
            items: calendarItemsFor(
              CalendarSection.event,
              requests[0].date,
              start: 2,
            ),
          ),
        );
        await interrupted;
        expect(controller.state.eventSection.items, hasLength(1));

        retryLoadMore.complete(
          calendarPageResponse(
            request: requests[1],
            items: calendarItemsFor(
              CalendarSection.event,
              requests[1].date,
              start: 2,
            ),
          ),
        );
        await retried;
        expect(controller.state.eventSection.items, hasLength(2));
        expect(controller.state.eventSection.phase, CalendarSectionPhase.ready);
      },
    );

    test(
      'route cancellation settles and rejects cached background refresh',
      () async {
        final background = {
          for (final section in CalendarSection.values)
            section: Completer<CalendarDayItemPageDto>(),
        };
        var originalDateCalls = 0;
        final gateway = CallbackCalendarGateway(
          onPage: (request) {
            if (request.date == '2026-08-31') {
              originalDateCalls += 1;
              if (originalDateCalls > 3) {
                return background[request.section]!.future;
              }
            }
            return Future.value(calendarPageResponse(request: request));
          },
        );
        final controller = _controller(gateway);
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.selectDate(DateTime.utc(2026, 9, 1));

        final refreshing = controller.selectDate(DateTime.utc(2026, 8, 31));
        await _flush();
        expect(controller.state.rangePhase, CalendarRangePhase.refreshing);
        controller.beginRouteTransition();
        await controller.handleRouteResult(false);
        expect(controller.state.rangePhase, CalendarRangePhase.ready);
        for (final section in CalendarSection.values) {
          expect(
            controller.state.section(section).phase,
            CalendarSectionPhase.ready,
          );
        }

        final requests = gateway.pageRequests.skip(
          gateway.pageRequests.length - 3,
        );
        for (final request in requests) {
          background[request.section]!.complete(
            calendarPageResponse(
              request: request,
              items: calendarItemsFor(request.section, request.date, start: 9),
            ),
          );
        }
        await refreshing;
        expect(
          controller.state.eventSection.items.single.identityKey,
          contains('1'),
        );
        expect(controller.state.rangePhase, CalendarRangePhase.ready);
      },
    );
  });

  group('CalendarController temporal invalidation and pagination', () {
    test(
      'activation reconciles an inactive midnight before one reload',
      () async {
        var now = DateTime(2026, 8, 31, 23, 59);
        var rangeCalls = 0;
        final activationRange = Completer<CalendarRangeSummaryResponseDto>();
        CalendarRangeSummaryRequestDto? activationRequest;
        final gateway = CallbackCalendarGateway(
          onRange: (request) {
            rangeCalls += 1;
            if (rangeCalls == 1) {
              return Future.value(calendarRangeResponse(request: request));
            }
            activationRequest = request;
            return activationRange.future;
          },
        );
        final controller = CalendarController(
          gateway: gateway,
          timezoneProvider: () async => calendarTimezone,
          nowProvider: () => now,
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.setActive(false);

        now = DateTime(2026, 9, 1, 0, 1);
        await controller.handleMidnight();
        expect(controller.state.today, DateTime.utc(2026, 8, 31));
        expect(rangeCalls, 1);

        final activation = controller.setActive(true);
        final duplicateActivation = controller.setActive(true);
        await _flush();
        expect(controller.state.today, DateTime.utc(2026, 9, 1));
        expect(controller.state.snapshotToken, isNull);
        expect(rangeCalls, 2);

        activationRange.complete(
          calendarRangeResponse(
            request: activationRequest!,
            snapshotToken: calendarSnapshotB,
          ),
        );
        await Future.wait([activation, duplicateActivation]);
        expect(controller.state.snapshotToken, calendarSnapshotB);
        expect(rangeCalls, 2);
      },
    );

    test(
      'activation reconciles a timezone changed while inactive once',
      () async {
        var timezone = calendarTimezone;
        var rangeCalls = 0;
        final activationRange = Completer<CalendarRangeSummaryResponseDto>();
        CalendarRangeSummaryRequestDto? activationRequest;
        final gateway = CallbackCalendarGateway(
          onRange: (request) {
            rangeCalls += 1;
            if (rangeCalls == 1) {
              return Future.value(calendarRangeResponse(request: request));
            }
            activationRequest = request;
            return activationRange.future;
          },
        );
        final controller = CalendarController(
          gateway: gateway,
          timezoneProvider: () async => timezone,
          nowProvider: () => DateTime(2026, 8, 31, 9),
        );
        addTearDown(controller.dispose);
        await controller.initialize();
        await controller.setActive(false);

        timezone = 'Europe/Paris';
        final activation = controller.setActive(true);
        await _flush();
        expect(controller.state.timezone, 'Europe/Paris');
        expect(controller.state.snapshotToken, isNull);
        expect(activationRequest!.timezone, 'Europe/Paris');
        expect(rangeCalls, 2);

        activationRange.complete(
          calendarRangeResponse(
            request: activationRequest!,
            snapshotToken: calendarSnapshotB,
          ),
        );
        await activation;
        expect(controller.state.snapshotToken, calendarSnapshotB);
        expect(
          gateway.pageRequests
              .skip(3)
              .every((request) => request.timezone == 'Europe/Paris'),
          isTrue,
        );
        expect(rangeCalls, 2);
      },
    );

    test(
      'local midnight invalidates token, all cursors and stale load-more',
      () async {
        var now = DateTime(2026, 8, 31, 23, 59);
        var rangeCalls = 0;
        final midnightRange = Completer<CalendarRangeSummaryResponseDto>();
        CalendarRangeSummaryRequestDto? midnightRequest;
        final oldLoadMore = Completer<CalendarDayItemPageDto>();
        final gateway = CallbackCalendarGateway(
          onRange: (request) {
            rangeCalls += 1;
            if (rangeCalls == 1) {
              return Future.value(calendarRangeResponse(request: request));
            }
            midnightRequest = request;
            return midnightRange.future;
          },
          onPage: (request) {
            if (request.cursor != null) return oldLoadMore.future;
            return Future.value(
              calendarPageResponse(
                request: request,
                items: calendarItemsFor(request.section, request.date),
                hasMore: request.section == CalendarSection.event,
                nextCursor: request.section == CalendarSection.event
                    ? calendarCursorA
                    : null,
              ),
            );
          },
        );
        final controller = CalendarController(
          gateway: gateway,
          timezoneProvider: () async => calendarTimezone,
          nowProvider: () => now,
        );
        addTearDown(controller.dispose);
        await controller.initialize();

        final loadingMore = controller.loadMore(CalendarSection.event);
        await _flush();
        now = DateTime(2026, 9, 1, 0, 1);
        final midnight = controller.handleMidnight();
        await _flush();

        expect(controller.state.today, DateTime.utc(2026, 9, 1));
        expect(controller.state.snapshotToken, isNull);
        for (final section in CalendarSection.values) {
          expect(controller.state.section(section).hasMore, isFalse);
          expect(controller.state.section(section).nextCursor, isNull);
        }

        final staleRequest = gateway.pageRequests.singleWhere(
          (request) => request.cursor != null,
        );
        oldLoadMore.complete(
          calendarPageResponse(
            request: staleRequest,
            items: calendarItemsFor(
              CalendarSection.event,
              staleRequest.date,
              start: 2,
            ),
          ),
        );
        await loadingMore;
        expect(controller.state.eventSection.items, hasLength(1));

        midnightRange.complete(
          calendarRangeResponse(
            request: midnightRequest!,
            snapshotToken: calendarSnapshotB,
          ),
        );
        await midnight;
        expect(controller.state.snapshotToken, calendarSnapshotB);
        expect(rangeCalls, 2);
      },
    );

    test('timezone change clears snapshot and reloads all groups', () async {
      final reloadRange = Completer<CalendarRangeSummaryResponseDto>();
      CalendarRangeSummaryRequestDto? reloadRequest;
      var rangeCalls = 0;
      final gateway = CallbackCalendarGateway(
        onRange: (request) {
          rangeCalls += 1;
          if (rangeCalls == 1) {
            return Future.value(calendarRangeResponse(request: request));
          }
          reloadRequest = request;
          return reloadRange.future;
        },
      );
      final controller = _controller(gateway);
      addTearDown(controller.dispose);
      await controller.initialize();

      final changing = controller.changeTimezone('Europe/Paris');
      await _flush();
      expect(controller.state.timezone, 'Europe/Paris');
      expect(controller.state.snapshotToken, isNull);
      for (final section in CalendarSection.values) {
        expect(controller.state.section(section).nextCursor, isNull);
      }

      reloadRange.complete(
        calendarRangeResponse(
          request: reloadRequest!,
          snapshotToken: calendarSnapshotB,
        ),
      );
      await changing;
      expect(controller.state.snapshotToken, calendarSnapshotB);
      expect(
        gateway.pageRequests
            .skip(3)
            .every((request) => request.timezone == 'Europe/Paris'),
        isTrue,
      );
    });

    for (final section in CalendarSection.values) {
      for (final total in [0, 1, 19, 20, 21, 41, 101]) {
        test(
          '${section.name} pagination is complete for $total items',
          () async {
            final gateway = CallbackCalendarGateway(
              onPage: (request) async {
                if (request.section != section) {
                  return calendarPageResponse(
                    request: request,
                    items: const [],
                  );
                }
                final offset = request.cursor == null
                    ? 0
                    : int.parse(request.cursor!.substring('calcur1.'.length));
                final count = (total - offset).clamp(0, request.pageSize);
                final nextOffset = offset + count;
                final hasMore = nextOffset < total;
                return calendarPageResponse(
                  request: request,
                  items: calendarItemsFor(
                    request.section,
                    request.date,
                    start: offset + 1,
                    count: count,
                  ),
                  hasMore: hasMore,
                  nextCursor: hasMore
                      ? 'calcur1.${nextOffset.toString().padLeft(20, '0')}'
                      : null,
                );
              },
            );
            final controller = _controller(gateway);
            addTearDown(controller.dispose);
            await controller.initialize();

            while (controller.state.section(section).hasMore) {
              await controller.loadMore(section);
            }

            expect(controller.state.section(section).items, hasLength(total));
            expect(
              controller.state
                  .section(section)
                  .items
                  .map((item) => item.identityKey)
                  .toSet(),
              hasLength(total),
            );
            expect(
              gateway.pageRequests
                  .where((request) => request.section == section)
                  .every(
                    (request) =>
                        request.pageSize == CalendarController.pageSize,
                  ),
              isTrue,
            );
          },
        );
      }

      test('${section.name} duplicate identity is a scoped error', () async {
        final gateway = CallbackCalendarGateway(
          onPage: (request) async {
            if (request.section != section) {
              return calendarPageResponse(request: request, items: const []);
            }
            return calendarPageResponse(
              request: request,
              items: calendarItemsFor(section, request.date),
              hasMore: request.cursor == null,
              nextCursor: request.cursor == null ? calendarCursorA : null,
            );
          },
        );
        final controller = _controller(gateway);
        addTearDown(controller.dispose);
        await controller.initialize();

        await controller.loadMore(section);

        expect(
          controller.state.section(section).phase,
          CalendarSectionPhase.error,
        );
        expect(controller.state.section(section).items, hasLength(1));
        for (final other in CalendarSection.values.where(
          (value) => value != section,
        )) {
          expect(
            controller.state.section(other).phase,
            CalendarSectionPhase.ready,
          );
        }
      });
    }
  });
}

CalendarController _controller(CallbackCalendarGateway gateway) =>
    CalendarController(
      gateway: gateway,
      timezoneProvider: () async => calendarTimezone,
      nowProvider: () => DateTime(2026, 8, 31, 9),
    );

Future<void> _flush() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

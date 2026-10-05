import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/daily_step.dart';
import 'package:app/features/footsteps/data/footsteps_api.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:app/features/footsteps/data/footsteps_sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedCountryResolver implements CountryResolver {
  @override
  Future<String> resolveIso2(double lat, double lng) async => 'JP';
}

class _FakeFootstepsApi implements FootstepsApi {
  int nextServerId = 1;
  List<Checkin> pushedCheckins = [];
  List<DailyStep> pushedDailySteps = [];

  @override
  Future<Map<int, String>> pushCheckins(List<Checkin> items) async {
    pushedCheckins = items;
    return {for (final c in items) c.id: 'server-checkin-${nextServerId++}'};
  }

  @override
  Future<Map<int, String>> pushDailySteps(List<DailyStep> items) async {
    pushedDailySteps = items;
    return {for (final d in items) d.id: 'server-daily-${nextServerId++}'};
  }
}

void main() {
  late AppDatabase db;
  late FootstepsRepository repo;
  late _FakeFootstepsApi api;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    repo = FootstepsRepository(db: db, countryResolver: _FixedCountryResolver());
    api = _FakeFootstepsApi();
  });

  tearDown(() => db.close());

  test('미동기화 체크인과 걸음수를 배치로 보내고 동기화 표시한다', () async {
    await repo.recordCheckinAt(35.6, 139.7, DateTime.utc(2026, 12, 20, 9), CheckinSource.auto);
    await repo.upsertDailySteps(DateTime.utc(2026, 12, 20), 'JP', 5000);

    await syncFootsteps(repository: repo, api: api);

    expect(api.pushedCheckins, hasLength(1));
    expect(api.pushedDailySteps, hasLength(1));
    expect(await repo.unsyncedCheckins(), isEmpty);
    expect(await repo.unsyncedDailySteps(), isEmpty);
  });

  test('보낼 것이 없으면 API를 호출하지 않는다', () async {
    await syncFootsteps(repository: repo, api: api);

    expect(api.pushedCheckins, isEmpty);
    expect(api.pushedDailySteps, isEmpty);
  });
}

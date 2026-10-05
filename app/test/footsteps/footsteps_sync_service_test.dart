import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/daily_step.dart';
import 'package:app/features/footsteps/data/footsteps_api.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:app/features/footsteps/data/footsteps_sync_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// 남위(lat < 0)는 판정 실패를 흉내내 'XX'를 돌려준다 — 서버가 모르는 국가 코드다.
class _LatBasedCountryResolver implements CountryResolver {
  @override
  Future<String> resolveIso2(double lat, double lng) async => lat < 0 ? 'XX' : 'JP';
}

class _FakeFootstepsApi implements FootstepsApi {
  int nextServerId = 1;
  List<Checkin> pushedCheckins = [];
  List<DailyStep> pushedDailySteps = [];

  /// 서버가 모르는 국가 코드가 하나라도 섞이면 배치 전체를 400으로 거부한다.
  Set<String> rejectedCountries = {};
  int pushCheckinCalls = 0;

  @override
  Future<Map<int, String>> pushCheckins(List<Checkin> items) async {
    pushCheckinCalls++;
    if (items.any((c) => rejectedCountries.contains(c.countryIso))) {
      throw Exception('400 Bad Request: unknown country');
    }
    pushedCheckins = [...pushedCheckins, ...items];
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
    repo = FootstepsRepository(db: db, countryResolver: _LatBasedCountryResolver());
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

  test('서버가 모르는 국가가 섞여 배치가 거부되면 정상 체크인만 하나씩 동기화한다', () async {
    // 'XX' 한 줄이 배치를 400으로 만들면, 그 뒤 모든 체크인이 영구히 미동기화로 남았다.
    await repo.recordCheckinAt(35.6, 139.7, DateTime.utc(2026, 12, 20, 9), CheckinSource.auto);
    await repo.recordCheckinAt(-80.0, 0.0, DateTime.utc(2026, 12, 20, 10), CheckinSource.auto);
    await repo.recordCheckinAt(35.7, 139.8, DateTime.utc(2026, 12, 20, 11), CheckinSource.auto);
    api.rejectedCountries = {'XX'};

    await syncFootsteps(repository: repo, api: api);

    // 정상 2건은 통과하고, 거부되는 1건만 남는다.
    expect(api.pushedCheckins.map((c) => c.countryIso), ['JP', 'JP']);
    final remaining = await repo.unsyncedCheckins();
    expect(remaining, hasLength(1));
    expect(remaining.single.countryIso, 'XX');
  });

  test('체크인 배치가 거부돼도 걸음수 동기화는 진행된다', () async {
    await repo.recordCheckinAt(-80.0, 0.0, DateTime.utc(2026, 12, 20, 10), CheckinSource.auto);
    await repo.upsertDailySteps(DateTime.utc(2026, 12, 20), 'JP', 5000);
    api.rejectedCountries = {'XX'};

    await syncFootsteps(repository: repo, api: api);

    expect(await repo.unsyncedDailySteps(), isEmpty);
  });
}

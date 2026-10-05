import 'package:app/core/db/app_database.dart';
import 'package:app/features/footsteps/data/checkin.dart';
import 'package:app/features/footsteps/data/country_resolver.dart';
import 'package:app/features/footsteps/data/footsteps_repository.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class _FixedCountryResolver implements CountryResolver {
  _FixedCountryResolver(this.iso);
  final String iso;

  @override
  Future<String> resolveIso2(double lat, double lng) async => iso;
}

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('좌표를 주면 국가를 판정해 저장한다', () async {
    final repo = FootstepsRepository(db: db, countryResolver: _FixedCountryResolver('VN'));

    await repo.recordCheckinAt(21.0, 105.8, DateTime.utc(2026, 12, 21, 10), CheckinSource.manual);

    final all = await repo.allCheckins();
    expect(all, hasLength(1));
    expect(all.first.countryIso, 'VN');
    expect(all.first.source, CheckinSource.manual);
  });

  test('국가별 조회와 누적 걸음수 집계를 그대로 위임한다', () async {
    final repo = FootstepsRepository(db: db, countryResolver: _FixedCountryResolver('JP'));
    await repo.recordCheckinAt(35.6, 139.7, DateTime.utc(2026, 12, 20, 9), CheckinSource.auto);

    final jp = await repo.checkinsForCountry('JP');
    expect(jp, hasLength(1));

    await db.upsertDailySteps(DateTime.utc(2026, 12, 20), 'JP', 4000);
    final totals = await repo.cumulativeStepsByCountry();
    expect(totals['JP'], 4000);
  });
}

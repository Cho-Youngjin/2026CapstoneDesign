import 'package:health/health.dart';

import '../data/footsteps_repository.dart';
import 'step_attribution.dart';

class HealthStepsService {
  HealthStepsService() : _health = Health();

  final Health _health;
  bool _configured = false;

  static const _types = [HealthDataType.STEPS];

  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await _health.configure();
    _configured = true;
  }

  Future<bool> requestAuthorization() async {
    await _ensureConfigured();
    final granted = await _health.hasPermissions(_types) ?? false;
    if (granted) return true;
    return _health.requestAuthorization(_types);
  }

  /// [date]의 자정부터 다음날 자정까지 걸음 수를 합산한다. 권한이 없거나
  /// 데이터가 없으면 null.
  Future<int?> stepsOn(DateTime date) async {
    await _ensureConfigured();
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    return _health.getTotalStepsInInterval(start, end);
  }
}

/// [date]의 걸음 수를 읽어, 그날 가장 많이 체크인된 국가에 귀속시켜 로컬 DB에 저장한다.
/// 걸음 데이터가 없거나(steps == null) 그날 체크인이 하나도 없어 귀속시킬 국가를
/// 못 찾으면(country == null) 아무것도 하지 않는다.
Future<void> syncStepsToDatabase({
  required HealthStepsService health,
  required FootstepsRepository repository,
  required DateTime date,
}) async {
  final steps = await health.stepsOn(date);
  if (steps == null) return;

  final allCheckins = await repository.allCheckins();
  final country = attributeCountryForDate(date, allCheckins);
  if (country == null) return;

  await repository.upsertDailySteps(date, country, steps);
}

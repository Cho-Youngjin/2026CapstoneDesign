import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'wallet_database.g.dart';

/// 지출 기록. 금액은 현지 통화 최소단위 정수(엔은 1엔, 달러는 1센트).
@DataClassName('ExpenseRow')
class Expenses extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get isoAlpha2 => text()();
  TextColumn get currencyCode => text()();

  /// `ExpenseCategory.code` (FOOD, LODGING, TRANSPORT, SIGHTSEEING, OTHER)
  TextColumn get category => text()();
  IntColumn get amountMinor => integer()();

  /// 기록한 순간의 1단위당 원화. 이미 쓴 돈의 원화 값은 이 값으로 고정한다(설계 §5.3).
  /// 그때 환율을 몰랐으면 null이고, 화면에 "환율 없음"으로 보인다.
  RealColumn get krwPerUnitAtEntry => real().nullable()();
  TextColumn get memo => text().withDefault(const Constant(''))();
  DateTimeColumn get spentOn => dateTime()();
}

/// 환전 기록. [amountMinor]는 받은 현지 통화, [krwPaid]는 그때 낸 원화(선택, 평가손익 계산용).
@DataClassName('ExchangeRow')
class Exchanges extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get isoAlpha2 => text()();
  TextColumn get currencyCode => text()();
  IntColumn get amountMinor => integer()();
  IntColumn get krwPaid => integer().nullable()();
  TextColumn get memo => text().withDefault(const Constant(''))();
  DateTimeColumn get exchangedOn => dateTime()();
}

/// 지갑 전용 로컬 DB(`wallet.sqlite`). 발걸음 기능의 AppDatabase와 파일을 나눠,
/// 서로의 스키마 마이그레이션이 영향을 주지 않게 한다(설계 §5.4). 서버에는 저장하지 않는다.
@DriftDatabase(tables: [Expenses, Exchanges])
class WalletDatabase extends _$WalletDatabase {
  WalletDatabase() : super(_openConnection());

  /// 테스트에서 인메모리 DB를 주입하기 위한 생성자.
  WalletDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;

  Future<int> addExpense({
    required String isoAlpha2,
    required String currencyCode,
    required String category,
    required int amountMinor,
    double? krwPerUnitAtEntry,
    String memo = '',
    required DateTime spentOn,
  }) {
    return into(expenses).insert(ExpensesCompanion.insert(
      isoAlpha2: isoAlpha2,
      currencyCode: currencyCode,
      category: category,
      amountMinor: amountMinor,
      krwPerUnitAtEntry: Value(krwPerUnitAtEntry),
      memo: Value(memo),
      spentOn: spentOn,
    ));
  }

  Future<void> updateExpense(ExpenseRow row) async {
    await update(expenses).replace(row);
  }

  Future<void> deleteExpense(int id) async {
    await (delete(expenses)..where((e) => e.id.equals(id))).go();
  }

  Future<int> addExchange({
    required String isoAlpha2,
    required String currencyCode,
    required int amountMinor,
    int? krwPaid,
    String memo = '',
    required DateTime exchangedOn,
  }) {
    return into(exchanges).insert(ExchangesCompanion.insert(
      isoAlpha2: isoAlpha2,
      currencyCode: currencyCode,
      amountMinor: amountMinor,
      krwPaid: Value(krwPaid),
      memo: Value(memo),
      exchangedOn: exchangedOn,
    ));
  }

  Future<void> updateExchange(ExchangeRow row) async {
    await update(exchanges).replace(row);
  }

  Future<void> deleteExchange(int id) async {
    await (delete(exchanges)..where((x) => x.id.equals(id))).go();
  }

  /// 한 나라의 지출. 최근 날짜 먼저, 같은 날은 나중에 넣은 것 먼저.
  Stream<List<ExpenseRow>> watchExpenses(String isoAlpha2) {
    return (select(expenses)
          ..where((e) => e.isoAlpha2.equals(isoAlpha2))
          ..orderBy([(e) => OrderingTerm.desc(e.spentOn), (e) => OrderingTerm.desc(e.id)]))
        .watch();
  }

  /// 한 나라의 환전. 정렬 규칙은 [watchExpenses]와 같다.
  Stream<List<ExchangeRow>> watchExchanges(String isoAlpha2) {
    return (select(exchanges)
          ..where((x) => x.isoAlpha2.equals(isoAlpha2))
          ..orderBy([(x) => OrderingTerm.desc(x.exchangedOn), (x) => OrderingTerm.desc(x.id)]))
        .watch();
  }

  /// 이 나라의 지갑 기록(지출·환전)을 모두 지운다. 다른 나라 기록은 그대로 둔다.
  Future<void> clearWallet(String isoAlpha2) {
    return transaction(() async {
      await (delete(expenses)..where((e) => e.isoAlpha2.equals(isoAlpha2))).go();
      await (delete(exchanges)..where((x) => x.isoAlpha2.equals(isoAlpha2))).go();
    });
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final dbFolder = await getApplicationDocumentsDirectory();
    return NativeDatabase.createInBackground(File(p.join(dbFolder.path, 'wallet.sqlite')));
  });
}

final walletDatabaseProvider = Provider<WalletDatabase>((ref) {
  final db = WalletDatabase();
  ref.onDispose(db.close);
  return db;
});

/// 나라(isoAlpha2)별 지출 목록. DB가 바뀌면 자동으로 다시 내보낸다.
final walletExpensesProvider =
    StreamProvider.family<List<ExpenseRow>, String>((ref, isoAlpha2) {
  return ref.watch(walletDatabaseProvider).watchExpenses(isoAlpha2);
});

/// 나라(isoAlpha2)별 환전 목록.
final walletExchangesProvider =
    StreamProvider.family<List<ExchangeRow>, String>((ref, isoAlpha2) {
  return ref.watch(walletDatabaseProvider).watchExchanges(isoAlpha2);
});

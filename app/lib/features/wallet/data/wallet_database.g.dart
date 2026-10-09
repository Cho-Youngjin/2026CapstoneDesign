// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'wallet_database.dart';

// ignore_for_file: type=lint
class $ExpensesTable extends Expenses
    with TableInfo<$ExpensesTable, ExpenseRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExpensesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _isoAlpha2Meta = const VerificationMeta(
    'isoAlpha2',
  );
  @override
  late final GeneratedColumn<String> isoAlpha2 = GeneratedColumn<String>(
    'iso_alpha2',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyCodeMeta = const VerificationMeta(
    'currencyCode',
  );
  @override
  late final GeneratedColumn<String> currencyCode = GeneratedColumn<String>(
    'currency_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _categoryMeta = const VerificationMeta(
    'category',
  );
  @override
  late final GeneratedColumn<String> category = GeneratedColumn<String>(
    'category',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _krwPerUnitAtEntryMeta = const VerificationMeta(
    'krwPerUnitAtEntry',
  );
  @override
  late final GeneratedColumn<double> krwPerUnitAtEntry =
      GeneratedColumn<double>(
        'krw_per_unit_at_entry',
        aliasedName,
        true,
        type: DriftSqlType.double,
        requiredDuringInsert: false,
      );
  static const VerificationMeta _memoMeta = const VerificationMeta('memo');
  @override
  late final GeneratedColumn<String> memo = GeneratedColumn<String>(
    'memo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _spentOnMeta = const VerificationMeta(
    'spentOn',
  );
  @override
  late final GeneratedColumn<DateTime> spentOn = GeneratedColumn<DateTime>(
    'spent_on',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    isoAlpha2,
    currencyCode,
    category,
    amountMinor,
    krwPerUnitAtEntry,
    memo,
    spentOn,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'expenses';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExpenseRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('iso_alpha2')) {
      context.handle(
        _isoAlpha2Meta,
        isoAlpha2.isAcceptableOrUnknown(data['iso_alpha2']!, _isoAlpha2Meta),
      );
    } else if (isInserting) {
      context.missing(_isoAlpha2Meta);
    }
    if (data.containsKey('currency_code')) {
      context.handle(
        _currencyCodeMeta,
        currencyCode.isAcceptableOrUnknown(
          data['currency_code']!,
          _currencyCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currencyCodeMeta);
    }
    if (data.containsKey('category')) {
      context.handle(
        _categoryMeta,
        category.isAcceptableOrUnknown(data['category']!, _categoryMeta),
      );
    } else if (isInserting) {
      context.missing(_categoryMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('krw_per_unit_at_entry')) {
      context.handle(
        _krwPerUnitAtEntryMeta,
        krwPerUnitAtEntry.isAcceptableOrUnknown(
          data['krw_per_unit_at_entry']!,
          _krwPerUnitAtEntryMeta,
        ),
      );
    }
    if (data.containsKey('memo')) {
      context.handle(
        _memoMeta,
        memo.isAcceptableOrUnknown(data['memo']!, _memoMeta),
      );
    }
    if (data.containsKey('spent_on')) {
      context.handle(
        _spentOnMeta,
        spentOn.isAcceptableOrUnknown(data['spent_on']!, _spentOnMeta),
      );
    } else if (isInserting) {
      context.missing(_spentOnMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExpenseRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExpenseRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      isoAlpha2: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}iso_alpha2'],
      )!,
      currencyCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_code'],
      )!,
      category: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}category'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      krwPerUnitAtEntry: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}krw_per_unit_at_entry'],
      ),
      memo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}memo'],
      )!,
      spentOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}spent_on'],
      )!,
    );
  }

  @override
  $ExpensesTable createAlias(String alias) {
    return $ExpensesTable(attachedDatabase, alias);
  }
}

class ExpenseRow extends DataClass implements Insertable<ExpenseRow> {
  final int id;
  final String isoAlpha2;
  final String currencyCode;

  /// `ExpenseCategory.code` (FOOD, LODGING, TRANSPORT, SIGHTSEEING, OTHER)
  final String category;
  final int amountMinor;

  /// 기록한 순간의 1단위당 원화. 이미 쓴 돈의 원화 값은 이 값으로 고정한다(설계 §5.3).
  /// 그때 환율을 몰랐으면 null이고, 화면에 "환율 없음"으로 보인다.
  final double? krwPerUnitAtEntry;
  final String memo;
  final DateTime spentOn;
  const ExpenseRow({
    required this.id,
    required this.isoAlpha2,
    required this.currencyCode,
    required this.category,
    required this.amountMinor,
    this.krwPerUnitAtEntry,
    required this.memo,
    required this.spentOn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['iso_alpha2'] = Variable<String>(isoAlpha2);
    map['currency_code'] = Variable<String>(currencyCode);
    map['category'] = Variable<String>(category);
    map['amount_minor'] = Variable<int>(amountMinor);
    if (!nullToAbsent || krwPerUnitAtEntry != null) {
      map['krw_per_unit_at_entry'] = Variable<double>(krwPerUnitAtEntry);
    }
    map['memo'] = Variable<String>(memo);
    map['spent_on'] = Variable<DateTime>(spentOn);
    return map;
  }

  ExpensesCompanion toCompanion(bool nullToAbsent) {
    return ExpensesCompanion(
      id: Value(id),
      isoAlpha2: Value(isoAlpha2),
      currencyCode: Value(currencyCode),
      category: Value(category),
      amountMinor: Value(amountMinor),
      krwPerUnitAtEntry: krwPerUnitAtEntry == null && nullToAbsent
          ? const Value.absent()
          : Value(krwPerUnitAtEntry),
      memo: Value(memo),
      spentOn: Value(spentOn),
    );
  }

  factory ExpenseRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExpenseRow(
      id: serializer.fromJson<int>(json['id']),
      isoAlpha2: serializer.fromJson<String>(json['isoAlpha2']),
      currencyCode: serializer.fromJson<String>(json['currencyCode']),
      category: serializer.fromJson<String>(json['category']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      krwPerUnitAtEntry: serializer.fromJson<double?>(
        json['krwPerUnitAtEntry'],
      ),
      memo: serializer.fromJson<String>(json['memo']),
      spentOn: serializer.fromJson<DateTime>(json['spentOn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'isoAlpha2': serializer.toJson<String>(isoAlpha2),
      'currencyCode': serializer.toJson<String>(currencyCode),
      'category': serializer.toJson<String>(category),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'krwPerUnitAtEntry': serializer.toJson<double?>(krwPerUnitAtEntry),
      'memo': serializer.toJson<String>(memo),
      'spentOn': serializer.toJson<DateTime>(spentOn),
    };
  }

  ExpenseRow copyWith({
    int? id,
    String? isoAlpha2,
    String? currencyCode,
    String? category,
    int? amountMinor,
    Value<double?> krwPerUnitAtEntry = const Value.absent(),
    String? memo,
    DateTime? spentOn,
  }) => ExpenseRow(
    id: id ?? this.id,
    isoAlpha2: isoAlpha2 ?? this.isoAlpha2,
    currencyCode: currencyCode ?? this.currencyCode,
    category: category ?? this.category,
    amountMinor: amountMinor ?? this.amountMinor,
    krwPerUnitAtEntry: krwPerUnitAtEntry.present
        ? krwPerUnitAtEntry.value
        : this.krwPerUnitAtEntry,
    memo: memo ?? this.memo,
    spentOn: spentOn ?? this.spentOn,
  );
  ExpenseRow copyWithCompanion(ExpensesCompanion data) {
    return ExpenseRow(
      id: data.id.present ? data.id.value : this.id,
      isoAlpha2: data.isoAlpha2.present ? data.isoAlpha2.value : this.isoAlpha2,
      currencyCode: data.currencyCode.present
          ? data.currencyCode.value
          : this.currencyCode,
      category: data.category.present ? data.category.value : this.category,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      krwPerUnitAtEntry: data.krwPerUnitAtEntry.present
          ? data.krwPerUnitAtEntry.value
          : this.krwPerUnitAtEntry,
      memo: data.memo.present ? data.memo.value : this.memo,
      spentOn: data.spentOn.present ? data.spentOn.value : this.spentOn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExpenseRow(')
          ..write('id: $id, ')
          ..write('isoAlpha2: $isoAlpha2, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('category: $category, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('krwPerUnitAtEntry: $krwPerUnitAtEntry, ')
          ..write('memo: $memo, ')
          ..write('spentOn: $spentOn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    isoAlpha2,
    currencyCode,
    category,
    amountMinor,
    krwPerUnitAtEntry,
    memo,
    spentOn,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExpenseRow &&
          other.id == this.id &&
          other.isoAlpha2 == this.isoAlpha2 &&
          other.currencyCode == this.currencyCode &&
          other.category == this.category &&
          other.amountMinor == this.amountMinor &&
          other.krwPerUnitAtEntry == this.krwPerUnitAtEntry &&
          other.memo == this.memo &&
          other.spentOn == this.spentOn);
}

class ExpensesCompanion extends UpdateCompanion<ExpenseRow> {
  final Value<int> id;
  final Value<String> isoAlpha2;
  final Value<String> currencyCode;
  final Value<String> category;
  final Value<int> amountMinor;
  final Value<double?> krwPerUnitAtEntry;
  final Value<String> memo;
  final Value<DateTime> spentOn;
  const ExpensesCompanion({
    this.id = const Value.absent(),
    this.isoAlpha2 = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.category = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.krwPerUnitAtEntry = const Value.absent(),
    this.memo = const Value.absent(),
    this.spentOn = const Value.absent(),
  });
  ExpensesCompanion.insert({
    this.id = const Value.absent(),
    required String isoAlpha2,
    required String currencyCode,
    required String category,
    required int amountMinor,
    this.krwPerUnitAtEntry = const Value.absent(),
    this.memo = const Value.absent(),
    required DateTime spentOn,
  }) : isoAlpha2 = Value(isoAlpha2),
       currencyCode = Value(currencyCode),
       category = Value(category),
       amountMinor = Value(amountMinor),
       spentOn = Value(spentOn);
  static Insertable<ExpenseRow> custom({
    Expression<int>? id,
    Expression<String>? isoAlpha2,
    Expression<String>? currencyCode,
    Expression<String>? category,
    Expression<int>? amountMinor,
    Expression<double>? krwPerUnitAtEntry,
    Expression<String>? memo,
    Expression<DateTime>? spentOn,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (isoAlpha2 != null) 'iso_alpha2': isoAlpha2,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (category != null) 'category': category,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (krwPerUnitAtEntry != null) 'krw_per_unit_at_entry': krwPerUnitAtEntry,
      if (memo != null) 'memo': memo,
      if (spentOn != null) 'spent_on': spentOn,
    });
  }

  ExpensesCompanion copyWith({
    Value<int>? id,
    Value<String>? isoAlpha2,
    Value<String>? currencyCode,
    Value<String>? category,
    Value<int>? amountMinor,
    Value<double?>? krwPerUnitAtEntry,
    Value<String>? memo,
    Value<DateTime>? spentOn,
  }) {
    return ExpensesCompanion(
      id: id ?? this.id,
      isoAlpha2: isoAlpha2 ?? this.isoAlpha2,
      currencyCode: currencyCode ?? this.currencyCode,
      category: category ?? this.category,
      amountMinor: amountMinor ?? this.amountMinor,
      krwPerUnitAtEntry: krwPerUnitAtEntry ?? this.krwPerUnitAtEntry,
      memo: memo ?? this.memo,
      spentOn: spentOn ?? this.spentOn,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (isoAlpha2.present) {
      map['iso_alpha2'] = Variable<String>(isoAlpha2.value);
    }
    if (currencyCode.present) {
      map['currency_code'] = Variable<String>(currencyCode.value);
    }
    if (category.present) {
      map['category'] = Variable<String>(category.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (krwPerUnitAtEntry.present) {
      map['krw_per_unit_at_entry'] = Variable<double>(krwPerUnitAtEntry.value);
    }
    if (memo.present) {
      map['memo'] = Variable<String>(memo.value);
    }
    if (spentOn.present) {
      map['spent_on'] = Variable<DateTime>(spentOn.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExpensesCompanion(')
          ..write('id: $id, ')
          ..write('isoAlpha2: $isoAlpha2, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('category: $category, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('krwPerUnitAtEntry: $krwPerUnitAtEntry, ')
          ..write('memo: $memo, ')
          ..write('spentOn: $spentOn')
          ..write(')'))
        .toString();
  }
}

class $ExchangesTable extends Exchanges
    with TableInfo<$ExchangesTable, ExchangeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ExchangesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _isoAlpha2Meta = const VerificationMeta(
    'isoAlpha2',
  );
  @override
  late final GeneratedColumn<String> isoAlpha2 = GeneratedColumn<String>(
    'iso_alpha2',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _currencyCodeMeta = const VerificationMeta(
    'currencyCode',
  );
  @override
  late final GeneratedColumn<String> currencyCode = GeneratedColumn<String>(
    'currency_code',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _amountMinorMeta = const VerificationMeta(
    'amountMinor',
  );
  @override
  late final GeneratedColumn<int> amountMinor = GeneratedColumn<int>(
    'amount_minor',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _krwPaidMeta = const VerificationMeta(
    'krwPaid',
  );
  @override
  late final GeneratedColumn<int> krwPaid = GeneratedColumn<int>(
    'krw_paid',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _memoMeta = const VerificationMeta('memo');
  @override
  late final GeneratedColumn<String> memo = GeneratedColumn<String>(
    'memo',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _exchangedOnMeta = const VerificationMeta(
    'exchangedOn',
  );
  @override
  late final GeneratedColumn<DateTime> exchangedOn = GeneratedColumn<DateTime>(
    'exchanged_on',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    isoAlpha2,
    currencyCode,
    amountMinor,
    krwPaid,
    memo,
    exchangedOn,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'exchanges';
  @override
  VerificationContext validateIntegrity(
    Insertable<ExchangeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('iso_alpha2')) {
      context.handle(
        _isoAlpha2Meta,
        isoAlpha2.isAcceptableOrUnknown(data['iso_alpha2']!, _isoAlpha2Meta),
      );
    } else if (isInserting) {
      context.missing(_isoAlpha2Meta);
    }
    if (data.containsKey('currency_code')) {
      context.handle(
        _currencyCodeMeta,
        currencyCode.isAcceptableOrUnknown(
          data['currency_code']!,
          _currencyCodeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_currencyCodeMeta);
    }
    if (data.containsKey('amount_minor')) {
      context.handle(
        _amountMinorMeta,
        amountMinor.isAcceptableOrUnknown(
          data['amount_minor']!,
          _amountMinorMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_amountMinorMeta);
    }
    if (data.containsKey('krw_paid')) {
      context.handle(
        _krwPaidMeta,
        krwPaid.isAcceptableOrUnknown(data['krw_paid']!, _krwPaidMeta),
      );
    }
    if (data.containsKey('memo')) {
      context.handle(
        _memoMeta,
        memo.isAcceptableOrUnknown(data['memo']!, _memoMeta),
      );
    }
    if (data.containsKey('exchanged_on')) {
      context.handle(
        _exchangedOnMeta,
        exchangedOn.isAcceptableOrUnknown(
          data['exchanged_on']!,
          _exchangedOnMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exchangedOnMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ExchangeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ExchangeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      isoAlpha2: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}iso_alpha2'],
      )!,
      currencyCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}currency_code'],
      )!,
      amountMinor: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}amount_minor'],
      )!,
      krwPaid: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}krw_paid'],
      ),
      memo: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}memo'],
      )!,
      exchangedOn: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}exchanged_on'],
      )!,
    );
  }

  @override
  $ExchangesTable createAlias(String alias) {
    return $ExchangesTable(attachedDatabase, alias);
  }
}

class ExchangeRow extends DataClass implements Insertable<ExchangeRow> {
  final int id;
  final String isoAlpha2;
  final String currencyCode;
  final int amountMinor;
  final int? krwPaid;
  final String memo;
  final DateTime exchangedOn;
  const ExchangeRow({
    required this.id,
    required this.isoAlpha2,
    required this.currencyCode,
    required this.amountMinor,
    this.krwPaid,
    required this.memo,
    required this.exchangedOn,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['iso_alpha2'] = Variable<String>(isoAlpha2);
    map['currency_code'] = Variable<String>(currencyCode);
    map['amount_minor'] = Variable<int>(amountMinor);
    if (!nullToAbsent || krwPaid != null) {
      map['krw_paid'] = Variable<int>(krwPaid);
    }
    map['memo'] = Variable<String>(memo);
    map['exchanged_on'] = Variable<DateTime>(exchangedOn);
    return map;
  }

  ExchangesCompanion toCompanion(bool nullToAbsent) {
    return ExchangesCompanion(
      id: Value(id),
      isoAlpha2: Value(isoAlpha2),
      currencyCode: Value(currencyCode),
      amountMinor: Value(amountMinor),
      krwPaid: krwPaid == null && nullToAbsent
          ? const Value.absent()
          : Value(krwPaid),
      memo: Value(memo),
      exchangedOn: Value(exchangedOn),
    );
  }

  factory ExchangeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ExchangeRow(
      id: serializer.fromJson<int>(json['id']),
      isoAlpha2: serializer.fromJson<String>(json['isoAlpha2']),
      currencyCode: serializer.fromJson<String>(json['currencyCode']),
      amountMinor: serializer.fromJson<int>(json['amountMinor']),
      krwPaid: serializer.fromJson<int?>(json['krwPaid']),
      memo: serializer.fromJson<String>(json['memo']),
      exchangedOn: serializer.fromJson<DateTime>(json['exchangedOn']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'isoAlpha2': serializer.toJson<String>(isoAlpha2),
      'currencyCode': serializer.toJson<String>(currencyCode),
      'amountMinor': serializer.toJson<int>(amountMinor),
      'krwPaid': serializer.toJson<int?>(krwPaid),
      'memo': serializer.toJson<String>(memo),
      'exchangedOn': serializer.toJson<DateTime>(exchangedOn),
    };
  }

  ExchangeRow copyWith({
    int? id,
    String? isoAlpha2,
    String? currencyCode,
    int? amountMinor,
    Value<int?> krwPaid = const Value.absent(),
    String? memo,
    DateTime? exchangedOn,
  }) => ExchangeRow(
    id: id ?? this.id,
    isoAlpha2: isoAlpha2 ?? this.isoAlpha2,
    currencyCode: currencyCode ?? this.currencyCode,
    amountMinor: amountMinor ?? this.amountMinor,
    krwPaid: krwPaid.present ? krwPaid.value : this.krwPaid,
    memo: memo ?? this.memo,
    exchangedOn: exchangedOn ?? this.exchangedOn,
  );
  ExchangeRow copyWithCompanion(ExchangesCompanion data) {
    return ExchangeRow(
      id: data.id.present ? data.id.value : this.id,
      isoAlpha2: data.isoAlpha2.present ? data.isoAlpha2.value : this.isoAlpha2,
      currencyCode: data.currencyCode.present
          ? data.currencyCode.value
          : this.currencyCode,
      amountMinor: data.amountMinor.present
          ? data.amountMinor.value
          : this.amountMinor,
      krwPaid: data.krwPaid.present ? data.krwPaid.value : this.krwPaid,
      memo: data.memo.present ? data.memo.value : this.memo,
      exchangedOn: data.exchangedOn.present
          ? data.exchangedOn.value
          : this.exchangedOn,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ExchangeRow(')
          ..write('id: $id, ')
          ..write('isoAlpha2: $isoAlpha2, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('krwPaid: $krwPaid, ')
          ..write('memo: $memo, ')
          ..write('exchangedOn: $exchangedOn')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    isoAlpha2,
    currencyCode,
    amountMinor,
    krwPaid,
    memo,
    exchangedOn,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ExchangeRow &&
          other.id == this.id &&
          other.isoAlpha2 == this.isoAlpha2 &&
          other.currencyCode == this.currencyCode &&
          other.amountMinor == this.amountMinor &&
          other.krwPaid == this.krwPaid &&
          other.memo == this.memo &&
          other.exchangedOn == this.exchangedOn);
}

class ExchangesCompanion extends UpdateCompanion<ExchangeRow> {
  final Value<int> id;
  final Value<String> isoAlpha2;
  final Value<String> currencyCode;
  final Value<int> amountMinor;
  final Value<int?> krwPaid;
  final Value<String> memo;
  final Value<DateTime> exchangedOn;
  const ExchangesCompanion({
    this.id = const Value.absent(),
    this.isoAlpha2 = const Value.absent(),
    this.currencyCode = const Value.absent(),
    this.amountMinor = const Value.absent(),
    this.krwPaid = const Value.absent(),
    this.memo = const Value.absent(),
    this.exchangedOn = const Value.absent(),
  });
  ExchangesCompanion.insert({
    this.id = const Value.absent(),
    required String isoAlpha2,
    required String currencyCode,
    required int amountMinor,
    this.krwPaid = const Value.absent(),
    this.memo = const Value.absent(),
    required DateTime exchangedOn,
  }) : isoAlpha2 = Value(isoAlpha2),
       currencyCode = Value(currencyCode),
       amountMinor = Value(amountMinor),
       exchangedOn = Value(exchangedOn);
  static Insertable<ExchangeRow> custom({
    Expression<int>? id,
    Expression<String>? isoAlpha2,
    Expression<String>? currencyCode,
    Expression<int>? amountMinor,
    Expression<int>? krwPaid,
    Expression<String>? memo,
    Expression<DateTime>? exchangedOn,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (isoAlpha2 != null) 'iso_alpha2': isoAlpha2,
      if (currencyCode != null) 'currency_code': currencyCode,
      if (amountMinor != null) 'amount_minor': amountMinor,
      if (krwPaid != null) 'krw_paid': krwPaid,
      if (memo != null) 'memo': memo,
      if (exchangedOn != null) 'exchanged_on': exchangedOn,
    });
  }

  ExchangesCompanion copyWith({
    Value<int>? id,
    Value<String>? isoAlpha2,
    Value<String>? currencyCode,
    Value<int>? amountMinor,
    Value<int?>? krwPaid,
    Value<String>? memo,
    Value<DateTime>? exchangedOn,
  }) {
    return ExchangesCompanion(
      id: id ?? this.id,
      isoAlpha2: isoAlpha2 ?? this.isoAlpha2,
      currencyCode: currencyCode ?? this.currencyCode,
      amountMinor: amountMinor ?? this.amountMinor,
      krwPaid: krwPaid ?? this.krwPaid,
      memo: memo ?? this.memo,
      exchangedOn: exchangedOn ?? this.exchangedOn,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (isoAlpha2.present) {
      map['iso_alpha2'] = Variable<String>(isoAlpha2.value);
    }
    if (currencyCode.present) {
      map['currency_code'] = Variable<String>(currencyCode.value);
    }
    if (amountMinor.present) {
      map['amount_minor'] = Variable<int>(amountMinor.value);
    }
    if (krwPaid.present) {
      map['krw_paid'] = Variable<int>(krwPaid.value);
    }
    if (memo.present) {
      map['memo'] = Variable<String>(memo.value);
    }
    if (exchangedOn.present) {
      map['exchanged_on'] = Variable<DateTime>(exchangedOn.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ExchangesCompanion(')
          ..write('id: $id, ')
          ..write('isoAlpha2: $isoAlpha2, ')
          ..write('currencyCode: $currencyCode, ')
          ..write('amountMinor: $amountMinor, ')
          ..write('krwPaid: $krwPaid, ')
          ..write('memo: $memo, ')
          ..write('exchangedOn: $exchangedOn')
          ..write(')'))
        .toString();
  }
}

abstract class _$WalletDatabase extends GeneratedDatabase {
  _$WalletDatabase(QueryExecutor e) : super(e);
  $WalletDatabaseManager get managers => $WalletDatabaseManager(this);
  late final $ExpensesTable expenses = $ExpensesTable(this);
  late final $ExchangesTable exchanges = $ExchangesTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [expenses, exchanges];
}

typedef $$ExpensesTableCreateCompanionBuilder = ExpensesCompanion Function({
  Value<int> id,
  required String isoAlpha2,
  required String currencyCode,
  required String category,
  required int amountMinor,
  Value<double?> krwPerUnitAtEntry,
  Value<String> memo,
  required DateTime spentOn,
});
typedef $$ExpensesTableUpdateCompanionBuilder = ExpensesCompanion Function({
  Value<int> id,
  Value<String> isoAlpha2,
  Value<String> currencyCode,
  Value<String> category,
  Value<int> amountMinor,
  Value<double?> krwPerUnitAtEntry,
  Value<String> memo,
  Value<DateTime> spentOn,
});

class $$ExpensesTableFilterComposer
    extends Composer<_$WalletDatabase, $ExpensesTable> {
  $$ExpensesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get isoAlpha2 => $composableBuilder(
    column: $table.isoAlpha2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get krwPerUnitAtEntry => $composableBuilder(
    column: $table.krwPerUnitAtEntry,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memo => $composableBuilder(
    column: $table.memo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get spentOn => $composableBuilder(
    column: $table.spentOn,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExpensesTableOrderingComposer
    extends Composer<_$WalletDatabase, $ExpensesTable> {
  $$ExpensesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get isoAlpha2 => $composableBuilder(
    column: $table.isoAlpha2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get category => $composableBuilder(
    column: $table.category,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get krwPerUnitAtEntry => $composableBuilder(
    column: $table.krwPerUnitAtEntry,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memo => $composableBuilder(
    column: $table.memo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get spentOn => $composableBuilder(
    column: $table.spentOn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExpensesTableAnnotationComposer
    extends Composer<_$WalletDatabase, $ExpensesTable> {
  $$ExpensesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get isoAlpha2 =>
      $composableBuilder(column: $table.isoAlpha2, builder: (column) => column);

  GeneratedColumn<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => column,
  );

  GeneratedColumn<String> get category =>
      $composableBuilder(column: $table.category, builder: (column) => column);

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<double> get krwPerUnitAtEntry => $composableBuilder(
    column: $table.krwPerUnitAtEntry,
    builder: (column) => column,
  );

  GeneratedColumn<String> get memo =>
      $composableBuilder(column: $table.memo, builder: (column) => column);

  GeneratedColumn<DateTime> get spentOn =>
      $composableBuilder(column: $table.spentOn, builder: (column) => column);
}

class $$ExpensesTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $ExpensesTable,
          ExpenseRow,
          $$ExpensesTableFilterComposer,
          $$ExpensesTableOrderingComposer,
          $$ExpensesTableAnnotationComposer,
          $$ExpensesTableCreateCompanionBuilder,
          $$ExpensesTableUpdateCompanionBuilder,
          (
            ExpenseRow,
            BaseReferences<_$WalletDatabase, $ExpensesTable, ExpenseRow>,
          ),
          ExpenseRow,
          PrefetchHooks Function()
        > {
  $$ExpensesTableTableManager(_$WalletDatabase db, $ExpensesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExpensesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExpensesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExpensesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> isoAlpha2 = const Value.absent(),
                Value<String> currencyCode = const Value.absent(),
                Value<String> category = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<double?> krwPerUnitAtEntry = const Value.absent(),
                Value<String> memo = const Value.absent(),
                Value<DateTime> spentOn = const Value.absent(),
              }) => ExpensesCompanion(
                id: id,
                isoAlpha2: isoAlpha2,
                currencyCode: currencyCode,
                category: category,
                amountMinor: amountMinor,
                krwPerUnitAtEntry: krwPerUnitAtEntry,
                memo: memo,
                spentOn: spentOn,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String isoAlpha2,
                required String currencyCode,
                required String category,
                required int amountMinor,
                Value<double?> krwPerUnitAtEntry = const Value.absent(),
                Value<String> memo = const Value.absent(),
                required DateTime spentOn,
              }) => ExpensesCompanion.insert(
                id: id,
                isoAlpha2: isoAlpha2,
                currencyCode: currencyCode,
                category: category,
                amountMinor: amountMinor,
                krwPerUnitAtEntry: krwPerUnitAtEntry,
                memo: memo,
                spentOn: spentOn,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExpensesTable, ExpenseRow>(table),
                  BaseReferences<_$WalletDatabase, $ExpensesTable, ExpenseRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExpensesTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $ExpensesTable,
      ExpenseRow,
      $$ExpensesTableFilterComposer,
      $$ExpensesTableOrderingComposer,
      $$ExpensesTableAnnotationComposer,
      $$ExpensesTableCreateCompanionBuilder,
      $$ExpensesTableUpdateCompanionBuilder,
      (
        ExpenseRow,
        BaseReferences<_$WalletDatabase, $ExpensesTable, ExpenseRow>,
      ),
      ExpenseRow,
      PrefetchHooks Function()
    >;
typedef $$ExchangesTableCreateCompanionBuilder = ExchangesCompanion Function({
  Value<int> id,
  required String isoAlpha2,
  required String currencyCode,
  required int amountMinor,
  Value<int?> krwPaid,
  Value<String> memo,
  required DateTime exchangedOn,
});
typedef $$ExchangesTableUpdateCompanionBuilder = ExchangesCompanion Function({
  Value<int> id,
  Value<String> isoAlpha2,
  Value<String> currencyCode,
  Value<int> amountMinor,
  Value<int?> krwPaid,
  Value<String> memo,
  Value<DateTime> exchangedOn,
});

class $$ExchangesTableFilterComposer
    extends Composer<_$WalletDatabase, $ExchangesTable> {
  $$ExchangesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get isoAlpha2 => $composableBuilder(
    column: $table.isoAlpha2,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get krwPaid => $composableBuilder(
    column: $table.krwPaid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get memo => $composableBuilder(
    column: $table.memo,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get exchangedOn => $composableBuilder(
    column: $table.exchangedOn,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ExchangesTableOrderingComposer
    extends Composer<_$WalletDatabase, $ExchangesTable> {
  $$ExchangesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get isoAlpha2 => $composableBuilder(
    column: $table.isoAlpha2,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get krwPaid => $composableBuilder(
    column: $table.krwPaid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get memo => $composableBuilder(
    column: $table.memo,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get exchangedOn => $composableBuilder(
    column: $table.exchangedOn,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ExchangesTableAnnotationComposer
    extends Composer<_$WalletDatabase, $ExchangesTable> {
  $$ExchangesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get isoAlpha2 =>
      $composableBuilder(column: $table.isoAlpha2, builder: (column) => column);

  GeneratedColumn<String> get currencyCode => $composableBuilder(
    column: $table.currencyCode,
    builder: (column) => column,
  );

  GeneratedColumn<int> get amountMinor => $composableBuilder(
    column: $table.amountMinor,
    builder: (column) => column,
  );

  GeneratedColumn<int> get krwPaid =>
      $composableBuilder(column: $table.krwPaid, builder: (column) => column);

  GeneratedColumn<String> get memo =>
      $composableBuilder(column: $table.memo, builder: (column) => column);

  GeneratedColumn<DateTime> get exchangedOn => $composableBuilder(
    column: $table.exchangedOn,
    builder: (column) => column,
  );
}

class $$ExchangesTableTableManager
    extends
        RootTableManager<
          _$WalletDatabase,
          $ExchangesTable,
          ExchangeRow,
          $$ExchangesTableFilterComposer,
          $$ExchangesTableOrderingComposer,
          $$ExchangesTableAnnotationComposer,
          $$ExchangesTableCreateCompanionBuilder,
          $$ExchangesTableUpdateCompanionBuilder,
          (
            ExchangeRow,
            BaseReferences<_$WalletDatabase, $ExchangesTable, ExchangeRow>,
          ),
          ExchangeRow,
          PrefetchHooks Function()
        > {
  $$ExchangesTableTableManager(_$WalletDatabase db, $ExchangesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ExchangesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ExchangesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ExchangesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> isoAlpha2 = const Value.absent(),
                Value<String> currencyCode = const Value.absent(),
                Value<int> amountMinor = const Value.absent(),
                Value<int?> krwPaid = const Value.absent(),
                Value<String> memo = const Value.absent(),
                Value<DateTime> exchangedOn = const Value.absent(),
              }) => ExchangesCompanion(
                id: id,
                isoAlpha2: isoAlpha2,
                currencyCode: currencyCode,
                amountMinor: amountMinor,
                krwPaid: krwPaid,
                memo: memo,
                exchangedOn: exchangedOn,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String isoAlpha2,
                required String currencyCode,
                required int amountMinor,
                Value<int?> krwPaid = const Value.absent(),
                Value<String> memo = const Value.absent(),
                required DateTime exchangedOn,
              }) => ExchangesCompanion.insert(
                id: id,
                isoAlpha2: isoAlpha2,
                currencyCode: currencyCode,
                amountMinor: amountMinor,
                krwPaid: krwPaid,
                memo: memo,
                exchangedOn: exchangedOn,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ExchangesTable, ExchangeRow>(table),
                  BaseReferences<
                    _$WalletDatabase,
                    $ExchangesTable,
                    ExchangeRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ExchangesTableProcessedTableManager =
    ProcessedTableManager<
      _$WalletDatabase,
      $ExchangesTable,
      ExchangeRow,
      $$ExchangesTableFilterComposer,
      $$ExchangesTableOrderingComposer,
      $$ExchangesTableAnnotationComposer,
      $$ExchangesTableCreateCompanionBuilder,
      $$ExchangesTableUpdateCompanionBuilder,
      (
        ExchangeRow,
        BaseReferences<_$WalletDatabase, $ExchangesTable, ExchangeRow>,
      ),
      ExchangeRow,
      PrefetchHooks Function()
    >;

class $WalletDatabaseManager {
  final _$WalletDatabase _db;
  $WalletDatabaseManager(this._db);
  $$ExpensesTableTableManager get expenses =>
      $$ExpensesTableTableManager(_db, _db.expenses);
  $$ExchangesTableTableManager get exchanges =>
      $$ExchangesTableTableManager(_db, _db.exchanges);
}

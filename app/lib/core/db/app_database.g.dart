// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $CheckinsTable extends Checkins
    with TableInfo<$CheckinsTable, CheckinRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CheckinsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countryIsoMeta = const VerificationMeta(
    'countryIso',
  );
  @override
  late final GeneratedColumn<String> countryIso = GeneratedColumn<String>(
    'country_iso',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 2,
      maxTextLength: 2,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  late final GeneratedColumnWithTypeConverter<CheckinSource, String> source =
      GeneratedColumn<String>(
        'source',
        aliasedName,
        false,
        type: DriftSqlType.string,
        requiredDuringInsert: true,
      ).withConverter<CheckinSource>($CheckinsTable.$convertersource);
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    lat,
    lng,
    countryIso,
    recordedAt,
    source,
    synced,
    serverId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'checkins';
  @override
  VerificationContext validateIntegrity(
    Insertable<CheckinRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    } else if (isInserting) {
      context.missing(_lngMeta);
    }
    if (data.containsKey('country_iso')) {
      context.handle(
        _countryIsoMeta,
        countryIso.isAcceptableOrUnknown(data['country_iso']!, _countryIsoMeta),
      );
    } else if (isInserting) {
      context.missing(_countryIsoMeta);
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CheckinRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CheckinRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      )!,
      countryIso: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country_iso'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recorded_at'],
      )!,
      source: $CheckinsTable.$convertersource.fromSql(
        attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}source'],
        )!,
      ),
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
    );
  }

  @override
  $CheckinsTable createAlias(String alias) {
    return $CheckinsTable(attachedDatabase, alias);
  }

  static JsonTypeConverter2<CheckinSource, String, String> $convertersource =
      const EnumNameConverter<CheckinSource>(CheckinSource.values);
}

class CheckinRow extends DataClass implements Insertable<CheckinRow> {
  final int id;
  final double lat;
  final double lng;
  final String countryIso;
  final DateTime recordedAt;
  final CheckinSource source;
  final bool synced;
  final String? serverId;
  const CheckinRow({
    required this.id,
    required this.lat,
    required this.lng,
    required this.countryIso,
    required this.recordedAt,
    required this.source,
    required this.synced,
    this.serverId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['lat'] = Variable<double>(lat);
    map['lng'] = Variable<double>(lng);
    map['country_iso'] = Variable<String>(countryIso);
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    {
      map['source'] = Variable<String>(
        $CheckinsTable.$convertersource.toSql(source),
      );
    }
    map['synced'] = Variable<bool>(synced);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    return map;
  }

  CheckinsCompanion toCompanion(bool nullToAbsent) {
    return CheckinsCompanion(
      id: Value(id),
      lat: Value(lat),
      lng: Value(lng),
      countryIso: Value(countryIso),
      recordedAt: Value(recordedAt),
      source: Value(source),
      synced: Value(synced),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
    );
  }

  factory CheckinRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CheckinRow(
      id: serializer.fromJson<int>(json['id']),
      lat: serializer.fromJson<double>(json['lat']),
      lng: serializer.fromJson<double>(json['lng']),
      countryIso: serializer.fromJson<String>(json['countryIso']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
      source: $CheckinsTable.$convertersource.fromJson(
        serializer.fromJson<String>(json['source']),
      ),
      synced: serializer.fromJson<bool>(json['synced']),
      serverId: serializer.fromJson<String?>(json['serverId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lat': serializer.toJson<double>(lat),
      'lng': serializer.toJson<double>(lng),
      'countryIso': serializer.toJson<String>(countryIso),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
      'source': serializer.toJson<String>(
        $CheckinsTable.$convertersource.toJson(source),
      ),
      'synced': serializer.toJson<bool>(synced),
      'serverId': serializer.toJson<String?>(serverId),
    };
  }

  CheckinRow copyWith({
    int? id,
    double? lat,
    double? lng,
    String? countryIso,
    DateTime? recordedAt,
    CheckinSource? source,
    bool? synced,
    Value<String?> serverId = const Value.absent(),
  }) => CheckinRow(
    id: id ?? this.id,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    countryIso: countryIso ?? this.countryIso,
    recordedAt: recordedAt ?? this.recordedAt,
    source: source ?? this.source,
    synced: synced ?? this.synced,
    serverId: serverId.present ? serverId.value : this.serverId,
  );
  CheckinRow copyWithCompanion(CheckinsCompanion data) {
    return CheckinRow(
      id: data.id.present ? data.id.value : this.id,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      countryIso: data.countryIso.present
          ? data.countryIso.value
          : this.countryIso,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
      source: data.source.present ? data.source.value : this.source,
      synced: data.synced.present ? data.synced.value : this.synced,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CheckinRow(')
          ..write('id: $id, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('countryIso: $countryIso, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('source: $source, ')
          ..write('synced: $synced, ')
          ..write('serverId: $serverId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    lat,
    lng,
    countryIso,
    recordedAt,
    source,
    synced,
    serverId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CheckinRow &&
          other.id == this.id &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.countryIso == this.countryIso &&
          other.recordedAt == this.recordedAt &&
          other.source == this.source &&
          other.synced == this.synced &&
          other.serverId == this.serverId);
}

class CheckinsCompanion extends UpdateCompanion<CheckinRow> {
  final Value<int> id;
  final Value<double> lat;
  final Value<double> lng;
  final Value<String> countryIso;
  final Value<DateTime> recordedAt;
  final Value<CheckinSource> source;
  final Value<bool> synced;
  final Value<String?> serverId;
  const CheckinsCompanion({
    this.id = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.countryIso = const Value.absent(),
    this.recordedAt = const Value.absent(),
    this.source = const Value.absent(),
    this.synced = const Value.absent(),
    this.serverId = const Value.absent(),
  });
  CheckinsCompanion.insert({
    this.id = const Value.absent(),
    required double lat,
    required double lng,
    required String countryIso,
    required DateTime recordedAt,
    required CheckinSource source,
    this.synced = const Value.absent(),
    this.serverId = const Value.absent(),
  }) : lat = Value(lat),
       lng = Value(lng),
       countryIso = Value(countryIso),
       recordedAt = Value(recordedAt),
       source = Value(source);
  static Insertable<CheckinRow> custom({
    Expression<int>? id,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<String>? countryIso,
    Expression<DateTime>? recordedAt,
    Expression<String>? source,
    Expression<bool>? synced,
    Expression<String>? serverId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (countryIso != null) 'country_iso': countryIso,
      if (recordedAt != null) 'recorded_at': recordedAt,
      if (source != null) 'source': source,
      if (synced != null) 'synced': synced,
      if (serverId != null) 'server_id': serverId,
    });
  }

  CheckinsCompanion copyWith({
    Value<int>? id,
    Value<double>? lat,
    Value<double>? lng,
    Value<String>? countryIso,
    Value<DateTime>? recordedAt,
    Value<CheckinSource>? source,
    Value<bool>? synced,
    Value<String?>? serverId,
  }) {
    return CheckinsCompanion(
      id: id ?? this.id,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      countryIso: countryIso ?? this.countryIso,
      recordedAt: recordedAt ?? this.recordedAt,
      source: source ?? this.source,
      synced: synced ?? this.synced,
      serverId: serverId ?? this.serverId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (countryIso.present) {
      map['country_iso'] = Variable<String>(countryIso.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    if (source.present) {
      map['source'] = Variable<String>(
        $CheckinsTable.$convertersource.toSql(source.value),
      );
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CheckinsCompanion(')
          ..write('id: $id, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('countryIso: $countryIso, ')
          ..write('recordedAt: $recordedAt, ')
          ..write('source: $source, ')
          ..write('synced: $synced, ')
          ..write('serverId: $serverId')
          ..write(')'))
        .toString();
  }
}

class $DailyStepsTable extends DailySteps
    with TableInfo<$DailyStepsTable, DailyStepRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DailyStepsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _dateMeta = const VerificationMeta('date');
  @override
  late final GeneratedColumn<DateTime> date = GeneratedColumn<DateTime>(
    'date',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countryIsoMeta = const VerificationMeta(
    'countryIso',
  );
  @override
  late final GeneratedColumn<String> countryIso = GeneratedColumn<String>(
    'country_iso',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 2,
      maxTextLength: 2,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepCountMeta = const VerificationMeta(
    'stepCount',
  );
  @override
  late final GeneratedColumn<int> stepCount = GeneratedColumn<int>(
    'step_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _syncedMeta = const VerificationMeta('synced');
  @override
  late final GeneratedColumn<bool> synced = GeneratedColumn<bool>(
    'synced',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("synced" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _serverIdMeta = const VerificationMeta(
    'serverId',
  );
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
    'server_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    date,
    countryIso,
    stepCount,
    synced,
    serverId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'daily_steps';
  @override
  VerificationContext validateIntegrity(
    Insertable<DailyStepRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('date')) {
      context.handle(
        _dateMeta,
        date.isAcceptableOrUnknown(data['date']!, _dateMeta),
      );
    } else if (isInserting) {
      context.missing(_dateMeta);
    }
    if (data.containsKey('country_iso')) {
      context.handle(
        _countryIsoMeta,
        countryIso.isAcceptableOrUnknown(data['country_iso']!, _countryIsoMeta),
      );
    } else if (isInserting) {
      context.missing(_countryIsoMeta);
    }
    if (data.containsKey('step_count')) {
      context.handle(
        _stepCountMeta,
        stepCount.isAcceptableOrUnknown(data['step_count']!, _stepCountMeta),
      );
    } else if (isInserting) {
      context.missing(_stepCountMeta);
    }
    if (data.containsKey('synced')) {
      context.handle(
        _syncedMeta,
        synced.isAcceptableOrUnknown(data['synced']!, _syncedMeta),
      );
    }
    if (data.containsKey('server_id')) {
      context.handle(
        _serverIdMeta,
        serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {date, countryIso},
  ];
  @override
  DailyStepRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DailyStepRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      date: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}date'],
      )!,
      countryIso: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country_iso'],
      )!,
      stepCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}step_count'],
      )!,
      synced: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}synced'],
      )!,
      serverId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}server_id'],
      ),
    );
  }

  @override
  $DailyStepsTable createAlias(String alias) {
    return $DailyStepsTable(attachedDatabase, alias);
  }
}

class DailyStepRow extends DataClass implements Insertable<DailyStepRow> {
  final int id;
  final DateTime date;
  final String countryIso;
  final int stepCount;
  final bool synced;
  final String? serverId;
  const DailyStepRow({
    required this.id,
    required this.date,
    required this.countryIso,
    required this.stepCount,
    required this.synced,
    this.serverId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['date'] = Variable<DateTime>(date);
    map['country_iso'] = Variable<String>(countryIso);
    map['step_count'] = Variable<int>(stepCount);
    map['synced'] = Variable<bool>(synced);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    return map;
  }

  DailyStepsCompanion toCompanion(bool nullToAbsent) {
    return DailyStepsCompanion(
      id: Value(id),
      date: Value(date),
      countryIso: Value(countryIso),
      stepCount: Value(stepCount),
      synced: Value(synced),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
    );
  }

  factory DailyStepRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DailyStepRow(
      id: serializer.fromJson<int>(json['id']),
      date: serializer.fromJson<DateTime>(json['date']),
      countryIso: serializer.fromJson<String>(json['countryIso']),
      stepCount: serializer.fromJson<int>(json['stepCount']),
      synced: serializer.fromJson<bool>(json['synced']),
      serverId: serializer.fromJson<String?>(json['serverId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'date': serializer.toJson<DateTime>(date),
      'countryIso': serializer.toJson<String>(countryIso),
      'stepCount': serializer.toJson<int>(stepCount),
      'synced': serializer.toJson<bool>(synced),
      'serverId': serializer.toJson<String?>(serverId),
    };
  }

  DailyStepRow copyWith({
    int? id,
    DateTime? date,
    String? countryIso,
    int? stepCount,
    bool? synced,
    Value<String?> serverId = const Value.absent(),
  }) => DailyStepRow(
    id: id ?? this.id,
    date: date ?? this.date,
    countryIso: countryIso ?? this.countryIso,
    stepCount: stepCount ?? this.stepCount,
    synced: synced ?? this.synced,
    serverId: serverId.present ? serverId.value : this.serverId,
  );
  DailyStepRow copyWithCompanion(DailyStepsCompanion data) {
    return DailyStepRow(
      id: data.id.present ? data.id.value : this.id,
      date: data.date.present ? data.date.value : this.date,
      countryIso: data.countryIso.present
          ? data.countryIso.value
          : this.countryIso,
      stepCount: data.stepCount.present ? data.stepCount.value : this.stepCount,
      synced: data.synced.present ? data.synced.value : this.synced,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DailyStepRow(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('countryIso: $countryIso, ')
          ..write('stepCount: $stepCount, ')
          ..write('synced: $synced, ')
          ..write('serverId: $serverId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, date, countryIso, stepCount, synced, serverId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DailyStepRow &&
          other.id == this.id &&
          other.date == this.date &&
          other.countryIso == this.countryIso &&
          other.stepCount == this.stepCount &&
          other.synced == this.synced &&
          other.serverId == this.serverId);
}

class DailyStepsCompanion extends UpdateCompanion<DailyStepRow> {
  final Value<int> id;
  final Value<DateTime> date;
  final Value<String> countryIso;
  final Value<int> stepCount;
  final Value<bool> synced;
  final Value<String?> serverId;
  const DailyStepsCompanion({
    this.id = const Value.absent(),
    this.date = const Value.absent(),
    this.countryIso = const Value.absent(),
    this.stepCount = const Value.absent(),
    this.synced = const Value.absent(),
    this.serverId = const Value.absent(),
  });
  DailyStepsCompanion.insert({
    this.id = const Value.absent(),
    required DateTime date,
    required String countryIso,
    required int stepCount,
    this.synced = const Value.absent(),
    this.serverId = const Value.absent(),
  }) : date = Value(date),
       countryIso = Value(countryIso),
       stepCount = Value(stepCount);
  static Insertable<DailyStepRow> custom({
    Expression<int>? id,
    Expression<DateTime>? date,
    Expression<String>? countryIso,
    Expression<int>? stepCount,
    Expression<bool>? synced,
    Expression<String>? serverId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (date != null) 'date': date,
      if (countryIso != null) 'country_iso': countryIso,
      if (stepCount != null) 'step_count': stepCount,
      if (synced != null) 'synced': synced,
      if (serverId != null) 'server_id': serverId,
    });
  }

  DailyStepsCompanion copyWith({
    Value<int>? id,
    Value<DateTime>? date,
    Value<String>? countryIso,
    Value<int>? stepCount,
    Value<bool>? synced,
    Value<String?>? serverId,
  }) {
    return DailyStepsCompanion(
      id: id ?? this.id,
      date: date ?? this.date,
      countryIso: countryIso ?? this.countryIso,
      stepCount: stepCount ?? this.stepCount,
      synced: synced ?? this.synced,
      serverId: serverId ?? this.serverId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (date.present) {
      map['date'] = Variable<DateTime>(date.value);
    }
    if (countryIso.present) {
      map['country_iso'] = Variable<String>(countryIso.value);
    }
    if (stepCount.present) {
      map['step_count'] = Variable<int>(stepCount.value);
    }
    if (synced.present) {
      map['synced'] = Variable<bool>(synced.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DailyStepsCompanion(')
          ..write('id: $id, ')
          ..write('date: $date, ')
          ..write('countryIso: $countryIso, ')
          ..write('stepCount: $stepCount, ')
          ..write('synced: $synced, ')
          ..write('serverId: $serverId')
          ..write(')'))
        .toString();
  }
}

class $RoutePointsTable extends RoutePoints
    with TableInfo<$RoutePointsTable, RoutePointRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $RoutePointsTable(this.attachedDatabase, [this._alias]);
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
  static const VerificationMeta _latMeta = const VerificationMeta('lat');
  @override
  late final GeneratedColumn<double> lat = GeneratedColumn<double>(
    'lat',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lngMeta = const VerificationMeta('lng');
  @override
  late final GeneratedColumn<double> lng = GeneratedColumn<double>(
    'lng',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _countryIsoMeta = const VerificationMeta(
    'countryIso',
  );
  @override
  late final GeneratedColumn<String> countryIso = GeneratedColumn<String>(
    'country_iso',
    aliasedName,
    false,
    additionalChecks: GeneratedColumn.checkTextLength(
      minTextLength: 2,
      maxTextLength: 2,
    ),
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recordedAtMeta = const VerificationMeta(
    'recordedAt',
  );
  @override
  late final GeneratedColumn<DateTime> recordedAt = GeneratedColumn<DateTime>(
    'recorded_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, lat, lng, countryIso, recordedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'route_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<RoutePointRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('lat')) {
      context.handle(
        _latMeta,
        lat.isAcceptableOrUnknown(data['lat']!, _latMeta),
      );
    } else if (isInserting) {
      context.missing(_latMeta);
    }
    if (data.containsKey('lng')) {
      context.handle(
        _lngMeta,
        lng.isAcceptableOrUnknown(data['lng']!, _lngMeta),
      );
    } else if (isInserting) {
      context.missing(_lngMeta);
    }
    if (data.containsKey('country_iso')) {
      context.handle(
        _countryIsoMeta,
        countryIso.isAcceptableOrUnknown(data['country_iso']!, _countryIsoMeta),
      );
    } else if (isInserting) {
      context.missing(_countryIsoMeta);
    }
    if (data.containsKey('recorded_at')) {
      context.handle(
        _recordedAtMeta,
        recordedAt.isAcceptableOrUnknown(data['recorded_at']!, _recordedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_recordedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  RoutePointRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return RoutePointRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      lat: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lat'],
      )!,
      lng: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}lng'],
      )!,
      countryIso: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}country_iso'],
      )!,
      recordedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}recorded_at'],
      )!,
    );
  }

  @override
  $RoutePointsTable createAlias(String alias) {
    return $RoutePointsTable(attachedDatabase, alias);
  }
}

class RoutePointRow extends DataClass implements Insertable<RoutePointRow> {
  final int id;
  final double lat;
  final double lng;
  final String countryIso;
  final DateTime recordedAt;
  const RoutePointRow({
    required this.id,
    required this.lat,
    required this.lng,
    required this.countryIso,
    required this.recordedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['lat'] = Variable<double>(lat);
    map['lng'] = Variable<double>(lng);
    map['country_iso'] = Variable<String>(countryIso);
    map['recorded_at'] = Variable<DateTime>(recordedAt);
    return map;
  }

  RoutePointsCompanion toCompanion(bool nullToAbsent) {
    return RoutePointsCompanion(
      id: Value(id),
      lat: Value(lat),
      lng: Value(lng),
      countryIso: Value(countryIso),
      recordedAt: Value(recordedAt),
    );
  }

  factory RoutePointRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return RoutePointRow(
      id: serializer.fromJson<int>(json['id']),
      lat: serializer.fromJson<double>(json['lat']),
      lng: serializer.fromJson<double>(json['lng']),
      countryIso: serializer.fromJson<String>(json['countryIso']),
      recordedAt: serializer.fromJson<DateTime>(json['recordedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'lat': serializer.toJson<double>(lat),
      'lng': serializer.toJson<double>(lng),
      'countryIso': serializer.toJson<String>(countryIso),
      'recordedAt': serializer.toJson<DateTime>(recordedAt),
    };
  }

  RoutePointRow copyWith({
    int? id,
    double? lat,
    double? lng,
    String? countryIso,
    DateTime? recordedAt,
  }) => RoutePointRow(
    id: id ?? this.id,
    lat: lat ?? this.lat,
    lng: lng ?? this.lng,
    countryIso: countryIso ?? this.countryIso,
    recordedAt: recordedAt ?? this.recordedAt,
  );
  RoutePointRow copyWithCompanion(RoutePointsCompanion data) {
    return RoutePointRow(
      id: data.id.present ? data.id.value : this.id,
      lat: data.lat.present ? data.lat.value : this.lat,
      lng: data.lng.present ? data.lng.value : this.lng,
      countryIso: data.countryIso.present
          ? data.countryIso.value
          : this.countryIso,
      recordedAt: data.recordedAt.present
          ? data.recordedAt.value
          : this.recordedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('RoutePointRow(')
          ..write('id: $id, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('countryIso: $countryIso, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, lat, lng, countryIso, recordedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is RoutePointRow &&
          other.id == this.id &&
          other.lat == this.lat &&
          other.lng == this.lng &&
          other.countryIso == this.countryIso &&
          other.recordedAt == this.recordedAt);
}

class RoutePointsCompanion extends UpdateCompanion<RoutePointRow> {
  final Value<int> id;
  final Value<double> lat;
  final Value<double> lng;
  final Value<String> countryIso;
  final Value<DateTime> recordedAt;
  const RoutePointsCompanion({
    this.id = const Value.absent(),
    this.lat = const Value.absent(),
    this.lng = const Value.absent(),
    this.countryIso = const Value.absent(),
    this.recordedAt = const Value.absent(),
  });
  RoutePointsCompanion.insert({
    this.id = const Value.absent(),
    required double lat,
    required double lng,
    required String countryIso,
    required DateTime recordedAt,
  }) : lat = Value(lat),
       lng = Value(lng),
       countryIso = Value(countryIso),
       recordedAt = Value(recordedAt);
  static Insertable<RoutePointRow> custom({
    Expression<int>? id,
    Expression<double>? lat,
    Expression<double>? lng,
    Expression<String>? countryIso,
    Expression<DateTime>? recordedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (lat != null) 'lat': lat,
      if (lng != null) 'lng': lng,
      if (countryIso != null) 'country_iso': countryIso,
      if (recordedAt != null) 'recorded_at': recordedAt,
    });
  }

  RoutePointsCompanion copyWith({
    Value<int>? id,
    Value<double>? lat,
    Value<double>? lng,
    Value<String>? countryIso,
    Value<DateTime>? recordedAt,
  }) {
    return RoutePointsCompanion(
      id: id ?? this.id,
      lat: lat ?? this.lat,
      lng: lng ?? this.lng,
      countryIso: countryIso ?? this.countryIso,
      recordedAt: recordedAt ?? this.recordedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (lat.present) {
      map['lat'] = Variable<double>(lat.value);
    }
    if (lng.present) {
      map['lng'] = Variable<double>(lng.value);
    }
    if (countryIso.present) {
      map['country_iso'] = Variable<String>(countryIso.value);
    }
    if (recordedAt.present) {
      map['recorded_at'] = Variable<DateTime>(recordedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('RoutePointsCompanion(')
          ..write('id: $id, ')
          ..write('lat: $lat, ')
          ..write('lng: $lng, ')
          ..write('countryIso: $countryIso, ')
          ..write('recordedAt: $recordedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $CheckinsTable checkins = $CheckinsTable(this);
  late final $DailyStepsTable dailySteps = $DailyStepsTable(this);
  late final $RoutePointsTable routePoints = $RoutePointsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    checkins,
    dailySteps,
    routePoints,
  ];
}

typedef $$CheckinsTableCreateCompanionBuilder = CheckinsCompanion Function({
  Value<int> id,
  required double lat,
  required double lng,
  required String countryIso,
  required DateTime recordedAt,
  required CheckinSource source,
  Value<bool> synced,
  Value<String?> serverId,
});
typedef $$CheckinsTableUpdateCompanionBuilder = CheckinsCompanion Function({
  Value<int> id,
  Value<double> lat,
  Value<double> lng,
  Value<String> countryIso,
  Value<DateTime> recordedAt,
  Value<CheckinSource> source,
  Value<bool> synced,
  Value<String?> serverId,
});

class $$CheckinsTableFilterComposer
    extends Composer<_$AppDatabase, $CheckinsTable> {
  $$CheckinsTableFilterComposer({
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

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get countryIso => $composableBuilder(
    column: $table.countryIso,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnWithTypeConverterFilters<CheckinSource, CheckinSource, String>
  get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnWithTypeConverterFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$CheckinsTableOrderingComposer
    extends Composer<_$AppDatabase, $CheckinsTable> {
  $$CheckinsTableOrderingComposer({
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

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get countryIso => $composableBuilder(
    column: $table.countryIso,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get source => $composableBuilder(
    column: $table.source,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$CheckinsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CheckinsTable> {
  $$CheckinsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<String> get countryIso => $composableBuilder(
    column: $table.countryIso,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );

  GeneratedColumnWithTypeConverter<CheckinSource, String> get source =>
      $composableBuilder(column: $table.source, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);
}

class $$CheckinsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CheckinsTable,
          CheckinRow,
          $$CheckinsTableFilterComposer,
          $$CheckinsTableOrderingComposer,
          $$CheckinsTableAnnotationComposer,
          $$CheckinsTableCreateCompanionBuilder,
          $$CheckinsTableUpdateCompanionBuilder,
          (
            CheckinRow,
            BaseReferences<_$AppDatabase, $CheckinsTable, CheckinRow>,
          ),
          CheckinRow,
          PrefetchHooks Function()
        > {
  $$CheckinsTableTableManager(_$AppDatabase db, $CheckinsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CheckinsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CheckinsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CheckinsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lng = const Value.absent(),
                Value<String> countryIso = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
                Value<CheckinSource> source = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
              }) => CheckinsCompanion(
                id: id,
                lat: lat,
                lng: lng,
                countryIso: countryIso,
                recordedAt: recordedAt,
                source: source,
                synced: synced,
                serverId: serverId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required double lat,
                required double lng,
                required String countryIso,
                required DateTime recordedAt,
                required CheckinSource source,
                Value<bool> synced = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
              }) => CheckinsCompanion.insert(
                id: id,
                lat: lat,
                lng: lng,
                countryIso: countryIso,
                recordedAt: recordedAt,
                source: source,
                synced: synced,
                serverId: serverId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CheckinsTable, CheckinRow>(table),
                  BaseReferences<_$AppDatabase, $CheckinsTable, CheckinRow>(
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

typedef $$CheckinsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CheckinsTable,
      CheckinRow,
      $$CheckinsTableFilterComposer,
      $$CheckinsTableOrderingComposer,
      $$CheckinsTableAnnotationComposer,
      $$CheckinsTableCreateCompanionBuilder,
      $$CheckinsTableUpdateCompanionBuilder,
      (CheckinRow, BaseReferences<_$AppDatabase, $CheckinsTable, CheckinRow>),
      CheckinRow,
      PrefetchHooks Function()
    >;
typedef $$DailyStepsTableCreateCompanionBuilder = DailyStepsCompanion Function({
  Value<int> id,
  required DateTime date,
  required String countryIso,
  required int stepCount,
  Value<bool> synced,
  Value<String?> serverId,
});
typedef $$DailyStepsTableUpdateCompanionBuilder = DailyStepsCompanion Function({
  Value<int> id,
  Value<DateTime> date,
  Value<String> countryIso,
  Value<int> stepCount,
  Value<bool> synced,
  Value<String?> serverId,
});

class $$DailyStepsTableFilterComposer
    extends Composer<_$AppDatabase, $DailyStepsTable> {
  $$DailyStepsTableFilterComposer({
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

  ColumnFilters<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get countryIso => $composableBuilder(
    column: $table.countryIso,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get stepCount => $composableBuilder(
    column: $table.stepCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$DailyStepsTableOrderingComposer
    extends Composer<_$AppDatabase, $DailyStepsTable> {
  $$DailyStepsTableOrderingComposer({
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

  ColumnOrderings<DateTime> get date => $composableBuilder(
    column: $table.date,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get countryIso => $composableBuilder(
    column: $table.countryIso,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get stepCount => $composableBuilder(
    column: $table.stepCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get synced => $composableBuilder(
    column: $table.synced,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get serverId => $composableBuilder(
    column: $table.serverId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DailyStepsTableAnnotationComposer
    extends Composer<_$AppDatabase, $DailyStepsTable> {
  $$DailyStepsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get date =>
      $composableBuilder(column: $table.date, builder: (column) => column);

  GeneratedColumn<String> get countryIso => $composableBuilder(
    column: $table.countryIso,
    builder: (column) => column,
  );

  GeneratedColumn<int> get stepCount =>
      $composableBuilder(column: $table.stepCount, builder: (column) => column);

  GeneratedColumn<bool> get synced =>
      $composableBuilder(column: $table.synced, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);
}

class $$DailyStepsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DailyStepsTable,
          DailyStepRow,
          $$DailyStepsTableFilterComposer,
          $$DailyStepsTableOrderingComposer,
          $$DailyStepsTableAnnotationComposer,
          $$DailyStepsTableCreateCompanionBuilder,
          $$DailyStepsTableUpdateCompanionBuilder,
          (
            DailyStepRow,
            BaseReferences<_$AppDatabase, $DailyStepsTable, DailyStepRow>,
          ),
          DailyStepRow,
          PrefetchHooks Function()
        > {
  $$DailyStepsTableTableManager(_$AppDatabase db, $DailyStepsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DailyStepsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DailyStepsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DailyStepsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<DateTime> date = const Value.absent(),
                Value<String> countryIso = const Value.absent(),
                Value<int> stepCount = const Value.absent(),
                Value<bool> synced = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
              }) => DailyStepsCompanion(
                id: id,
                date: date,
                countryIso: countryIso,
                stepCount: stepCount,
                synced: synced,
                serverId: serverId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required DateTime date,
                required String countryIso,
                required int stepCount,
                Value<bool> synced = const Value.absent(),
                Value<String?> serverId = const Value.absent(),
              }) => DailyStepsCompanion.insert(
                id: id,
                date: date,
                countryIso: countryIso,
                stepCount: stepCount,
                synced: synced,
                serverId: serverId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DailyStepsTable, DailyStepRow>(table),
                  BaseReferences<_$AppDatabase, $DailyStepsTable, DailyStepRow>(
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

typedef $$DailyStepsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DailyStepsTable,
      DailyStepRow,
      $$DailyStepsTableFilterComposer,
      $$DailyStepsTableOrderingComposer,
      $$DailyStepsTableAnnotationComposer,
      $$DailyStepsTableCreateCompanionBuilder,
      $$DailyStepsTableUpdateCompanionBuilder,
      (
        DailyStepRow,
        BaseReferences<_$AppDatabase, $DailyStepsTable, DailyStepRow>,
      ),
      DailyStepRow,
      PrefetchHooks Function()
    >;
typedef $$RoutePointsTableCreateCompanionBuilder =
    RoutePointsCompanion Function({
      Value<int> id,
      required double lat,
      required double lng,
      required String countryIso,
      required DateTime recordedAt,
    });
typedef $$RoutePointsTableUpdateCompanionBuilder =
    RoutePointsCompanion Function({
      Value<int> id,
      Value<double> lat,
      Value<double> lng,
      Value<String> countryIso,
      Value<DateTime> recordedAt,
    });

class $$RoutePointsTableFilterComposer
    extends Composer<_$AppDatabase, $RoutePointsTable> {
  $$RoutePointsTableFilterComposer({
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

  ColumnFilters<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get countryIso => $composableBuilder(
    column: $table.countryIso,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$RoutePointsTableOrderingComposer
    extends Composer<_$AppDatabase, $RoutePointsTable> {
  $$RoutePointsTableOrderingComposer({
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

  ColumnOrderings<double> get lat => $composableBuilder(
    column: $table.lat,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get lng => $composableBuilder(
    column: $table.lng,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get countryIso => $composableBuilder(
    column: $table.countryIso,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$RoutePointsTableAnnotationComposer
    extends Composer<_$AppDatabase, $RoutePointsTable> {
  $$RoutePointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get lat =>
      $composableBuilder(column: $table.lat, builder: (column) => column);

  GeneratedColumn<double> get lng =>
      $composableBuilder(column: $table.lng, builder: (column) => column);

  GeneratedColumn<String> get countryIso => $composableBuilder(
    column: $table.countryIso,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get recordedAt => $composableBuilder(
    column: $table.recordedAt,
    builder: (column) => column,
  );
}

class $$RoutePointsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $RoutePointsTable,
          RoutePointRow,
          $$RoutePointsTableFilterComposer,
          $$RoutePointsTableOrderingComposer,
          $$RoutePointsTableAnnotationComposer,
          $$RoutePointsTableCreateCompanionBuilder,
          $$RoutePointsTableUpdateCompanionBuilder,
          (
            RoutePointRow,
            BaseReferences<_$AppDatabase, $RoutePointsTable, RoutePointRow>,
          ),
          RoutePointRow,
          PrefetchHooks Function()
        > {
  $$RoutePointsTableTableManager(_$AppDatabase db, $RoutePointsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$RoutePointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$RoutePointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$RoutePointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<double> lat = const Value.absent(),
                Value<double> lng = const Value.absent(),
                Value<String> countryIso = const Value.absent(),
                Value<DateTime> recordedAt = const Value.absent(),
              }) => RoutePointsCompanion(
                id: id,
                lat: lat,
                lng: lng,
                countryIso: countryIso,
                recordedAt: recordedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required double lat,
                required double lng,
                required String countryIso,
                required DateTime recordedAt,
              }) => RoutePointsCompanion.insert(
                id: id,
                lat: lat,
                lng: lng,
                countryIso: countryIso,
                recordedAt: recordedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$RoutePointsTable, RoutePointRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $RoutePointsTable,
                    RoutePointRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$RoutePointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $RoutePointsTable,
      RoutePointRow,
      $$RoutePointsTableFilterComposer,
      $$RoutePointsTableOrderingComposer,
      $$RoutePointsTableAnnotationComposer,
      $$RoutePointsTableCreateCompanionBuilder,
      $$RoutePointsTableUpdateCompanionBuilder,
      (
        RoutePointRow,
        BaseReferences<_$AppDatabase, $RoutePointsTable, RoutePointRow>,
      ),
      RoutePointRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$CheckinsTableTableManager get checkins =>
      $$CheckinsTableTableManager(_db, _db.checkins);
  $$DailyStepsTableTableManager get dailySteps =>
      $$DailyStepsTableTableManager(_db, _db.dailySteps);
  $$RoutePointsTableTableManager get routePoints =>
      $$RoutePointsTableTableManager(_db, _db.routePoints);
}

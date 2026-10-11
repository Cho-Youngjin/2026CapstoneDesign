import 'package:app/features/wallet/domain/currency_info.dart';
import 'package:app/features/wallet/domain/expense_category.dart';
import 'package:app/features/wallet/domain/month_day.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final jpy = currencyInfoOf('JPY');
  final usd = currencyInfoOf('USD');
  final vnd = currencyInfoOf('VND');

  group('CurrencyInfo.parseToMinor', () {
    test('정수부가 12자리를 넘으면 예외 대신 null', () {
      expect(jpy.parseToMinor('999999999999'), 999999999999);
      expect(jpy.parseToMinor('1000000000000'), isNull);
      expect(usd.parseToMinor('1${'0' * 30}'), isNull);
    });

    test('콤마가 섞인 정수 입력을 최소단위로 바꾼다', () {
      expect(jpy.parseToMinor('1,200'), 1200);
      expect(usd.parseToMinor('12.5'), 1250);
      expect(usd.parseToMinor('12'), 1200);
    });

    test('통화보다 소수 자릿수가 많으면 null', () {
      expect(jpy.parseToMinor('12.5'), isNull);
      expect(usd.parseToMinor('12.345'), isNull);
    });

    test('0, 빈 값, 숫자가 아닌 값은 null', () {
      expect(usd.parseToMinor('0'), isNull);
      expect(usd.parseToMinor(''), isNull);
      expect(usd.parseToMinor('abc'), isNull);
      expect(usd.parseToMinor('-3'), isNull);
    });
  });

  group('CurrencyInfo 표시', () {
    test('통화 기호와 천 단위 콤마, 소수 자릿수로 표시한다', () {
      expect(jpy.format(1200), '¥1,200');
      expect(usd.format(1250), r'$12.50');
      expect(vnd.format(-50000), '-₫50,000');
    });

    test('편집 폼에 다시 채울 문자열은 콤마 없이 소수 자릿수를 맞춘다', () {
      expect(usd.toInputText(1250), '12.50');
      expect(jpy.toInputText(1200), '1200');
    });

    test('원화 환산은 반올림한 정수 원이다', () {
      expect(jpy.toKrw(1200, 8.4746), 10170);
      expect(vnd.toKrw(50000, 0.051934), 2597);
    });

    test('표시 단위는 단위×환율이 10원 이상이 되는 가장 작은 값이다', () {
      expect(usd.displayUnit(1339.2), 1);
      expect(jpy.displayUnit(8.4746), 100);
      expect(vnd.displayUnit(0.051934), 1000);
    });

    test('단위 라벨은 수량과 한글 단위를 붙인다', () {
      expect(jpy.unitLabel(100), '100엔');
      expect(vnd.unitLabel(1000), '1,000동');
      expect(usd.unitLabel(1), '1달러');
    });

    test('원화와 환율 값 표기', () {
      expect(formatKrw(10170), '10,170원');
      expect(formatKrw(-500), '-500원');
      expect(formatKrwRate(847.46), '847.46원');
      expect(formatKrwRate(1339.2), '1,339.20원');
    });
  });

  group('currencyInfoOf', () {
    test('소문자 코드도 찾는다', () {
      expect(currencyInfoOf('jpy').code, 'JPY');
    });

    test('표에 없는 통화는 코드로 표시하고 소수 2자리로 다룬다', () {
      final unknown = currencyInfoOf('XYZ');
      expect(unknown.minorDigits, 2);
      expect(unknown.format(150), 'XYZ 1.50');
    });

    test('우리 country 테이블의 통화 17개가 모두 표에 있다', () {
      const codes = ['AUD', 'CAD', 'CHF', 'CNY', 'CZK', 'EUR', 'GBP', 'HKD', 'IDR', 'JPY',
        'PHP', 'SGD', 'THB', 'TRY', 'TWD', 'USD', 'VND'];
      for (final code in codes) {
        // 표에 없으면 대체값의 nameKo가 코드 그대로다. 표의 통화는 모두 한글 이름을 가진다.
        expect(currencyInfoOf(code).nameKo, isNot(code), reason: code);
      }
    });
  });

  group('ExpenseCategory', () {
    test('코드로 찾고, 모르는 코드는 기타로 본다', () {
      expect(ExpenseCategory.fromCode('SIGHTSEEING'), ExpenseCategory.sightseeing);
      expect(ExpenseCategory.fromCode('???'), ExpenseCategory.other);
    });

    test('라벨과 메모 힌트', () {
      expect(ExpenseCategory.values.map((c) => c.labelKo).toList(),
          ['식비', '숙박', '교통', '관광', '기타']);
      expect(ExpenseCategory.other.memoHint, '여행자보험, eSIM 등');
      expect(ExpenseCategory.sightseeing.memoHint, '입장료, 투어 등');
      expect(ExpenseCategory.food.memoHint, '메모 (선택)');
    });
  });

  test('formatMonthDay', () {
    expect(formatMonthDay(DateTime(2026, 10, 9)), '10월 9일');
  });
}

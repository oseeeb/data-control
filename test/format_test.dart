import 'package:flutter_test/flutter_test.dart';
import 'package:flux/app/settings.dart';
import 'package:flux/ui/format.dart';

void main() {
  test('débit en Mo/s avec virgule', () {
    expect(formatRate(8400000, RateUnit.megabytes).toString(), '8,4 Mo/s');
  });

  test('débit en Mb/s (×8)', () {
    expect(formatRate(1000000, RateUnit.megabits).toString(), '8,0 Mb/s');
  });

  test('unité automatique', () {
    expect(formatRate(18000, RateUnit.auto).toString(), '18 Ko/s');
    expect(formatRate(9800000, RateUnit.auto).toString(), '9,8 Mo/s');
    expect(formatRate(2100000000, RateUnit.auto).toString(), '2,1 Go/s');
  });

  test('volumes', () {
    expect(formatVolume(1500000).toString(), '1,5 Mo');
    expect(formatVolume(124000000).toString(), '124 Mo');
    expect(formatVolume(800).toString(), '1 Ko');
  });

  test('durées', () {
    expect(formatClock(const Duration(seconds: 84)), '01:24');
    expect(formatDuration(const Duration(seconds: 84)), '1 min 24 s');
    expect(formatDuration(const Duration(seconds: 9)), '9 s');
    expect(formatShare(86, 100), '86 %');
    expect(formatShare(1, 0), '0 %');
  });
}

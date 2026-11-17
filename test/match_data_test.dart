import 'package:flutter_test/flutter_test.dart';
import 'package:spoda_app/main.dart';

void main() {
  const match = MatchData(raw: {
    'teamName1': 'Chitwan Rhinos',
    'teamName2': 'Karnali Yaks',
    'team1ThumbUrl': 'https://example.com/team1.png',
    'team2ThumbUrl': 'https://example.com/team2.png',
  });

  test('overview numbered teams resolve for card sides A and B', () {
    expect(match.teamName('A'), 'Chitwan Rhinos');
    expect(match.teamName('B'), 'Karnali Yaks');
    expect(match.teamFlag('A'), 'https://example.com/team1.png');
    expect(match.teamFlag('B'), 'https://example.com/team2.png');
  });

  test('scorecard names take priority over overview names', () {
    final scorecard = <String, dynamic>{
      'data': {
        'response': {
          'teama': {'short_name': 'CR'},
          'teamb': {'short_name': 'KY'},
        },
      },
    };
    expect(match.teamName('A', scorecard: scorecard), 'CR');
    expect(match.teamName('B', scorecard: scorecard), 'KY');
  });
  test('timezone-free match starts represent UTC', () {
    const match = MatchData(raw: {'startDate': '2026-11-18T23:30:00'});
    expect(match.startDate, DateTime.utc(2026, 11, 18, 23, 30));
    expect(match.startDate!.isUtc, isTrue);
    expect(match.startDate!.toLocal().toUtc(), match.startDate);
  });

  test('match starts preserve explicit timezone offsets', () {
    const match = MatchData(raw: {'startDate': '2026-11-19T05:00:00+05:30'});
    expect(match.startDate, DateTime.utc(2026, 11, 18, 23, 30));
    const utcMatch = MatchData(raw: {'startDate': '2026-11-18T23:30:00Z'});
    expect(utcMatch.startDate, match.startDate);
  });

  test('missing or invalid match times stay unavailable', () {
    expect(const MatchData(raw: {}).startDate, isNull);
    expect(const MatchData(raw: {'startDate': 'invalid'}).startDate, isNull);
  });}

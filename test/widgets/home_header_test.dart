import 'package:berber_randevu/widgets/home_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home header fits 320dp width with large system text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.5)),
        child: MaterialApp(
          home: Scaffold(
            body: HomeHeader(
              managementMenu: PopupMenuButton<String>(
                tooltip: 'Yönetim',
                icon: const Icon(Icons.settings),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'services', child: Text('Hizmetler')),
                ],
              ),
              isSearching: false,
              onSearchPressed: () {},
              showTodayButton: true,
              onTodayPressed: () {},
            ),
          ),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('BarberBook'), findsOneWidget);
    expect(
      tester.getRect(find.text('BarberBook')).height,
      greaterThanOrEqualTo(42),
    );
    expect(find.byTooltip('Yönetim'), findsOneWidget);
    expect(find.byTooltip('Ara'), findsOneWidget);
    expect(find.byTooltip('Bugüne dön'), findsOneWidget);

    await tester.tap(find.byTooltip('Yönetim'));
    await tester.pumpAndSettle();
    expect(find.text('Hizmetler'), findsOneWidget);
  });
}

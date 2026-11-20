import 'package:flutter_test/flutter_test.dart';
import 'package:remedy_track/models/inventory_item.dart';

void main() {
  group('Inventory Item Depletion & Run-Out Math Tests', () {
    test('isLowStock triggers when current stock is at or below threshold', () {
      const itemLow = InventoryItem(
        id: '1',
        userId: 'u1',
        medicationId: 'm1',
        currentStock: 8.0,
        lowStockThreshold: 10.0,
      );

      const itemExact = InventoryItem(
        id: '2',
        userId: 'u1',
        medicationId: 'm1',
        currentStock: 10.0,
        lowStockThreshold: 10.0,
      );

      const itemSafe = InventoryItem(
        id: '3',
        userId: 'u1',
        medicationId: 'm1',
        currentStock: 25.0,
        lowStockThreshold: 10.0,
      );

      expect(itemLow.isLowStock, isTrue);
      expect(itemExact.isLowStock, isTrue);
      expect(itemSafe.isLowStock, isFalse);
    });

    test(
        'estimatedDaysRemaining accurately computes days based on daily consumption rate',
        () {
      const item = InventoryItem(
        id: '1',
        userId: 'u1',
        medicationId: 'm1',
        currentStock: 30.0,
        lowStockThreshold: 10.0,
      );

      // Consuming 2 pills/day -> 15 days
      expect(item.estimatedDaysRemaining(2.0), 15);

      // Consuming 3 pills/day -> 10 days
      expect(item.estimatedDaysRemaining(3.0), 10);

      // Consuming 4 pills/day -> 7 days (floor of 7.5)
      expect(item.estimatedDaysRemaining(4.0), 7);

      // Zero or negative consumption returns null
      expect(item.estimatedDaysRemaining(0.0), isNull);
    });
  });
}

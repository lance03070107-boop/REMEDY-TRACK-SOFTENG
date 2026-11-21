import 'dart:async';
import 'package:remedy_track/models/dose_schedule.dart';
import 'package:remedy_track/models/intake_log.dart';
import 'package:remedy_track/models/inventory_item.dart';
import 'package:remedy_track/models/medication.dart';
import 'package:remedy_track/models/user_profile.dart';
import 'mock_caregiver_repository.dart';
export 'mock_caregiver_repository.dart';
import 'package:remedy_track/repositories/intake_repository.dart';
import 'package:remedy_track/repositories/inventory_repository.dart';
import 'package:remedy_track/repositories/medication_repository.dart';
import 'package:remedy_track/repositories/user_repository.dart';

/// Pre-seeded offline mock repositories compliant with RA 10173.
/// Enables full functional offline development, testing, and zero-configuration launch.
class MockRepositories {
  static const String defaultUserId = 'patient_local_01';
  static const String defaultUserEmail = '';
  static const String defaultUserName = '';

  static final MockRepositories instance = MockRepositories._internal();

  late final MockMedicationRepository medicationRepository;
  late final MockIntakeRepository intakeRepository;
  late final MockInventoryRepository inventoryRepository;
  late final MockUserRepository userRepository;
  late final MockCaregiverRepository caregiverRepository;

  MockRepositories._internal() {
    inventoryRepository = MockInventoryRepository();
    intakeRepository = MockIntakeRepository(inventoryRepository);
    medicationRepository = MockMedicationRepository();
    userRepository = MockUserRepository();
    caregiverRepository = MockCaregiverRepository();
    _seedData();
  }

  void _seedData() {
    final now = DateTime.now();

    // Zero hardcoded mock user accounts or emails pre-seeded.
    // User profile is created upon authenticating or signing in.

    // 2. Seed Medications
    final amox = Medication(
      id: 'med_amox',
      userId: defaultUserId,
      name: 'Amoxicillin',
      genericName: 'Amoxicillin Trihydrate',
      strength: '500 mg',
      form: MedicationForm.capsule,
      doseAmount: 1.0,
      instructions: 'Take 1 capsule after meals with a full glass of water',
      notes: 'Complete the full 7-day prescribed antibiotic course.',
      colorTag: 0xFF1E66F5, // Catppuccin Blue
      schedule: DoseSchedule(
        frequency: ScheduleFrequency.daily,
        timesOfDay: const ['08:00', '13:00', '19:00'],
        startDate: now.subtract(const Duration(days: 3)),
      ),
      isPrn: false,
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(days: 3)),
    );

    final atorva = Medication(
      id: 'med_atorva',
      userId: defaultUserId,
      name: 'Atorvastatin',
      genericName: 'Atorvastatin Calcium',
      strength: '20 mg',
      form: MedicationForm.tablet,
      doseAmount: 1.0,
      instructions: 'Take 1 tablet at bedtime',
      notes: 'For lipid/cholesterol management',
      colorTag: 0xFF8839EF, // Catppuccin Mauve
      schedule: DoseSchedule(
        frequency: ScheduleFrequency.daily,
        timesOfDay: const ['21:00'],
        startDate: now.subtract(const Duration(days: 14)),
      ),
      isPrn: false,
      createdAt: now.subtract(const Duration(days: 14)),
      updatedAt: now.subtract(const Duration(days: 14)),
    );

    final losartan = Medication(
      id: 'med_losartan',
      userId: defaultUserId,
      name: 'Losartan Potassium',
      genericName: 'Losartan',
      strength: '50 mg',
      form: MedicationForm.tablet,
      doseAmount: 1.0,
      instructions: 'Take 1 tablet every morning',
      notes: 'Blood pressure control',
      colorTag: 0xFF179299, // Catppuccin Teal
      schedule: DoseSchedule(
        frequency: ScheduleFrequency.daily,
        timesOfDay: const ['07:00'],
        startDate: now.subtract(const Duration(days: 30)),
      ),
      isPrn: false,
      createdAt: now.subtract(const Duration(days: 30)),
      updatedAt: now.subtract(const Duration(days: 30)),
    );

    final paracetamol = Medication(
      id: 'med_paracetamol',
      userId: defaultUserId,
      name: 'Paracetamol',
      genericName: 'Acetaminophen',
      strength: '500 mg',
      form: MedicationForm.tablet,
      doseAmount: 1.0,
      instructions: 'Take for fever or pain every 4 to 6 hours as needed',
      notes: 'Do not exceed 8 tablets in 24 hours.',
      colorTag: 0xFFDF8E1D, // Catppuccin Yellow
      schedule: null,
      isPrn: true,
      minIntervalHours: 4,
      dailyMaxDose: 8.0,
      createdAt: now.subtract(const Duration(days: 60)),
      updatedAt: now.subtract(const Duration(days: 60)),
    );

    medicationRepository.seedMedications([amox, atorva, losartan, paracetamol]);

    // 4. Seed Inventory
    inventoryRepository.seedInventory([
      InventoryItem(
        id: 'inv_amox',
        medicationId: 'med_amox',
        userId: defaultUserId,
        currentStock: 18.0,
        lowStockThreshold: 6.0,
        unit: 'capsules',
        lastRefillDate: now.subtract(const Duration(days: 3)),
      ),
      InventoryItem(
        id: 'inv_atorva',
        medicationId: 'med_atorva',
        userId: defaultUserId,
        currentStock: 25.0,
        lowStockThreshold: 5.0,
        unit: 'tablets',
        lastRefillDate: now.subtract(const Duration(days: 14)),
      ),
      InventoryItem(
        id: 'inv_losartan',
        medicationId: 'med_losartan',
        userId: defaultUserId,
        currentStock: 3.0, // Low stock triggered!
        lowStockThreshold: 7.0,
        unit: 'tablets',
        lastRefillDate: now.subtract(const Duration(days: 30)),
      ),
      InventoryItem(
        id: 'inv_paracetamol',
        medicationId: 'med_paracetamol',
        userId: defaultUserId,
        currentStock: 16.0,
        lowStockThreshold: 4.0,
        unit: 'tablets',
        lastRefillDate: now.subtract(const Duration(days: 20)),
      ),
    ]);

    // 5. Seed Intake Logs (Past 7 days + today)
    final logs = <IntakeLog>[];

    // Today's morning doses: Losartan (Taken) & Amoxicillin (Taken)
    logs.add(
      IntakeLog(
        id: 'log_today_losartan',
        medicationId: 'med_losartan',
        medicationName: 'Losartan Potassium',
        userId: defaultUserId,
        scheduledTime: DateTime(now.year, now.month, now.day, 7, 0),
        recordedTime: DateTime(now.year, now.month, now.day, 7, 10),
        status: DoseStatus.taken,
        doseAmount: 1.0,
      ),
    );
    logs.add(
      IntakeLog(
        id: 'log_today_amox_morning',
        medicationId: 'med_amox',
        medicationName: 'Amoxicillin',
        userId: defaultUserId,
        scheduledTime: DateTime(now.year, now.month, now.day, 8, 0),
        recordedTime: DateTime(now.year, now.month, now.day, 8, 25),
        status: DoseStatus.taken,
        doseAmount: 1.0,
      ),
    );

    // Past 6 days logs to show solid adherence streak
    for (int i = 1; i <= 6; i++) {
      final day = now.subtract(Duration(days: i));
      logs.add(
        IntakeLog(
          id: 'log_day_${i}_losartan',
          medicationId: 'med_losartan',
          medicationName: 'Losartan Potassium',
          userId: defaultUserId,
          scheduledTime: DateTime(day.year, day.month, day.day, 7, 0),
          recordedTime: DateTime(day.year, day.month, day.day, 7, 15),
          status: DoseStatus.taken,
          doseAmount: 1.0,
        ),
      );
      logs.add(
        IntakeLog(
          id: 'log_day_${i}_atorva',
          medicationId: 'med_atorva',
          medicationName: 'Atorvastatin',
          userId: defaultUserId,
          scheduledTime: DateTime(day.year, day.month, day.day, 21, 0),
          recordedTime: DateTime(day.year, day.month, day.day, 21, 30),
          status: DoseStatus.taken,
          doseAmount: 1.0,
        ),
      );
      logs.add(
        IntakeLog(
          id: 'log_day_${i}_amox_1',
          medicationId: 'med_amox',
          medicationName: 'Amoxicillin',
          userId: defaultUserId,
          scheduledTime: DateTime(day.year, day.month, day.day, 8, 0),
          recordedTime: DateTime(day.year, day.month, day.day, 8, 20),
          status: DoseStatus.taken,
          doseAmount: 1.0,
        ),
      );
      logs.add(
        IntakeLog(
          id: 'log_day_${i}_amox_2',
          medicationId: 'med_amox',
          medicationName: 'Amoxicillin',
          userId: defaultUserId,
          scheduledTime: DateTime(day.year, day.month, day.day, 13, 0),
          recordedTime: DateTime(day.year, day.month, day.day, 13, 40),
          status: i == 3 ? DoseStatus.late : DoseStatus.taken,
          doseAmount: 1.0,
        ),
      );
      logs.add(
        IntakeLog(
          id: 'log_day_${i}_amox_3',
          medicationId: 'med_amox',
          medicationName: 'Amoxicillin',
          userId: defaultUserId,
          scheduledTime: DateTime(day.year, day.month, day.day, 19, 0),
          recordedTime: DateTime(day.year, day.month, day.day, 19, 15),
          status: DoseStatus.taken,
          doseAmount: 1.0,
        ),
      );
    }

    intakeRepository.seedLogs(logs);
  }
}

/// In-memory Mock implementation of MedicationRepository.
class MockMedicationRepository implements MedicationRepository {
  final List<Medication> _items = [];
  final StreamController<List<Medication>> _controller =
      StreamController<List<Medication>>.broadcast();

  void seedMedications(List<Medication> items) {
    _items.clear();
    _items.addAll(items);
    _controller.add(List.unmodifiable(_items));
  }

  @override
  Stream<List<Medication>> streamMedications(String userId) {
    return _controller.stream;
  }

  @override
  Future<List<Medication>> getMedications(String userId) async {
    final matches = _items.where((m) => m.userId == userId).toList();
    return matches.isNotEmpty ? matches : _items;
  }

  @override
  Future<Medication?> getMedicationById(String id) async {
    try {
      return _items.firstWhere((m) => m.id == id);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> addMedication(Medication medication) async {
    _items.add(medication);
    _controller.add(List.unmodifiable(_items));
  }

  @override
  Future<void> updateMedication(Medication medication) async {
    final idx = _items.indexWhere((m) => m.id == medication.id);
    if (idx != -1) {
      _items[idx] = medication;
      _controller.add(List.unmodifiable(_items));
    }
  }

  @override
  Future<void> saveMedicationWithInventory({
    required Medication medication,
    required InventoryItem inventoryItem,
  }) async {
    final idx = _items.indexWhere((m) => m.id == medication.id);
    if (idx != -1) {
      _items[idx] = medication;
    } else {
      _items.add(medication);
    }
    _controller.add(List.unmodifiable(_items));
  }

  @override
  Future<void> deleteMedication(String id) async {
    _items.removeWhere((m) => m.id == id);
    _controller.add(List.unmodifiable(_items));
  }
}

/// In-memory Mock implementation of InventoryRepository.
class MockInventoryRepository implements InventoryRepository {
  final List<InventoryItem> _items = [];
  final StreamController<List<InventoryItem>> _controller =
      StreamController<List<InventoryItem>>.broadcast();

  void seedInventory(List<InventoryItem> items) {
    _items.clear();
    _items.addAll(items);
    _controller.add(List.unmodifiable(_items));
  }

  @override
  Stream<List<InventoryItem>> streamInventory(String userId) {
    return _controller.stream;
  }

  @override
  Future<List<InventoryItem>> getInventory(String userId) async {
    final matches = _items.where((item) => item.userId == userId).toList();
    return matches.isNotEmpty ? matches : _items;
  }

  @override
  Future<InventoryItem?> getInventoryByMedicationId(
      String userId, String medicationId) async {
    try {
      return _items.firstWhere((item) => item.medicationId == medicationId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> setInventoryItem(InventoryItem item) async {
    final idx = _items.indexWhere((i) => i.id == item.id);
    if (idx != -1) {
      _items[idx] = item;
    } else {
      _items.add(item);
    }
    _controller.add(List.unmodifiable(_items));
  }

  @override
  Future<void> refillStock(
    String itemId,
    double additionalAmount, {
    String? requestId,
  }) async {
    final idx = _items.indexWhere((i) => i.id == itemId);
    if (idx != -1) {
      final current = _items[idx];
      _items[idx] = current.copyWith(
        currentStock: current.currentStock + additionalAmount,
        lastRefillDate: DateTime.now(),
      );
      _controller.add(List.unmodifiable(_items));
    }
  }

  @override
  Future<void> deleteInventoryItem(String itemId) async {
    _items.removeWhere((i) => i.id == itemId);
    _controller.add(List.unmodifiable(_items));
  }

  void decrementStockForMedication(String medicationId, double amount) {
    final idx = _items.indexWhere((i) => i.medicationId == medicationId);
    if (idx != -1) {
      final current = _items[idx];
      final newStock =
          (current.currentStock - amount).clamp(0.0, double.infinity);
      _items[idx] = current.copyWith(
        currentStock: newStock,
      );
      _controller.add(List.unmodifiable(_items));
    }
  }
}

/// In-memory Mock implementation of IntakeRepository.
class MockIntakeRepository implements IntakeRepository {
  final MockInventoryRepository _inventoryRepo;
  final List<IntakeLog> _logs = [];
  final StreamController<List<IntakeLog>> _controller =
      StreamController<List<IntakeLog>>.broadcast();

  MockIntakeRepository(this._inventoryRepo);

  void seedLogs(List<IntakeLog> logs) {
    _logs.clear();
    _logs.addAll(logs);
    _controller.add(List.unmodifiable(_logs));
  }

  @override
  Stream<List<IntakeLog>> streamIntakeLogs(String userId, {int limit = 500}) {
    return _controller.stream.map((list) => list.take(limit).toList());
  }

  @override
  Future<List<IntakeLog>> getIntakeLogs(String userId,
      {int limit = 500}) async {
    final matches = _logs.where((l) => l.userId == userId).toList();
    final res = matches.isNotEmpty ? matches : _logs;
    return res.take(limit).toList();
  }

  @override
  Future<List<IntakeLog>> getLogsForDateRange(
      String userId, DateTime start, DateTime end) async {
    final matchingUser = _logs.where((l) => l.userId == userId).toList();
    final candidateLogs = matchingUser.isNotEmpty ? matchingUser : _logs;
    return candidateLogs
        .where((l) =>
            (l.scheduledTime.isAfter(start) ||
                l.scheduledTime.isAtSameMomentAs(start)) &&
            (l.scheduledTime.isBefore(end) ||
                l.scheduledTime.isAtSameMomentAs(end)))
        .toList();
  }

  @override
  Future<void> recordIntakeAtomic({
    required IntakeLog intakeLog,
    required bool decrementInventory,
  }) async {
    final idx = _logs.indexWhere((l) => l.id == intakeLog.id);
    final previousStatus = idx != -1 ? _logs[idx].status : null;

    // Terminal state protection (B1):
    // An already taken or late dose cannot be overwritten by missed, skipped, or snoozed.
    if (previousStatus != null &&
        (previousStatus == DoseStatus.taken ||
            previousStatus == DoseStatus.late)) {
      if (intakeLog.status == DoseStatus.missed ||
          intakeLog.status == DoseStatus.skipped ||
          intakeLog.status == DoseStatus.snoozed) {
        return; // Guard against reconciler race condition overwriting taken log
      }
    }

    if (previousStatus == DoseStatus.skipped) {
      if (intakeLog.status == DoseStatus.missed ||
          intakeLog.status == DoseStatus.snoozed) {
        return;
      }
    }

    if (idx != -1) {
      _logs[idx] = intakeLog;
    } else {
      _logs.insert(0, intakeLog);
    }

    // Idempotency guard: Only decrement inventory if this dose has NOT already been marked as taken or late!
    if (decrementInventory &&
        previousStatus != DoseStatus.taken &&
        previousStatus != DoseStatus.late) {
      _inventoryRepo.decrementStockForMedication(
        intakeLog.medicationId,
        intakeLog.doseAmount,
      );
    }

    _controller.add(List.unmodifiable(_logs));
  }

  @override
  Future<void> undoTakeDoseAtomic({
    required IntakeLog intakeLog,
    required bool restoreInventory,
  }) async {
    final idx = _logs.indexWhere((l) => l.id == intakeLog.id);
    if (idx == -1) return;
    final existingStatus = _logs[idx].status;
    _logs.removeAt(idx);

    // B3: Inventory Inflation Guard: Only restore inventory if existing dose was actually taken or late
    final wasTaken =
        existingStatus == DoseStatus.taken || existingStatus == DoseStatus.late;
    if (restoreInventory && wasTaken) {
      _inventoryRepo.decrementStockForMedication(
        intakeLog.medicationId,
        -intakeLog.doseAmount,
      );
    }
    _controller.add(List.unmodifiable(_logs));
  }

  @override
  Future<void> updateLogStatus(String logId, DoseStatus status) async {
    final idx = _logs.indexWhere((l) => l.id == logId);
    if (idx != -1) {
      _logs[idx] = _logs[idx].copyWith(status: status);
      _controller.add(List.unmodifiable(_logs));
    }
  }

  @override
  Future<void> deleteIntakeLog(String logId) async {
    _logs.removeWhere((l) => l.id == logId);
    _controller.add(List.unmodifiable(_logs));
  }

  @override
  Future<int> deleteAllIntakeLogs(String userId) async {
    final before = _logs.length;
    _logs.removeWhere((l) => l.userId == userId || userId.isEmpty);
    final deleted = before - _logs.length;
    _controller.add(List.unmodifiable(_logs));
    return deleted;
  }
}

/// In-memory Mock implementation of UserRepository.
class MockUserRepository implements UserRepository {
  UserProfile? _profile;

  void seedProfile(UserProfile profile) {
    _profile = profile;
  }

  @override
  Future<UserProfile?> getUserProfile(String userId) async {
    return _profile;
  }

  @override
  Future<void> saveUserProfile(UserProfile profile) async {
    _profile = profile;
  }

  @override
  Future<void> deleteAllUserData(String userId) async {
    _profile = null;
  }
}

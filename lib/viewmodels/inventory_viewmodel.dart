import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/constants/app_constants.dart';
import '../core/errors/app_exception.dart';
import '../core/errors/error_mapper.dart';
import '../core/utils/app_logger.dart';
import '../core/utils/result.dart';
import '../core/validation/medication_validator.dart';
import '../models/inventory_item.dart';
import '../models/medication.dart';
import '../repositories/inventory_repository.dart';
import '../services/alarm_id_generator.dart';
import '../services/crashlytics_service.dart';
import '../services/local_medication_cache.dart';
import '../services/notification_service.dart';

class InventoryViewModel extends ChangeNotifier {
  final InventoryRepository _inventoryRepository;
  final NotificationService _notificationService;
  final String? Function(String medicationId)? _resolveMedicationName;
  final Set<String> _notifiedLowStockItemIds = <String>{};
  final Set<String> _inFlightRefillItemIds = <String>{};
  bool _notifiedIdsLoaded = false;

  StreamSubscription<List<InventoryItem>>? _invSubscription;
  String? _activeUserId;
  bool _isOwnProfile = true;
  List<InventoryItem> _inventoryItems = [];
  bool _isLoading = false;
  String? _errorMessage;

  InventoryViewModel({
    required InventoryRepository inventoryRepository,
    NotificationService? notificationService,
    String? Function(String medicationId)? resolveMedicationName,
  })  : _inventoryRepository = inventoryRepository,
        _notificationService = notificationService ?? NotificationService(),
        _resolveMedicationName = resolveMedicationName;

  List<InventoryItem> get inventoryItems => _inventoryItems;
  List<InventoryItem> get lowStockItems =>
      _inventoryItems.where((item) => item.isLowStock).toList();
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;
  bool get isEmpty => _inventoryItems.isEmpty;
  bool get hasError => _errorMessage != null;
  bool isRefillingItem(String itemId) => _inFlightRefillItemIds.contains(itemId);

  void clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  /// Cancels active Firestore stream and clears in-memory state on sign-out or account switch.
  void resetState() {
    _invSubscription?.cancel();
    _invSubscription = null;
    _activeUserId = null;
    _isOwnProfile = true;
    _inventoryItems = [];
    _notifiedLowStockItemIds.clear();
    _inFlightRefillItemIds.clear();
    _notifiedIdsLoaded = false;
    _isLoading = false;
    _errorMessage = null;
    notifyListeners();
  }

  void retry(String userId) => listenToInventory(
        userId,
        forceReload: true,
        isOwnProfile: _isOwnProfile,
      );

  Future<void> _ensureNotifiedIdsLoaded() async {
    if (_notifiedIdsLoaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored =
          prefs.getStringList(AppConstants.keyNotifiedLowStockIds) ?? const [];
      _notifiedLowStockItemIds.addAll(stored);
      _notifiedIdsLoaded = true;
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack));
    }
  }

  Future<void> _persistNotifiedIds() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(
        AppConstants.keyNotifiedLowStockIds,
        _notifiedLowStockItemIds.toList(),
      );
    } catch (e, stack) {
      unawaited(CrashlyticsService.recordError(e, stack));
    }
  }

  void listenToInventory(
    String userId, {
    bool forceReload = false,
    bool isOwnProfile = true,
  }) {
    if (userId.isEmpty) return;
    if (!forceReload &&
        _activeUserId == userId &&
        _isOwnProfile == isOwnProfile &&
        _invSubscription != null &&
        !_isLoading &&
        _errorMessage == null) {
      return;
    }

    if (_activeUserId != null && _activeUserId != userId) {
      _inventoryItems = [];
      _notifiedLowStockItemIds.clear();
      _inFlightRefillItemIds.clear();
      _notifiedIdsLoaded = false;
      _errorMessage = null;
    }

    _activeUserId = userId;
    _isOwnProfile = isOwnProfile;
    _invSubscription?.cancel();
    _isLoading = true;
    notifyListeners();

    _invSubscription = _inventoryRepository.streamInventory(userId).listen(
      (items) {
        // Assign synchronously before any async work so out-of-order callbacks
        // can never overwrite newer snapshots with stale ones.
        _inventoryItems = items;
        _isLoading = false;
        _errorMessage = null;
        notifyListeners();
        unawaited(_evaluateLowStockNotifications(userId, items));
      },
      onError: (Object e, StackTrace s) async {
        final mapped = ErrorMapper.map(e, s);
        if (mapped is! PermissionException && mapped is! AuthException) {
          try {
            final cached = await _inventoryRepository.getInventory(userId);
            _inventoryItems = cached;
            _isLoading = false;
            _errorMessage = null;
            notifyListeners();
            return;
          } catch (cacheErr, cacheStack) {
            AppLogger.w('Inventory cache fallback failed: $cacheErr',
                tag: 'InventoryVM', error: cacheErr, stackTrace: cacheStack);
          }
        }
        _errorMessage = mapped.message;
        _isLoading = false;
        unawaited(CrashlyticsService.recordError(e, s));
        notifyListeners();
      },
    );
  }

  Future<void> _evaluateLowStockNotifications(
    String userId,
    List<InventoryItem> items,
  ) async {
    await _ensureNotifiedIdsLoaded();
    if (_activeUserId != userId) return;

    bool effectiveOwnProfile = _isOwnProfile;
    if (effectiveOwnProfile) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final ownUid = prefs.getString('remedy_active_user_id') ?? '';
        if (ownUid.isNotEmpty && ownUid != userId) {
          effectiveOwnProfile = false;
        }
      } catch (_) {}
    }
    if (!effectiveOwnProfile) return;

    Map<String, String>? cachedNamesByMedId;
    bool changedNotifiedSet = false;
    for (final item in items) {
      if (item.isLowStock) {
        if (!_notifiedLowStockItemIds.contains(item.id)) {
          _notifiedLowStockItemIds.add(item.id);
          changedNotifiedSet = true;

          String? medName = _resolveMedicationName?.call(item.medicationId);
          if (medName == null || medName.trim().isEmpty) {
            cachedNamesByMedId ??= await _loadCachedMedNames();
            medName = cachedNamesByMedId[item.medicationId];
          }
          final displayMedName = (medName != null && medName.trim().isNotEmpty)
              ? medName.trim()
              : ((item.notes != null && item.notes!.trim().isNotEmpty)
                  ? item.notes!.trim()
                  : 'Medication');

          unawaited(
            _notificationService.showLowStockAlert(
              notificationId:
                  AlarmIdGenerator.generateLowStockNotificationId(item.id),
              medicationName: displayMedName,
              currentStock: item.currentStock,
              unit: item.unit,
              threshold: item.lowStockThreshold,
            ),
          );
        }
      } else {
        if (_notifiedLowStockItemIds.remove(item.id)) {
          changedNotifiedSet = true;
        }
      }
    }
    if (changedNotifiedSet) {
      unawaited(_persistNotifiedIds());
    }
  }

  Future<Map<String, String>> _loadCachedMedNames() async {
    try {
      final cachedMeds = await LocalMedicationCache.loadMedications();
      return {
        for (final m in cachedMeds)
          if (m.id.isNotEmpty && m.name.trim().isNotEmpty) m.id: m.name.trim(),
      };
    } catch (_) {
      return const {};
    }
  }

  /// Creates or replaces an [InventoryItem] after validating clinical bounds.
  Future<Result<void>> setupInventoryItem(
    InventoryItem item, {
    MedicationForm? form,
  }) async {
    final validation =
        MedicationValidator.validateInventoryItemModel(item, form: form);
    if (validation.isFailure) {
      _errorMessage = validation.errorOrNull!.message;
      notifyListeners();
      return validation;
    }

    try {
      await _inventoryRepository.setInventoryItem(item);
      final idx = _inventoryItems.indexWhere((i) => i.id == item.id);
      if (idx != -1) {
        _inventoryItems = List<InventoryItem>.from(_inventoryItems)
          ..[idx] = item;
      } else {
        _inventoryItems = [..._inventoryItems, item];
      }
      _errorMessage = null;
      notifyListeners();
      return const Success(null);
    } catch (e, stack) {
      final mapped = ErrorMapper.map(e, stack);
      _errorMessage = mapped.message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      return Failure(mapped);
    }
  }

  Future<Result<void>> refillItem(
    String itemId,
    double additionalStock, {
    MedicationForm? form,
  }) async {
    if (additionalStock.isNaN ||
        additionalStock.isInfinite ||
        additionalStock <= 0 ||
        additionalStock > AppConstants.maxStock) {
      final err = ValidationException(
        'Enter a refill amount greater than 0 and up to ${AppConstants.maxStock.toInt()}.',
      );
      _errorMessage = err.message;
      notifyListeners();
      return Failure(err);
    }

    final index = _inventoryItems.indexWhere((i) => i.id == itemId);
    if (index == -1) {
      const err = InventoryException(
        'Stock is not set up for this medication yet. Set up stock first.',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    final current = _inventoryItems[index];
    if (form != null &&
        !MedicationValidator.allowsDecimalStock(form) &&
        additionalStock != additionalStock.roundToDouble()) {
      final err = ValidationException(
        'Refill amount for ${MedicationValidator.unitForForm(form)} must be a whole number.',
      );
      _errorMessage = err.message;
      notifyListeners();
      return Failure(err);
    }

    if (current.currentStock + additionalStock > AppConstants.maxStock + 1e-6) {
      final err = ValidationException(
        'Total stock cannot exceed ${AppConstants.maxStock.toInt()} ${current.unit}.',
      );
      _errorMessage = err.message;
      notifyListeners();
      return Failure(err);
    }

    if (_inFlightRefillItemIds.contains(itemId)) {
      return const Success(null);
    }
    _inFlightRefillItemIds.add(itemId);
    final requestId = '${itemId}_${DateTime.now().microsecondsSinceEpoch}';
    try {
      await _inventoryRepository.refillStock(
        itemId,
        additionalStock,
        requestId: requestId,
      );
      final updated = current.copyWith(
        currentStock: current.currentStock + additionalStock,
        lastRefillDate: DateTime.now(),
      );
      _inventoryItems = List<InventoryItem>.from(_inventoryItems)
        ..[index] = updated;
      if (!updated.isLowStock && _notifiedLowStockItemIds.remove(updated.id)) {
        unawaited(_persistNotifiedIds());
      }
      _errorMessage = null;
      notifyListeners();
      return const Success(null);
    } catch (e, stack) {
      final mapped = ErrorMapper.map(e, stack);
      _errorMessage = mapped.message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      return Failure(mapped);
    } finally {
      _inFlightRefillItemIds.remove(itemId);
    }
  }

  Future<Result<void>> updateInventoryDetails({
    required String itemId,
    required double currentStock,
    required double lowStockThreshold,
    MedicationForm? form,
  }) async {
    final index = _inventoryItems.indexWhere((i) => i.id == itemId);
    if (index == -1) {
      const err = InventoryException(
        'Stock is not set up for this medication yet. Set up stock first.',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    final updated = _inventoryItems[index].copyWith(
      currentStock: currentStock,
      lowStockThreshold: lowStockThreshold,
    );
    final validation =
        MedicationValidator.validateInventoryItemModel(updated, form: form);
    if (validation.isFailure) {
      _errorMessage = validation.errorOrNull!.message;
      notifyListeners();
      return validation;
    }

    try {
      await _inventoryRepository.setInventoryItem(updated);
      _inventoryItems = List<InventoryItem>.from(_inventoryItems)
        ..[index] = updated;
      if (!updated.isLowStock && _notifiedLowStockItemIds.remove(updated.id)) {
        unawaited(_persistNotifiedIds());
      }
      _errorMessage = null;
      notifyListeners();
      return const Success(null);
    } catch (e, stack) {
      final mapped = ErrorMapper.map(e, stack);
      _errorMessage = mapped.message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      return Failure(mapped);
    }
  }

  Future<Result<void>> updateThreshold(
    String itemId,
    double newThreshold, {
    MedicationForm? form,
  }) async {
    final index = _inventoryItems.indexWhere((i) => i.id == itemId);
    if (index == -1) {
      const err = InventoryException(
        'Stock is not set up for this medication yet. Set up stock first.',
      );
      _errorMessage = err.message;
      notifyListeners();
      return const Failure(err);
    }

    final updated =
        _inventoryItems[index].copyWith(lowStockThreshold: newThreshold);
    final validation =
        MedicationValidator.validateInventoryItemModel(updated, form: form);
    if (validation.isFailure) {
      _errorMessage = validation.errorOrNull!.message;
      notifyListeners();
      return validation;
    }

    try {
      await _inventoryRepository.setInventoryItem(updated);
      _inventoryItems = List<InventoryItem>.from(_inventoryItems)
        ..[index] = updated;
      _errorMessage = null;
      notifyListeners();
      return const Success(null);
    } catch (e, stack) {
      final mapped = ErrorMapper.map(e, stack);
      _errorMessage = mapped.message;
      unawaited(CrashlyticsService.recordError(e, stack));
      notifyListeners();
      return Failure(mapped);
    }
  }

  /// Optimistically decrements or restores in-memory inventory stock for immediate offline UI updates.
  void adjustLocalStock(String medicationId, double delta) {
    final itemId = 'inv_$medicationId';
    final index = _inventoryItems
        .indexWhere((i) => i.id == itemId || i.medicationId == medicationId);
    if (index == -1) return;
    final current = _inventoryItems[index];
    final nextStock = (current.currentStock + delta)
        .clamp(AppConstants.minStock, AppConstants.maxStock);
    final updated = current.copyWith(currentStock: nextStock);
    _inventoryItems = List<InventoryItem>.from(_inventoryItems)
      ..[index] = updated;
    notifyListeners();
  }

  @override
  void dispose() {
    _invSubscription?.cancel();
    super.dispose();
  }
}

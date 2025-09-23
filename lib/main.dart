import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:health_connect_calorie_app/permissions_page.dart';
import 'package:provider/provider.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:intl/intl.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';

void main() {
  runApp(
    ChangeNotifierProvider(
      create: (context) => HealthDataProvider(),
      child: MyApp(),
    ),
  );
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Health Connect Calorie Tracker',
      theme: ThemeData(
        primarySwatch: Colors.orange,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        // cardTheme: CardTheme(
        //   elevation: 4,
        //   margin: EdgeInsets.all(8),
        //   shape:
        //       RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        // ),
      ),
      home: FutureBuilder<bool>(
        future:
            Provider.of<HealthDataProvider>(context, listen: false).checkPermissions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return Scaffold(body: Center(child: CircularProgressIndicator()));
          } else if (snapshot.hasError) {
            return Scaffold(
                body: Center(child: Text('Error checking permissions')));
          } else if (snapshot.data == true) {
            return HealthConnectHomePage();
          } else {
            return PermissionsPage();
          }
        },
      ),
      debugShowCheckedModeBanner: false,
    );
  }
}

// Data model for calorie metrics
class CalorieMetrics {
  final double totalCalories;
  final double activeCalories;
  final int totalDataPoints;
  final DateTime lastUpdated;
  final Map<String, double> dailyBreakdown;

  CalorieMetrics({
    required this.totalCalories,
    required this.activeCalories,
    required this.totalDataPoints,
    required this.lastUpdated,
    required this.dailyBreakdown,
  });

  double get averageDailyCalories => dailyBreakdown.values.isEmpty
      ? 0
      : dailyBreakdown.values.reduce((a, b) => a + b) / dailyBreakdown.length;
}

// Health data provider for state management
class HealthDataProvider extends ChangeNotifier {
  static final Health _health = Health();

  // Health data types we want to access
  static final List<HealthDataType> _types = [
    HealthDataType.ACTIVE_ENERGY_BURNED,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.STEPS,
    HealthDataType.HEART_RATE,
  ];

  static final List<HealthDataAccess> _permissions =
      _types.map((type) => HealthDataAccess.READ_WRITE).toList();

  // State variables
  List<HealthDataPoint> _healthDataList = [];
  CalorieMetrics? _calorieMetrics;
  AppState _state = AppState.DATA_NOT_FETCHED;
  String _errorMessage = '';
  bool _hasPermissions = false;
  HealthConnectSdkStatus? _healthConnectStatus;

  // Getters
  List<HealthDataPoint> get healthDataList => _healthDataList;
  CalorieMetrics? get calorieMetrics => _calorieMetrics;
  AppState get state => _state;
  String get errorMessage => _errorMessage;
  bool get hasPermissions => _hasPermissions;
  HealthConnectSdkStatus? get healthConnectStatus => _healthConnectStatus;

  // Check Health Connect availability
  Future<void> checkHealthConnectStatus() async {
    if (Platform.isAndroid) {
      try {
        _healthConnectStatus = await _health.getHealthConnectSdkStatus();
        notifyListeners();
      } catch (e) {
        print('Error checking Health Connect status: $e');
      }
    }
  }

  // Install Health Connect if needed
  Future<void> installHealthConnect() async {
    if (Platform.isAndroid) {
      try {
        await _health.installHealthConnect();
      } catch (e) {
        _setError('Failed to install Health Connect: $e',
            newState: AppState.ERROR);
      }
    }
  }

  // Check if permissions are already granted
  Future<bool> checkPermissions() async {
    if (Platform.isAndroid) {
      final activityStatus = await Permission.activityRecognition.status;
      if (!activityStatus.isGranted) {
        return false;
      }

      final locationStatus = await Permission.locationWhenInUse.status;
      if (!locationStatus.isGranted) {
        return false;
      }
    }

    bool? hasPermissions =
        await _health.hasPermissions(_types, permissions: _permissions);

    _hasPermissions = hasPermissions ?? false;
    return _hasPermissions;
  }

  // Request all necessary permissions
  Future<bool> requestPermissions() async {
    _setState(AppState.REQUESTING_PERMISSIONS);

    try {
      // Request traditional Android permissions first
      if (Platform.isAndroid) {
        final activityStatus = await Permission.activityRecognition.request();
        if (activityStatus.isDenied || activityStatus.isPermanentlyDenied) {
          _setError(
              'Activity Recognition permission is required to track workouts. Please grant it in the app settings.',
              newState: AppState.PERMISSIONS_DENIED);
          return false;
        }

        final locationStatus = await Permission.locationWhenInUse.request();
        if (locationStatus.isDenied || locationStatus.isPermanentlyDenied) {
          _setError(
              'Location permission is required to track distance. Please grant it in the app settings.',
              newState: AppState.PERMISSIONS_DENIED);
          return false;
        }
      }

      // Check if Health Connect permissions are already granted
      bool? hasPermissions =
          await _health.hasPermissions(_types, permissions: _permissions);

      if (hasPermissions == true) {
        _hasPermissions = true;
        _setState(AppState.PERMISSIONS_GRANTED);
        return true;
      }

      // Request Health Connect permissions
      bool authorized =
          await _health.requestAuthorization(_types, permissions: _permissions);

      if (authorized) {
        // Request additional permissions for comprehensive access
        try {
          await _health.requestHealthDataHistoryAuthorization();
          await _health.requestHealthDataInBackgroundAuthorization();
        } catch (e) {
          print('Optional permissions not granted: $e');
        }

        _hasPermissions = true;
        _setState(AppState.PERMISSIONS_GRANTED);
        return true;
      } else {
        _hasPermissions = false;
        _setError(
            'Health Connect permissions were denied. Please grant them in the Health Connect app.',
            newState: AppState.PERMISSIONS_DENIED);
        return false;
      }
    } catch (error) {
      _hasPermissions = false;
      _setError('Permission request failed: $error', newState: AppState.ERROR);
      return false;
    }
  }

  // Fetch health data from Health Connect
  Future<void> fetchHealthData() async {
    if (!_hasPermissions) {
      _setError(
          'Permissions not granted. Please authorize Health Connect access first.',
          newState: AppState.PERMISSIONS_DENIED);
      return;
    }

    _setState(AppState.FETCHING_DATA);

    try {
      // Fetch data for the last 7 days
      final now = DateTime.now();
      final startTime = now.subtract(Duration(days: 7));

      // Get health data with timeout
      final healthData = await _health
          .getHealthDataFromTypes(
            types: _types,
            startTime: startTime,
            endTime: now,
          )
          .timeout(Duration(seconds: 30));

      // Remove duplicates and process data
      _healthDataList = Health().removeDuplicates(healthData);
      _calorieMetrics = _processCalorieData(_healthDataList);

      if (_healthDataList.isEmpty) {
        _setState(AppState.NO_DATA);
      } else {
        _setState(AppState.DATA_READY);
      }
    } on TimeoutException {
      _setError(
          'Request timed out. Please check your connection and try again.',
          newState: AppState.ERROR);
    } on PlatformException catch (e) {
      if (e.message?.contains('Protected health data is inaccessible') ==
          true) {
        _setError('Device must be unlocked to access health data',
            newState: AppState.ERROR);
      } else {
        _setError('Platform error: ${e.message}', newState: AppState.ERROR);
      }
    } catch (error) {
      _setError('Failed to fetch health data: $error', newState: AppState.ERROR);
    }
  }

  // Process raw health data into calorie metrics
  CalorieMetrics _processCalorieData(List<HealthDataPoint> data) {
    double totalCalories = 0;
    double activeCalories = 0;
    Map<String, double> dailyBreakdown = {};

    for (var point in data) {
      if (point.type == HealthDataType.TOTAL_CALORIES_BURNED ||
          point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
        final value = (point.value as NumericHealthValue).numericValue;
        final dateKey = DateFormat('yyyy-MM-dd').format(point.dateFrom);

        if (point.type == HealthDataType.TOTAL_CALORIES_BURNED) {
          totalCalories += value;
        } else if (point.type == HealthDataType.ACTIVE_ENERGY_BURNED) {
          activeCalories += value;
        }

        // Add to daily breakdown
        dailyBreakdown[dateKey] = (dailyBreakdown[dateKey] ?? 0) + value;
      }
    }

    return CalorieMetrics(
      totalCalories: totalCalories,
      activeCalories: activeCalories,
      totalDataPoints: data.length,
      lastUpdated: DateTime.now(),
      dailyBreakdown: dailyBreakdown,
    );
  }

  // Helper methods for state management
  void _setState(AppState newState) {
    _state = newState;
    _errorMessage = '';
    notifyListeners();
  }

  void _setError(String error, {AppState newState = AppState.ERROR}) {
    _state = newState;
    _errorMessage = error;
    notifyListeners();
  }

  // Refresh data
  Future<void> refreshData() async {
    await fetchHealthData();
  }
}

// App state enumeration
enum AppState {
  DATA_NOT_FETCHED,
  REQUESTING_PERMISSIONS,
  PERMISSIONS_GRANTED,
  PERMISSIONS_DENIED,
  FETCHING_DATA,
  DATA_READY,
  NO_DATA,
  ERROR,
}

// Main home page widget
class HealthConnectHomePage extends StatefulWidget {
  @override
  _HealthConnectHomePageState createState() => _HealthConnectHomePageState();
}

class _HealthConnectHomePageState extends State<HealthConnectHomePage> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<HealthDataProvider>(context, listen: false)
          .checkHealthConnectStatus();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Calorie Data from Smartwatch'),
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          Consumer<HealthDataProvider>(
            builder: (context, provider, child) {
              if (provider.state == AppState.DATA_READY) {
                return IconButton(
                  icon: Icon(Icons.refresh),
                  onPressed: () => provider.refreshData(),
                );
              }
              return SizedBox.shrink();
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.orange.shade100, Colors.white],
          ),
        ),
        child: Consumer<HealthDataProvider>(
          builder: (context, provider, child) {
            return SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHealthConnectStatusCard(provider),
                  SizedBox(height: 16),
                  _buildMainActionButton(provider),
                  SizedBox(height: 16),
                  _buildContentArea(provider),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  // Health Connect status indicator
  Widget _buildHealthConnectStatusCard(HealthDataProvider provider) {
    if (!Platform.isAndroid) {
      return Card(
        child: ListTile(
          leading: Icon(Icons.info, color: Colors.blue),
          title: Text('iOS Device Detected'),
          subtitle:
              Text('Health Connect is Android-only. Use HealthKit on iOS.'),
        ),
      );
    }

    String statusText;
    Color statusColor;
    IconData statusIcon;

    switch (provider.healthConnectStatus) {
      case HealthConnectSdkStatus.sdkAvailable:
        statusText = 'Health Connect Available';
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case HealthConnectSdkStatus.sdkUnavailable:
        statusText = 'Health Connect Unavailable';
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired:
        statusText = 'Health Connect Update Required';
        statusColor = Colors.orange;
        statusIcon = Icons.system_update;
        break;
      default:
        statusText = 'Checking Health Connect Status...';
        statusColor = Colors.grey;
        statusIcon = Icons.hourglass_empty;
    }

    return Card(
      child: ListTile(
        leading: Icon(statusIcon, color: statusColor),
        title: Text('Health Connect Status'),
        subtitle: Text(statusText),
        trailing: provider.healthConnectStatus ==
                HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired
            ? TextButton(
                onPressed: () => provider.installHealthConnect(),
                child: Text('Install'),
              )
            : null,
      ),
    );
  }

  // Main action button
  Widget _buildMainActionButton(HealthDataProvider provider) {
    String buttonText;
    VoidCallback? onPressed;
    bool isLoading = false;

    switch (provider.state) {
      case AppState.DATA_NOT_FETCHED:
        buttonText = 'Connect to Health Connect';
        onPressed = () async {
          final success = await provider.requestPermissions();
          if (success) {
            provider.fetchHealthData();
          }
        };
        break;
      case AppState.REQUESTING_PERMISSIONS:
        buttonText = 'Requesting Permissions...';
        isLoading = true;
        break;
      case AppState.PERMISSIONS_GRANTED:
        buttonText = 'Fetch Calorie Data';
        onPressed = () => provider.fetchHealthData();
        break;
      case AppState.FETCHING_DATA:
        buttonText = 'Fetching Health Data...';
        isLoading = true;
        break;
      case AppState.DATA_READY:
        buttonText = 'Refresh Data';
        onPressed = () => provider.refreshData();
        break;
      case AppState.NO_DATA:
        buttonText = 'Try Again';
        onPressed = () => provider.fetchHealthData();
        break;
      case AppState.ERROR:
        buttonText = 'Retry';
        onPressed = () async {
          final success = await provider.requestPermissions();
          if (success) {
            provider.fetchHealthData();
          }
        };
        break;
    }

    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.orange,
        foregroundColor: Colors.white,
        padding: EdgeInsets.symmetric(vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        elevation: 4,
      ),
      child: isLoading
          ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                ),
                SizedBox(width: 12),
                Text(buttonText, style: TextStyle(fontSize: 16)),
              ],
            )
          : Text(buttonText, style: TextStyle(fontSize: 16)),
    );
  }

  // Main content area
  Widget _buildContentArea(HealthDataProvider provider) {
    switch (provider.state) {
      case AppState.DATA_READY:
        return _buildDataDisplay(provider);
      case AppState.NO_DATA:
        return _buildNoDataDisplay();
      case AppState.ERROR:
        return _buildErrorDisplay(provider.errorMessage);
      case AppState.PERMISSIONS_DENIED:
        return _buildPermissionDeniedDisplay(provider);
      case AppState.FETCHING_DATA:
        return _buildLoadingDisplay();
      default:
        return _buildWelcomeDisplay();
    }
  }

  // Data display widgets
  Widget _buildDataDisplay(HealthDataProvider provider) {
    final metrics = provider.calorieMetrics;
    if (metrics == null) return SizedBox.shrink();

    return Column(
      children: [
        // Calorie metrics cards
        _buildCalorieMetricsCard(metrics),
        SizedBox(height: 16),

        // Daily breakdown
        _buildDailyBreakdownCard(metrics),
        SizedBox(height: 16),

        // Raw data summary
        _buildDataSummaryCard(provider),
      ],
    );
  }

  Widget _buildCalorieMetricsCard(CalorieMetrics metrics) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.local_fire_department,
                    color: Colors.orange, size: 24),
                SizedBox(width: 8),
                Text('Calorie Summary',
                    style:
                        TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            SizedBox(height: 16),
            _buildMetricRow(
                'Total Calories',
                '${metrics.totalCalories.toStringAsFixed(0)} kcal',
                Icons.whatshot),
            _buildMetricRow(
                'Active Calories',
                '${metrics.activeCalories.toStringAsFixed(0)} kcal',
                Icons.directions_run),
            _buildMetricRow(
                'Daily Average',
                '${metrics.averageDailyCalories.toStringAsFixed(0)} kcal',
                Icons.trending_up),
            _buildMetricRow(
                'Last Updated',
                DateFormat('MMM dd, HH:mm').format(metrics.lastUpdated),
                Icons.access_time),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricRow(String label, String value, IconData icon) {
    return Padding(
      padding: EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: Colors.grey[600]),
          SizedBox(width: 12),
          Expanded(child: Text(label, style: TextStyle(fontSize: 14))),
          Text(value,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildDailyBreakdownCard(CalorieMetrics metrics) {
    if (metrics.dailyBreakdown.isEmpty) return SizedBox.shrink();

    return Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Daily Breakdown',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            ...metrics.dailyBreakdown.entries.map((entry) {
              final date = DateTime.parse(entry.key);
              final formattedDate = DateFormat('MMM dd').format(date);
              return ListTile(
                dense: true,
                leading: Icon(Icons.calendar_today,
                    size: 16, color: Colors.grey[600]),
                title: Text(formattedDate),
                trailing: Text('${entry.value.toStringAsFixed(0)} kcal',
                    style: TextStyle(fontWeight: FontWeight.w600)),
              );
            }).toList(),
          ],
        ),
      ),
    );
  }

  Widget _buildDataSummaryCard(HealthDataProvider provider) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.data_usage, color: Colors.blue),
        title: Text('Data Points Retrieved'),
        subtitle: Text('From connected smartwatches and health apps'),
        trailing: Text('${provider.healthDataList.length}',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildNoDataDisplay() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.info_outline, size: 48, color: Colors.blue),
            SizedBox(height: 16),
            Text('No Health Data Found',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(
              'Make sure your smartwatch is connected and has synced recent data to Health Connect.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorDisplay(String error) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red),
            SizedBox(height: 16),
            Text('Error',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }

  Widget _buildLoadingDisplay() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(48),
        child: Column(
          children: [
            SpinKitWave(color: Colors.orange, size: 40),
            SizedBox(height: 16),
            Text('Loading health data...', style: TextStyle(fontSize: 16)),
          ],
        ),
      ),
    );
  }

  Widget _buildPermissionDeniedDisplay(HealthDataProvider provider) {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.lock, size: 48, color: Colors.red),
            SizedBox(height: 16),
            Text('Permissions Denied',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            SizedBox(height: 8),
            Text(provider.errorMessage, textAlign: TextAlign.center),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => openAppSettings(),
              child: Text('Open App Settings'),
            )
          ],
        ),
      ),
    );
  }

  Widget _buildWelcomeDisplay() {
    return Card(
      child: Padding(
        padding: EdgeInsets.all(24),
        child: Column(
          children: [
            Icon(Icons.favorite, size: 48, color: Colors.red),
            SizedBox(height: 16),
            Text('Welcome to Calorie Tracker',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            SizedBox(height: 12),
            Text(
              'Connect to Health Connect to view calorie data from your smartwatch.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }
}

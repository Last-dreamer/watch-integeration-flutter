import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'main.dart';

class PermissionsPage extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Permissions Required'),
        backgroundColor: Colors.orange,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'To get started, we need a few permissions',
              style: Theme.of(context).textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 24),
            PermissionItem(
              icon: Icons.directions_run,
              title: 'Activity Recognition',
              description:
                  'Allows the app to detect your workouts and physical activities.',
            ),
            PermissionItem(
              icon: Icons.location_on,
              title: 'Location',
              description:
                  'Needed to calculate the distance for your runs, walks, and other activities.',
            ),
            PermissionItem(
              icon: Icons.favorite,
              title: 'Health Data',
              description:
                  'Access to your calorie, step, and heart rate data from Health Connect.',
            ),
            Spacer(),
            ElevatedButton(
              onPressed: () async {
                final provider = Provider.of<HealthDataProvider>(context, listen: false);
                final success = await provider.requestPermissions();
                if (success) {
                  provider.fetchHealthData();
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute(builder: (context) => HealthConnectHomePage()),
                  );
                }
              },
              child: Text('Grant Permissions'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange,
                padding: EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class PermissionItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;

  const PermissionItem({
    Key? key,
    required this.icon,
    required this.title,
    required this.description,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Icon(icon, size: 40, color: Colors.orange),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleLarge!),
                SizedBox(height: 4),
                Text(description, style: Theme.of(context).textTheme.bodyMedium!),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

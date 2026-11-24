import 'package:flutter/material.dart';

class MainScaffold extends StatefulWidget {
  final Widget child;

  const MainScaffold({
    super.key,
    required this.child,
  });

  @override
  State<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends State<MainScaffold> {
  int index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          setState(() => index = i);
        },
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Akış',
          ),
          NavigationDestination(
            icon: Icon(Icons.add_box_outlined),
            selectedIcon: Icon(Icons.add_box),
            label: 'Paylaş',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

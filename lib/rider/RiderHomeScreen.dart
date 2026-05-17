import 'package:flutter/material.dart';

class RiderHomeScreen extends StatefulWidget {
  const RiderHomeScreen({super.key});

  @override
  State<RiderHomeScreen> createState() => _RiderHomeScreenState();
}

class _RiderHomeScreenState extends State<RiderHomeScreen> {
  bool isAvailable = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xffe6dfc6),
      body: Column(
        children: [

          /// TOP HEADER
          Container(
            height: 260,
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Color(0xffc20d0d),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(60),
                bottomRight: Radius.circular(60),
              ),
            ),
            child: Stack(
              children: [

                const Positioned(
                  top: 60,
                  left: 20,
                  child: Text(
                    "Hello Amin",
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),

                Positioned(
                  bottom: 0,
                  right: 40,
                  child: Image.network(
                    "https://cdn-icons-png.flaticon.com/512/2972/2972185.png",
                    height: 160,
                  ),
                )
              ],
            ),
          ),

          const SizedBox(height: 20),

          /// Availability Section
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.white70,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [

                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    "Are you available, Amin?",
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [

                    const Text(
                      "Available",
                      style: TextStyle(fontSize: 16),
                    ),

                    const SizedBox(width: 10),

                    Switch(
                      value: isAvailable,
                      activeThumbColor: Colors.red,
                      onChanged: (value) {
                        setState(() {
                          isAvailable = value;
                        });
                      },
                    ),

                    const SizedBox(width: 10),

                    const Text(
                      "Unavailable",
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 40),

          /// Order Stats
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: const [

                OrderStat(
                  title: "Total Orders",
                  number: "10",
                ),

                OrderStat(
                  title: "Delivered",
                  number: "8",
                ),

                OrderStat(
                  title: "Pending",
                  number: "2",
                ),
              ],
            ),
          ),
        ],
      ),

      /// Bottom Navigation
      bottomNavigationBar: BottomNavigationBar(
        selectedItemColor: Colors.red,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: "",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_bag),
            label: "",
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: "",
          ),
        ],
      ),
    );
  }
}

class OrderStat extends StatelessWidget {
  final String title;
  final String number;

  const OrderStat({
    super.key,
    required this.title,
    required this.number,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          number,
          style: const TextStyle(
            fontSize: 30,
            fontWeight: FontWeight.bold,
          ),
        )
      ],
    );
  }
}
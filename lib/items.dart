import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../cart_provider.dart';
import '../models/food_item.dart';
import 'cart_screen.dart';

class ItemDetailScreen extends StatelessWidget {
  final FoodItem item;

  const ItemDetailScreen({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFEF9E7),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: Text(item.name),
        actions: [
          Stack(
            children: [
              IconButton(
                icon: const Icon(Icons.shopping_cart, color: Colors.white),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const CartScreen()),
                  );
                },
              ),
              if (cart.itemCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: const BoxDecoration(
                      color: Colors.red,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      cart.itemCount.toString(),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          Image.network(item.imageUrl, height: 250, fit: BoxFit.cover),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(item.description, style: const TextStyle(fontSize: 16)),
          ),
          const Spacer(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  padding: const EdgeInsets.all(14),
                ),
                onPressed: () {
                  final price = (item.prices['small'] ?? 0).toDouble();
                  cart.addItem(
                    CartItem(
                      name: item.name,
                      imageUrl: item.imageUrl,
                      price: price,
                      category: item.category,
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Item added to cart!')),
                  );
                },
                child: const Text("Add to Cart"),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

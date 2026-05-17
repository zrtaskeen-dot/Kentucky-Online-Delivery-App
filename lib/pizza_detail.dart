import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../cart_provider.dart';
import '../models/food_item.dart';
import 'cart_screen.dart';

class PizzaDetailScreen extends StatefulWidget {
  final FoodItem item;

  const PizzaDetailScreen({super.key, required this.item});

  @override
  State<PizzaDetailScreen> createState() => _PizzaDetailScreenState();
}

class _PizzaDetailScreenState extends State<PizzaDetailScreen> {
  String selectedSize = 'small';

  @override
  Widget build(BuildContext context) {
    final cart = Provider.of<CartProvider>(context);

    return Scaffold(
      backgroundColor: const Color(0xFFFEF9E7),
      appBar: AppBar(
        backgroundColor: Colors.orange,
        title: Text(widget.item.name),
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
          Image.network(widget.item.imageUrl, height: 250, fit: BoxFit.cover),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              widget.item.description,
              style: const TextStyle(fontSize: 16),
            ),
          ),
          const SizedBox(height: 10),
          // 🔹 Size Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: ['small', 'medium', 'large'].map((size) {
              final isSelected = selectedSize == size;
              return GestureDetector(
                onTap: () => setState(() => selectedSize = size),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.orange : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange),
                  ),
                  child: Text(
                    size.toUpperCase(),
                    style: TextStyle(
                      color: isSelected ? Colors.white : Colors.orange,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              );
            }).toList(),
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
                  final price = (widget.item.prices[selectedSize] ?? 0)
                      .toDouble();
                  cart.addItem(
                    CartItem(
                      name: widget.item.name,
                      imageUrl: widget.item.imageUrl,
                      price: price,
                      category: widget.item.category,
                    ),
                  );
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Pizza added to cart!')),
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

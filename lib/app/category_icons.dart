import 'package:flutter/material.dart';

/// Íconos disponibles para categorías. Se guardan por clave para que el árbol de íconos
/// se pueda optimizar en el build (no se construyen `IconData` dinámicos).
const categoryIcons = <String, IconData>{
  'restaurant': Icons.restaurant,
  'shopping_cart': Icons.shopping_cart,
  'directions_bus': Icons.directions_bus,
  'local_gas_station': Icons.local_gas_station,
  'home': Icons.home,
  'bolt': Icons.bolt,
  'water_drop': Icons.water_drop,
  'wifi': Icons.wifi,
  'local_hospital': Icons.local_hospital,
  'school': Icons.school,
  'movie': Icons.movie,
  'checkroom': Icons.checkroom,
  'credit_card': Icons.credit_card,
  'more_horiz': Icons.more_horiz,
  'payments': Icons.payments,
  'add_card': Icons.add_card,
  'savings': Icons.savings,
  'pets': Icons.pets,
  'child_care': Icons.child_care,
  'sports_esports': Icons.sports_esports,
  'fitness_center': Icons.fitness_center,
  'flight': Icons.flight,
  'phone_iphone': Icons.phone_iphone,
  'card_giftcard': Icons.card_giftcard,
  'local_bar': Icons.local_bar,
  'build': Icons.build,
  'church': Icons.church,
  'two_wheeler': Icons.two_wheeler,
  'content_cut': Icons.content_cut,
  'work': Icons.work,
};

const categoryColors = <int>[
  0xFFE57373, 0xFFF06292, 0xFFBA68C8, 0xFF9575CD, 0xFF7986CB, 0xFF64B5F6,
  0xFF4FC3F7, 0xFF4DB6AC, 0xFF81C784, 0xFFAED581, 0xFFFFD54F, 0xFFFFB74D,
  0xFFA1887F, 0xFF90A4AE, 0xFFE53935, 0xFF43A047,
];

IconData iconFor(String key) => categoryIcons[key] ?? Icons.label;

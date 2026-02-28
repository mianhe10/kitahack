// lib/model/product_model.dart

class Product {
  final String id;
  final String title;
  final double currentPrice;
  final double recommendedPrice;
  final int stock;
  final int unitsSold;
  final double estimatedMarketPrice;
  final String aiAdvice;
  final bool isAiReady;

  Product({
    required this.id,
    required this.title,
    required this.currentPrice,
    required this.recommendedPrice,
    required this.stock,
    this.unitsSold = 0,
    this.estimatedMarketPrice = 0.0,
    this.aiAdvice = '',
    this.isAiReady = false,
  });

  /// Convenience method to update only specific fields
  Product copyWith({
    String? id,
    String? title,
    double? currentPrice,
    double? recommendedPrice,
    int? stock,
    int? unitsSold,
    double? estimatedMarketPrice,
    String? aiAdvice,
    bool? isAiReady,
  }) {
    return Product(
      id: id ?? this.id,
      title: title ?? this.title,
      currentPrice: currentPrice ?? this.currentPrice,
      recommendedPrice: recommendedPrice ?? this.recommendedPrice,
      stock: stock ?? this.stock,
      unitsSold: unitsSold ?? this.unitsSold,
      estimatedMarketPrice: estimatedMarketPrice ?? this.estimatedMarketPrice,
      aiAdvice: aiAdvice ?? this.aiAdvice,
      isAiReady: isAiReady ?? this.isAiReady,
    );
  }

  /// Quick helpers for trend arrows
  bool get isUp => recommendedPrice > currentPrice;
  bool get isDown => recommendedPrice < currentPrice;
}

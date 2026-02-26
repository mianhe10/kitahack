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

  bool get isUp => recommendedPrice > currentPrice;
  bool get isDown => recommendedPrice < currentPrice;
}
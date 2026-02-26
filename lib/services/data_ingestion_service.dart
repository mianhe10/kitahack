// lib/services/data_ingestion_service.dart

import 'dart:convert';
import 'dart:typed_data';
import 'package:csv/csv.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

class DataIngestionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final String? _uid = FirebaseAuth.instance.currentUser?.uid;
  final String apiKey;

  DataIngestionService({required this.apiKey});

  Future<Map<String, dynamic>> sniffCsv(Uint8List fileBytes) async {
    final csvString = utf8.decode(fileBytes);
    final fields = const CsvToListConverter().convert(csvString);

    if (fields.isEmpty) throw Exception("The CSV file is empty.");

    final headers = List<String>.from(fields[0].map((e) => e.toString().trim()));
    final sample = fields.length > 1 
        ? fields.sublist(1, fields.length > 4 ? 4 : fields.length) 
        : [];

    return {
      'headers': headers,
      'sample': sample,
    };
  }

  Future<Map<String, String>?> findExistingTemplate(List<String> headers) async {
    if (_uid == null) return null;

    String signature = headers.join(":");
    
    final query = await _db
        .collection('users')
        .doc(_uid)
        .collection('pricing_templates')
        .where('signature', isEqualTo: signature)
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return Map<String, String>.from(query.docs.first['mapping']);
    }
    return null;
  }

  Future<Map<String, String>> getAiSuggestedMapping({
    required List<String> headers,
    required List<dynamic> sample,
  }) async {
    final model = GenerativeModel(
      model: 'gemini-2.5-flash', 
      apiKey: apiKey,
    );

    final prompt = """
      You are a Data Engineering Assistant for Malaysian MSMEs.
      I have a CSV with these headers: $headers
      Example data row: $sample

      Map these headers to our internal standard keys: 
      - 'prod_id' (product name or SKU)
      - 'price' (the actual selling price/amount paid)
      - 'qty' (current stock quantity available)
      - 'units_sold' (how many units were sold recently)
      - 'date' (transaction timestamp)

      Rules:
      1. Return ONLY valid JSON. 
      2. If a header is in Malay (e.g., 'Harga', 'Kuantiti', 'Jualan'), map it to the correct intent.
      3. Format: {"prod_id": "UserHeader", "price": "UserHeader", "qty": "UserHeader", "units_sold": "UserHeader", "date": "UserHeader"}
    """;

    final response = await model.generateContent([Content.text(prompt)]);
    final String cleanJson = response.text!
        .replaceAll('```json', '')
        .replaceAll('```', '')
        .trim();

    return Map<String, String>.from(jsonDecode(cleanJson));
  }

  Future<void> saveTemplate(List<String> headers, Map<String, String> confirmedMapping) async {
    if (_uid == null) return;

    await _db.collection('users').doc(_uid).collection('pricing_templates').add({
      'signature': headers.join(":"),
      'mapping': confirmedMapping,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }
}
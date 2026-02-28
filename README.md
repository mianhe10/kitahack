# Pryce — MSME Pricing Intelligence

> *Democratizing enterprise-level AI for Malaysia's smallest businesses.*

[![Flutter](https://img.shields.io/badge/Flutter-3.27+-02569B?logo=flutter)](https://flutter.dev)
[![Firebase](https://img.shields.io/badge/Firebase-Firestore-FFCA28?logo=firebase)](https://firebase.google.com)
[![Gemini](https://img.shields.io/badge/Gemini-1.5%20Flash-4285F4?logo=google)](https://aistudio.google.com)
[![KitaHack](https://img.shields.io/badge/KitaHack-2026-blueviolet)](https://kitahack.com)

---

## The Problem

Malaysian MSMEs operate in a hyper-competitive, algorithm-driven digital economy. Large corporations deploy high-frequency AI pricing engines around the clock — small sellers rely on gut feeling.

The result: race-to-the-bottom price wars, lost customers from overpricing, and no way to forecast demand or simulate promotions. With **97% of Malaysian businesses classified as SMEs**, this gap has real economic consequences.

**Pryce closes that gap.**

---

## How It Works

```
Import → Analyze → Simulate → Execute
```

1. **Import** — Upload the last 30 days of Shopee or TikTok Shop sales via CSV.
2. **Analyze** — The AI evaluates each product and visualizes market sentiment and demand elasticity.
3. **Simulate** — Drag the price slider to see how changes affect predicted volume and total profit in real time.
4. **Execute** — Update prices with confidence, backed by data rather than emotion.

---

## Core Features

### 🤖 AI Pricing Engine
Sends each product's name, current price, stock, and sales velocity to Gemini. Returns an `estimatedMarketPrice`, a `recommendedPrice`, and a one-sentence actionable insight tailored to the Malaysian market.

### 📥 Smart CSV Ingestion
E-commerce exports vary wildly — "Harga" vs "Price", Malay vs English headers. Instead of brittle regex, a sample row is passed to Gemini which intelligently maps columns to the internal schema (`prod_id`, `price`, `qty`, `units_sold`).

### 📈 Daily Demand Forecasting
The home dashboard aggregates weekly sales into a normalized demand curve. Gemini analyzes this alongside the user's industry and region (e.g. *Retail in Kuala Lumpur*) to explain *why* a day is peaking and what pricing action to take.

### 🎛 Interactive Profit Simulator
A local mathematical model using price elasticity (default: −1.5) powers real-time sliders. As the target price moves, predicted volume and profit lift recalculate instantly, drawing the optimal "sweet spot" on a live curve.

**Core optimization formula:**

$$\text{Profit} = (\text{Price} - \text{Cost}) \times \text{Predicted Demand}$$

---

## Technical Architecture

| Layer | Technology |
|---|---|
| Mobile Framework | Flutter (Dart) 3.27+ |
| UI Charting | `fl_chart` |
| Authentication | Firebase Authentication |
| Database | Cloud Firestore (NoSQL) |
| AI Model | Google Gemini 1.5 Flash |
| Image Storage | Base64 encoding via Firestore |

All infrastructure runs serverless on the **Google Cloud / Firebase** ecosystem.

---

## Challenges & Solutions

**API Rate Limiting** — Free-tier Gemini quotas were exhausted during bulk product analysis. Fixed with Firestore-cached daily briefings, an `isAiReady` document flag to skip redundant calls, and a switch to the more efficient `gemini-1.5-flash` model.

**Unpredictable CSV Formats** — Vendor exports differ by platform and language. Solved by using Gemini's natural language understanding to dynamically map headers rather than hardcoded regex patterns.

**UI Freezing on Large Imports** — Parsing big CSVs and awaiting hundreds of Firestore writes blocked the Flutter UI thread. Resolved by offloading parsing asynchronously and batching up to 500 Firestore operations per atomic `batch()` commit.

---

## Roadmap

**Phase 1 — Vertex AI Migration**
Move from the standard Gemini API to Google Cloud Vertex AI for enterprise-grade rate limits, regional low-latency endpoints, and fine-tuned models on Malaysian retail datasets.

**Phase 2 — Live E-Commerce Integrations**
Replace manual CSV uploads with direct Shopee, TikTok Shop, and Lazada Open API integrations via Google Cloud Functions for real-time inventory and sales sync.

**Phase 3 — Analytics & Multi-Tenant RBAC**
Add Firebase Analytics and Crashlytics for usage monitoring. Implement Role-Based Access Control via Firebase App Check and Custom Claims so business owners can manage staff access and multiple franchise locations from a single dashboard.

---

## SDG Alignment

| Goal | Contribution |
|---|---|
| **SDG 1** — No Poverty | Increasing income stability for B40 entrepreneurs |
| **SDG 8** — Decent Work & Economic Growth | Strengthening MSME resilience and competitiveness |
| **SDG 9** — Industry, Innovation & Infrastructure | Upgrading tech capabilities of small-scale industries |

---

## Getting Started

### Prerequisites
- Flutter SDK **3.27.0+**
- Dart SDK **3.0.0+**
- A free Gemini API key from [Google AI Studio](https://aistudio.google.com/)

### Installation

```bash
# 1. Clone the repo
git clone https://github.com/your-username/kitahack.git
cd kitahack

# 2. Install dependencies
flutter pub get
```

### Configure the API Key

Create (or open) `lib/constants/app_constants.dart` and add:

```dart
class AppConstants {
  static const String geminiApiKey = 'YOUR_GEMINI_API_KEY_HERE';
}
```

### Run

```bash
flutter run
```

> **Note:** Firebase configuration files are included in the repository for seamless hackathon testing — no additional Firebase setup required.

---

## The Team

Built at **Universiti Malaya** for **KitaHack 2026**

| | |
|---|---|
| Muaz Zikry | Adam Haikal |
| Ahmad Fahim | Aniq Aisar |

---

*"Enterprise corporations use AI pricing engines to maximize profit every second. Pryce brings that same power to Malaysia's smallest businesses."*

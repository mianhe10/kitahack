[# kitahack](https://img.shields.io/badge/Kito-Hek-blue)

---

# 📊 MSME Pricing Intelligence

### *Democratizing Enterprise-Level AI for Malaysia’s Smallest Businesses*

Malaysian micro-sellers operate in a hyper-competitive, algorithm-controlled digital economy. While large corporations use high-frequency AI pricing engines, MSMEs often rely on "gut feeling" or emotional reactions to competitors. **MSME Pricing Intelligence** provides the same scientific precision to the backbone of our economy.

---

## 🚀 The Problem

Malaysian MSMEs lack data-driven pricing strategies, resulting in:

* **Underpricing:** Reduced margins due to "race to the bottom" price wars.
* **Overpricing:** Lost customers to competitors.
* **Decision Paralysis:** Inability to forecast demand or simulate promotion outcomes.
* **Economic Vulnerability:** 97% of Malaysian businesses are SMEs, yet many struggle to stay profitable amidst rising logistics and supplier costs.

---

## 🛠 Technical Architecture

The platform is built on a modern, scalable stack designed for real-time interaction and deep analytical processing.

* **Frontend:** **Flutter** (Mobile/Web) for a cross-platform, high-performance UI.
* **Backend & Auth:** **Firebase** for rapid scaling and seamless user authentication.
* **Database:** **Cloud Firestore** for real-time inventory and pricing data storage.
* **AI Engine:** * **Vertex AI:** Powers the regression and time-series models for demand forecasting.
* **Gemini AI:** Translates complex data into conversational, actionable business insights for sellers.
* **File Handling:** `file_picker` for secure CSV ingestion.
* **Database Schema:** * `products/`: Stores name, base price, cost, and stock.
* `sales/`: Stores historical price points and volume for the AI Forecasting Engine.
* **Data Processing:** Dart-based CSV parser to convert raw strings into structured JSON for Firestore.

* **Integration:** Support for **Shopee/TikTok Seller Data** (CSV) and **Google Trends** for market signal analysis.

---

## 🧪 Implementation Details

### 1. Demand Forecasting Engine

The system uses regression models to calculate:


$$Demand = f(price, competitor\_price, seasonality, trend)$$


By analyzing historical sales alongside external trends, we move beyond static pricing to dynamic, context-aware recommendations.

---

### 2. Smart Inventory Management

The inventory module acts as the "Source of Truth" for the MSME.

* **Firebase Synchronization:** Real-time tracking of stock levels using Cloud Firestore.
* **Low-Stock Alerts:** Visual indicators (Red/Green badges) to prevent "Out of Stock" scenarios during high-demand periods.
* **Manual & Bulk Entry:** Supports individual product creation or bulk CSV uploads for existing retail businesses.

### 3. Sales Data Integration (CSV Engine)

To enable AI forecasting, sellers need a way to import historical data without manual entry.

* **CSV Mapping Engine:** A custom-built interface that allows users to map their Shopee/TikTok export columns to our platform's internal data model.
* **Data Cleansing:** Automatically handles missing values or formatting errors common in raw marketplace exports.

---

## 🚀 How it Works (The Workflow)

1. **Import:** The seller uploads their last 30 days of sales from Shopee via the **Inventory Screen**.
2. **Analyze:** The **Analysis Screen** processes this data, identifying that their product has a "Demand Elasticity of 0.42."
3. **Simulate:** The seller uses the **Profit Simulator** to see that increasing their price by RM5 will actually *increase* total profit, despite a small drop in volume.
4. **Execute:** The seller updates their price with confidence, backed by data rather than emotion.

---
### 4. Profit Optimization Logic

The core algorithm prioritizes **Profit over Revenue**:


$$Profit = (Price - Cost) \times Predicted\ Demand$$


The app identifies the "Sweet Spot" on the optimization curve where the seller makes the most money, not just the most sales.

---

## 🚧 Challenges Faced

* **Data Scarcity:** Micro-sellers often lack long-term historical records. We solved this by using **Transfer Learning** from broader category benchmarks in the "Home Living" and "Retail" sectors.
* **User Literacy:** Most users find statistics intimidating. We implemented the **Gemini AI Insight Layer** to turn "0.42 Elasticity" into "Your customers won't mind a RM2 increase."
* **Real-time Computation:** Generating 50+ data points for a smooth curve on mobile devices required optimized `useMemo`-style logic in Flutter to prevent UI lag.

---

## 🗺 Future Roadmap

### Phase 1: Pilot (Q2 2026)

* Launch pilot with 200 MSMEs in the Klang Valley.
* Refine models for local niche markets (e.g., *Pasar Malam* vendors).

### Phase 2: Integration (Q4 2026)

* Direct API integration with **Shopee Open Platform** and **TikTok Shop Seller Center**.
* Automated price syncing based on AI recommendations.

### Phase 3: Financial Inclusion (2027)

* **Business Health Scoring:** Use pricing stability data to help MSMEs secure micro-financing.
* **Inventory Optimization:** Predictive restocking based on forecasted demand peaks.

---

## 🌍 SDG & National Impact

Our project directly contributes to the **UN Sustainable Development Goals** and Malaysia's national agenda:

* **SDG 1 (No Poverty):** Increasing income stability for B40 entrepreneurs.
* **SDG 8 (Decent Work & Economic Growth):** Strengthening MSME resilience.
* **SDG 9 (Industry, Innovation & Infrastructure):** Upgrading the technological capabilities of small-scale industries.

---

## 👥 The Team

Part of **Universiti Malaya (Group OCC 12, Group 2)** for **KitaHack 2026**.

* **Muaz Zikry**
* **Adam Haikal** 
* **Ahmad Fahim** 
* **Aniq Aisar** 
---

> **“Enterprise corporations use AI pricing engines to maximize profit every second. MSME Pricing Intelligence brings that same power to Malaysia’s smallest businesses.”**

---

### 🛠 Installation & Setup

To get the **MSME Pricing Intelligence** environment running locally, follow these steps:

#### 1. Prerequisites

* **Flutter SDK:** 3.27.0 or higher
* **Dart SDK:** 3.0.0 or higher
* **Firebase CLI:** For backend services

#### 2. Clone the Repository

```bash
git clone https://github.com/your-username/kitahack.git
cd kitahack

```

#### 3. Install Dependencies

This project uses `fl_chart` for data visualization and `lucide_icons` for a modern UI.

```bash
flutter pub get

```

#### 4. Backend Configuration

1. Create a project on the [Firebase Console](https://console.firebase.google.com/).
2. Enable **Cloud Firestore** and **Authentication**.
3. Add your `google-services.json` (Android) or `GoogleService-Info.plist` (iOS) to the respective directories.

#### 5. Run the App

```bash
flutter run

```

---

### 📂 Project Structure

* `lib/screens/`: Contains the Simulator, Inventory, and Analysis UI.
* `lib/theme/`: Custom `AppColors` for the "Midnight" theme.
* `lib/widgets/`: Reusable components like the `AIRecommendationCard`.

---

### 🚀 Deployment to GitHub

Once you have finished your feature, follow these terminal commands to push your branch:

```bash
# 1. Create and switch to your feature branch
git checkout -b feature-simulator

# 2. Stage and commit your changes
git add .
git commit -m "Integrated fl_chart and Vertex AI logic"

# 3. Push to GitHub
git push -u origin feature-simulator

```

---
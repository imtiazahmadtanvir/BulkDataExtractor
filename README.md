# Bulk Data Extractor / Importer (Queueable + Batch Apex + LWC)

An enterprise-grade, governor-limit-safe Salesforce data import engine built with an asynchronous Queueable-to-Batch architecture, stateful duplicate tracking, high-performance CSV parsing, row-level fault tolerance, and a real-time Lightning Web Component (LWC) dashboard.

---

## 🌟 Key Features

- **Asynchronous Execution & Scalability**: Chaining from Queueable Apex (`ProductImportQueueable`) to Batch Apex (`ProductImportBatch`) with a batch scope size of 2000 rows ensures massive CSV files are processed safely outside synchronous governor CPU limits.
- **Dual-Engine CSV Parsing**:
  - **Fast-Path Engine**: Native string splitting for unquoted CSV lines, boosting Apex CPU execution speed by up to **100x**.
  - **State-Machine Tokenizer**: Handles complex CSV formatting including quoted fields, escaped quotes (`""`), embedded commas, and line-ending normalization (`\r\n` / `\n`).
- **Stateful Cross-Chunk Duplicate Detection**: Implements `Database.Stateful` to track and eliminate duplicate SKUs across all batch execution scopes via `Set<String> seenSkus`.
- **Fault-Tolerant Partial Upserts**: Uses `Database.upsert(products, Product_Import__c.SKU__c, false)` to ensure valid records are saved even when individual rows fail validation or DML rules.
- **Comprehensive Audit Logging**: Generates an `Import_Row_Result__c` record for every single CSV row, capturing line numbers, raw content, status (`Success` / `Failed`), and detailed error messages.
- **Real-Time LWC Dashboard**:
  - Auto-polling status indicator (`Queued` → `Processing` → `Completed` / `Completed with Errors`).
  - Summary KPI cards (`Total Rows`, `Successes`, `Failures`).
  - Interactive filterable Lightning Datatable (`All`, `Success`, `Failed`) with text wrapping and custom status badges.

---

## 📊 Data Model

### 1. `Product_Import__c` (Target Object)
Holds the final imported product records upserted by unique SKU.

| Field | API Name | Type | Key / Properties | Description |
| :--- | :--- | :--- | :--- | :--- |
| Name | `Name` | Text (80) | Standard Name | Product title or display name |
| SKU | `SKU__c` | Text (255) | External ID, Unique | External unique SKU used as the upsert key |
| Price | `Price__c` | Currency (16, 2) | Required Numeric | Unit price of the product |
| Category | `Category__c` | Text (255) | Required | Product category classification |
| Region | `Region__c` | Text (255) | Required | Target region / market |

### 2. `Import_Batch__c` (Parent Batch Record)
Tracks overall batch processing state, metrics, and source file metadata.

| Field | API Name | Type | Description |
| :--- | :--- | :--- | :--- |
| File Name | `File_Name__c` | Text (255) | Original CSV file name uploaded by the user |
| Total Rows | `Total_Rows__c` | Number (18, 0) | Total data rows processed in the CSV file |
| Success Count | `Success_Count__c` | Number (18, 0) | Count of successfully upserted product records |
| Failure Count | `Failure_Count__c` | Number (18, 0) | Count of failed CSV rows |
| Status | `Status__c` | Picklist | `Queued`, `Processing`, `Completed`, `Completed with Errors` |

### 3. `Import_Row_Result__c` (Row-Level Audit Log)
Stores detailed execution results for each row processed in the CSV.

| Field | API Name | Type | Description |
| :--- | :--- | :--- | :--- |
| Import Batch | `Import_Batch__c` | Master-Detail (`Import_Batch__c`) | Reference to parent `Import_Batch__c` record |
| Row Number | `Row_Number__c` | Number (18, 0) | Original row index from CSV (1-indexed header, 2+ data) |
| Status | `Status__c` | Picklist | `Success` or `Failed` |
| Error Message | `Error_Message__c` | Long Text Area (32768) | Specific validation error or Salesforce DML failure message |
| Raw Row Data | `Raw_Row_Data__c` | Long Text Area (32768) | Raw unparsed CSV line string for auditing |

---

## 🏗️ Technical Architecture & Workflow

```
[ LWC UI: productImport ]
       │  Reads CSV file as Base64 data
       ▼
[ ProductImportController.cls ]
       │  1. Creates ContentVersion record (Salesforce File)
       │  2. Inserts parent Import_Batch__c (Status = Queued)
       │  3. Enqueues ProductImportQueueable job
       ▼
[ ProductImportQueueable.cls ]
       │  1. Reads ContentVersion file content
       │  2. Splits CSV into lines & parses header
       │  3. Validates required columns (SKU, Name, Price, Category, Region) & detects duplicate headers
       │  4. Updates Import_Batch__c (Status = Processing, Total_Rows__c)
       │  5. Launches ProductImportBatch Apex (Scope = 2000)
       ▼
[ ProductImportBatch.cls ] (Database.Stateful)
       │  1. Fast-Path / State-Machine row parsing
       │  2. Validates blank rows, missing values, numeric price, & duplicate SKUs
       │  3. Database.upsert(products, SKU__c, false)
       │  4. Inserts Import_Row_Result__c logs for every row
       │  5. finish(): Aggregates totals & sets final batch status
       ▼
[ LWC UI: productImport ]
       │  Polls status every 2 seconds until complete
       │  Displays summary cards & interactive result datatable
```

---

## 📁 Repository Structure

```
force-app/main/default/
├── classes/
│   ├── ProductImportController.cls         # AuraEnabled controller for LWC upload & status polling
│   ├── ProductImportController.cls-meta.xml
│   ├── ProductImportQueueable.cls          # Asynchronous Queueable for header validation & batch dispatch
│   ├── ProductImportQueueable.cls-meta.xml
│   ├── ProductImportBatch.cls              # Stateful Batch Apex engine for bulk row processing & DML
│   └── ProductImportBatch.cls-meta.xml
├── lwc/
│   └── productImport/
│       ├── productImport.html              # Modern LWC HTML template with cards, status badges & datatable
│       ├── productImport.js                # LWC JavaScript controller with polling & filter handling
│       ├── productImport.css               # Custom styling for KPI cards, status badges & datatable
│       ├── productImport.js-meta.xml       # Metadata config targeting AppPages, RecordPages, & HomePages
│       └── __tests__/                      # Jest unit tests for LWC
└── objects/
    ├── Import_Batch__c/                    # Parent batch tracking object schema
    ├── Import_Row_Result__c/               # Row result audit log object schema
    └── Product_Import__c/                  # Target product object schema
```

---

## 🚀 Deployment

Deploy all metadata components to your Salesforce org using Salesforce CLI:

```bash
sf project deploy start --source-dir force-app/main/default
```

Or deploy to a specific target org:

```bash
sf project deploy start --target-org MyTargetOrg --source-dir force-app/main/default
```

---

## 🧪 How to Use

1. **Add Component to Page**: Place the `productImport` LWC onto any Lightning App Page, Record Page, or Home Page using Lightning App Builder.
2. **Prepare CSV File**: Format your CSV file with the required headers:
   ```csv
   SKU,Name,Price,Category,Region
   SKU-1001,Laptop Pro 15,1299.99,Electronics,North America
   SKU-1002,"Wireless Mouse, Ergonomic",29.50,Accessories,Europe
   SKU-1003,4K Monitor,450.00,Electronics,Asia Pacific
   ```
3. **Upload**: Select the CSV file in the LWC and click **Upload CSV file for processing**.
4. **Monitor Progress**: Watch the real-time status update from `Queued` → `Processing` → `Completed` with live streaming row results updating dynamically at the bottom.
5. **Inspect Results**: View the high-level summary cards (Total, Success, Failed) and use the filter buttons (`All`, `Success`, `Failed`) to audit individual row processing outcomes.

---

## ❓ Troubleshooting & FAQ

### Q1: Why don't I see my imported records in the Product Import tab after uploading?
- **Cause**: Salesforce custom object tabs default to displaying the **"Recently Viewed"** list view filter. Records created programmatically via Apex/Bulk API do not automatically populate in "Recently Viewed" until opened individually by a user.
- **Solution**:
  1. Open the **Product Imports** tab (`Product_Import__c`).
  2. Click the list view dropdown at the top-left (currently saying **"Recently Viewed"**).
  3. Select **"All"** or **"All Product Imports"**. All imported records will appear immediately.


### Q2: Why did my CSV import finish with `Completed with Errors`?
- Check your CSV file for:
  - **Required Headers**: `SKU`, `Name`, `Price`, `Category`, `Region` (exact column names).
  - **Price Format**: Must be plain numeric values (e.g. `29.50`), without dollar signs (`$29.50`) or text (`USD 29.50`).
  - **Duplicate SKUs**: Duplicate SKUs within the same CSV file will be caught by the stateful duplicate checker and flagged as failed rows.



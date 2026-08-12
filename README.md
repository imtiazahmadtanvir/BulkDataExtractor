# Bulk Data Extractor (Queueable + Batch Apex + LWC)

An enterprise-grade, bulk-safe Salesforce data import engine designed to upload, parse, validate, and process CSV exports in bulk without hitting governor limits. Includes per-row error tracking and an interactive Lightning Web Component (LWC) interface.

---

## 🌟 Key Features

- **Asynchronous Execution**: Uses Queueable to Batch Apex chaining to safely process large files off the synchronous thread.
- **Bulk Safe & Fault Tolerant**: Performs `Database.upsert` with `allOrNone=false`, ensuring valid rows are saved even if individual rows fail.
- **Stateful Duplicate SKU Detection**: Tracks duplicate SKUs across all batch chunks using `Database.Stateful`.
- **Robust CSV Parser**: Custom state-machine CSV parser that supports quoted fields, escaped quotes (`""`), embedded commas, and line breaks.
- **Comprehensive Failure Handling**: Validates required headers, missing fields, numeric data types (`Price__c`), blank rows, duplicate SKUs, and DML validation errors.
- **Detailed Audit Log**: Generates an `Import_Row_Result__c` record for every single row in the CSV (Success or Failed with exact error messages).
- **Interactive LWC Interface**: Displays real-time status polling (`Queued` → `Processing` → `Completed`) and an interactive datatable with filters (`All`, `Success`, `Failed`).

---

## 📊 Data Model

### 1. `Product_Import__c` (Target Object)
| Field | Type | Properties | Description |
| :--- | :--- | :--- | :--- |
| `SKU__c` | Text | Unique, External ID | External unique key used for upserting |
| `Name` | Text | Standard Name | Product Name |
| `Price__c` | Currency | Scale 2, Precision 18 | Product Unit Price |
| `Category__c` | Text | | Product Category |
| `Region__c` | Text | | Product Region |

### 2. `Import_Batch__c` (Parent Batch Record)
| Field | Type | Description |
| :--- | :--- | :--- |
| `File_Name__c` | Text | Name of the uploaded CSV file |
| `Total_Rows__c` | Number | Total data rows found in the CSV |
| `Success_Count__c` | Number | Count of successfully upserted rows |
| `Failure_Count__c` | Number | Count of failed rows |
| `Status__c` | Picklist | `Queued`, `Processing`, `Completed`, `Completed with Errors` |

### 3. `Import_Row_Result__c` (Row Level Audit Log)
| Field | Type | Description |
| :--- | :--- | :--- |
| `Import_Batch__c` | Master-Detail | Parent `Import_Batch__c` reference |
| `Row_Number__c` | Number | Original CSV row index |
| `Status__c` | Picklist | `Success` or `Failed` |
| `Error_Message__c` | Long Text Area | Failure reason or validation error message |
| `Raw_Row_Data__c` | Long Text Area | Raw line content from CSV |

---

## 🏗️ Architecture & Component Flow

```
[ LWC UI: productImport ]
       │  (Upload CSV Base64)
       ▼
[ ProductImportController.cls ]
       │  1. Creates ContentVersion (Salesforce File)
       │  2. Inserts Import_Batch__c (Status = Queued)
       │  3. Enqueues Queueable Job
       ▼
[ ProductImportQueueable.cls ]
       │  1. Parses CSV Header & validates required columns
       │  2. Updates Import_Batch__c (Status = Processing)
       │  3. Executes Batch Apex (Scope = 100)
       ▼
[ ProductImportBatch.cls ] (Stateful)
       │  1. Parses rows via parseCsvLine()
       │  2. Validates data types & duplicate SKUs
       │  3. Performs Database.upsert(products, SKU__c, false)
       │  4. Creates Import_Row_Result__c per row
       │  5. finish(): Updates Import_Batch__c status & counts
       ▼
[ LWC UI: productImport ] (Polls & displays datatable + filters)
```

---

## 🚀 Deployment Instructions

Deploy the project metadata to your target Salesforce org using the Salesforce CLI:

```bash
sf project deploy start --source-dir force-app/main/default
```

---

## 🧪 How to Use

1. Open Salesforce and navigate to the page where the **`productImport`** Lightning Web Component is placed.
2. Select a CSV file containing the required headers:
   ```csv
   SKU,Name,Price,Category,Region
   SKU-1001,Laptop Pro 15,1299.99,Electronics,North America
   SKU-1002,Wireless Mouse,29.50,Accessories,Europe
   ```
3. Click **Upload CSV**.
4. Monitor the status update in real-time.
5. Review the summary metrics and use the **All**, **Success**, or **Failed** filter buttons to inspect individual row results.

public with sharing class ProductImportController {

    /*
     * ============================================================
     * UPLOAD CSV
     * ============================================================
     */
    @AuraEnabled
    public static Id uploadCsv(
        String fileName,
        String base64Data
    ) {

        if (String.isBlank(fileName)) {

            throw new AuraHandledException(
                'File name is required.'
            );
        }

        if (String.isBlank(base64Data)) {

            throw new AuraHandledException(
                'CSV file is empty.'
            );
        }

        /*
         * Only CSV files are allowed.
         */
        if (!fileName.toLowerCase().endsWith('.csv')) {

            throw new AuraHandledException(
                'Only CSV files are allowed.'
            );
        }

        /*
         * Decode Base64.
         */
        Blob fileBody;

        try {

            fileBody =
                EncodingUtil.base64Decode(base64Data);

        } catch (Exception e) {

            throw new AuraHandledException(
                'Unable to decode the uploaded file.'
            );
        }

        /*
         * Make sure decoded file isn't empty.
         */
        if (fileBody == null || fileBody.size() == 0) {

            throw new AuraHandledException(
                'CSV file is empty.'
            );
        }

        /*
         * ========================================================
         * CREATE SALESFORCE FILE
         * ========================================================
         */
        ContentVersion cv =
            new ContentVersion();

        cv.Title =
            fileName.toLowerCase().endsWith('.csv')
                ? fileName.substring(
                    0,
                    fileName.length() - 4
                )
                : fileName;

        cv.PathOnClient = fileName;
        cv.VersionData = fileBody;

        insert cv;

        /*
         * ========================================================
         * CREATE IMPORT BATCH
         * ========================================================
         */
        Import_Batch__c importBatch =
            new Import_Batch__c();

        importBatch.File_Name__c =
            fileName;

        importBatch.Status__c =
            'Queued';

        importBatch.Total_Rows__c = 0;
        importBatch.Success_Count__c = 0;
        importBatch.Failure_Count__c = 0;

        insert importBatch;

        /*
         * ========================================================
         * START QUEUEABLE
         * ========================================================
         */
        System.enqueueJob(
            new ProductImportQueueable(
                importBatch.Id,
                cv.Id
            )
        );

        /*
         * Return Import Batch Id to LWC.
         */
        return importBatch.Id;
    }


    /*
     * ============================================================
     * GET IMPORT BATCH
     * ============================================================
     *
     * LWC uses this method to check:
     *
     * Queued
     * Processing
     * Completed
     * Completed with Errors
     *
     */
    @AuraEnabled(cacheable=true)
    public static Import_Batch__c getImportBatch(
        Id batchId
    ) {

        if (batchId == null) {

            throw new AuraHandledException(
                'Import Batch Id is required.'
            );
        }

        return [
            SELECT
                Id,
                Name,
                File_Name__c,
                Total_Rows__c,
                Success_Count__c,
                Failure_Count__c,
                Status__c
            FROM Import_Batch__c
            WHERE Id = :batchId
            LIMIT 1
        ];
    }


    /*
     * ============================================================
     * GET ROW RESULTS
     * ============================================================
     *
     * Returns one Import_Row_Result__c for each
     * processed CSV row.
     */
    @AuraEnabled(cacheable=true)
    public static List<Import_Row_Result__c> getRowResults(
        Id batchId
    ) {

        if (batchId == null) {

            throw new AuraHandledException(
                'Import Batch Id is required.'
            );
        }

        return [
            SELECT
                Id,
                Row_Number__c,
                Status__c,
                Error_Message__c,
                Raw_Row_Data__c
            FROM Import_Row_Result__c
            WHERE Import_Batch__c = :batchId
            ORDER BY Row_Number__c ASC
        ];
    }
}
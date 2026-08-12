public with sharing class ProductImportController {

    @AuraEnabled
    public static Id uploadCsv(String fileName, String base64Data) {

        if (String.isBlank(fileName)) {
            throw new AuraHandledException('File name is required.');
        }

        if (String.isBlank(base64Data)) {
            throw new AuraHandledException('CSV file is empty.');
        }

        // Decode the uploaded Base64 CSV
        Blob fileBody;

        try {
            fileBody = EncodingUtil.base64Decode(base64Data);
        } catch (Exception e) {
            throw new AuraHandledException('Unable to decode the uploaded file.');
        }

        // Store the CSV as a Salesforce File
        ContentVersion cv = new ContentVersion();
        cv.Title = fileName.endsWith('.csv')
            ? fileName.substring(0, fileName.length() - 4)
            : fileName;
        cv.PathOnClient = fileName;
        cv.VersionData = fileBody;

        insert cv;

        // Create Import Batch
        Import_Batch__c importBatch = new Import_Batch__c();
        importBatch.File_Name__c = fileName;
        importBatch.Status__c = 'Queued';
        importBatch.Total_Rows__c = 0;
        importBatch.Success_Count__c = 0;
        importBatch.Failure_Count__c = 0;

        insert importBatch;

        // Start asynchronous processing
        System.enqueueJob(
            new ProductImportQueueable(
                importBatch.Id,
                cv.Id
            )
        );

        return importBatch.Id;
    }
}
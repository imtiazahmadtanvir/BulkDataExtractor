public with sharing class ProductImportQueueable implements Queueable {

    private Id batchId;
    private Id contentVersionId;

    public ProductImportQueueable(Id batchId, Id contentVersionId) {
        this.batchId = batchId;
        this.contentVersionId = contentVersionId;
    }

    public void execute(QueueableContext context) {

        // Get the stored CSV file
        ContentVersion cv = [
            SELECT Id, VersionData, Title, FileExtension
            FROM ContentVersion
            WHERE Id = :contentVersionId
            LIMIT 1
        ];

        // Convert file to text
        String csvText = cv.VersionData.toString();

        // Basic empty-file check
        if (String.isBlank(csvText)) {
            update new Import_Batch__c(
                Id = batchId,
                Status__c = 'Completed with Errors',
                Failure_Count__c = 1,
                Total_Rows__c = 0
            );
            return;
        }

        // Split CSV into lines
        List<String> rows = csvText.split('\\r?\\n');

        // Remove header
        if (!rows.isEmpty()) {
            rows.remove(0);
        }

        // Update batch status
        update new Import_Batch__c(
            Id = batchId,
            Status__c = 'Processing',
            Total_Rows__c = rows.size()
        );

        // Start Batch Apex
        Database.executeBatch(
            new ProductImportBatch(batchId, rows),
            100
        );
    }
}
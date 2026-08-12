public with sharing class ProductImportBatch
    implements Database.Batchable<String>, Database.Stateful {

    private Id batchId;
    private List<String> rows;
    private Map<String, Integer> columnMap;

    /*
     * Keeps track of duplicate SKUs across
     * ALL Batch execute() scopes.
     */
    private Set<String> seenSkus = new Set<String>();

    /*
     * Keeps the original CSV row number.
     *
     * CSV header = row 1
     * First data row = row 2
     */
    private Integer currentRowNumber = 2;

    /*
     * Constructor
     */
    public ProductImportBatch(
        Id batchId,
        List<String> rows,
        Map<String, Integer> columnMap
    ) {
        this.batchId = batchId;
        this.rows = rows;
        this.columnMap = columnMap;
    }

    /*
     * START
     */
    public Iterable<String> start(
        Database.BatchableContext context
    ) {
        return rows;
    }

    /*
     * EXECUTE
     */
    public void execute(
        Database.BatchableContext context,
        List<String> scope
    ) {

        List<Import_Row_Result__c> rowResults =
            new List<Import_Row_Result__c>();

        List<Product_Import__c> productsToUpsert =
            new List<Product_Import__c>();

        /*
         * Store the source row information for
         * every Product record being upserted.
         */
        List<Integer> productRowNumbers =
            new List<Integer>();

        List<String> productRawRows =
            new List<String>();

        /*
         * Process every CSV row in this scope.
         */
        for (String row : scope) {

            Integer rowNumber = currentRowNumber;

            currentRowNumber++;

            List<String> fields;

            /*
             * ==========================================
             * CSV PARSING
             * ==========================================
             */
            try {

                fields = parseCsvLine(row);

            } catch (Exception e) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'CSV parsing error: ' +
                        e.getMessage()
                    )
                );

                continue;
            }

            /*
             * ==========================================
             * BLANK ROW
             * ==========================================
             */
            if (isBlankRow(fields)) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'Fully blank row.'
                    )
                );

                continue;
            }

            /*
             * ==========================================
             * COLUMN COUNT / STRUCTURE
             * ==========================================
             *
             * The header defines the required columns.
             * This verifies that the current row contains
             * indexes for all required fields.
             */
            if (!hasRequiredIndexes(fields)) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'Row does not contain all required columns.'
                    )
                );

                continue;
            }

            /*
             * ==========================================
             * READ CSV VALUES
             * ==========================================
             */
            String sku = getField(
                fields,
                columnMap.get('SKU')
            );

            String name = getField(
                fields,
                columnMap.get('Name')
            );

            String priceText = getField(
                fields,
                columnMap.get('Price')
            );

            String category = getField(
                fields,
                columnMap.get('Category')
            );

            String region = getField(
                fields,
                columnMap.get('Region')
            );

            /*
             * ==========================================
             * REQUIRED FIELD VALIDATION
             * ==========================================
             */

            if (String.isBlank(sku)) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'SKU is required.'
                    )
                );

                continue;
            }

            if (String.isBlank(name)) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'Name is required.'
                    )
                );

                continue;
            }

            if (String.isBlank(priceText)) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'Price is required.'
                    )
                );

                continue;
            }

            if (String.isBlank(category)) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'Category is required.'
                    )
                );

                continue;
            }

            if (String.isBlank(region)) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'Region is required.'
                    )
                );

                continue;
            }

            /*
             * ==========================================
             * DUPLICATE SKU VALIDATION
             * ==========================================
             *
             * Because this class implements
             * Database.Stateful, seenSkus survives
             * between Batch execute() calls.
             */
            if (seenSkus.contains(sku)) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'Duplicate SKU in file: ' +
                        sku
                    )
                );

                continue;
            }

            seenSkus.add(sku);

            /*
             * ==========================================
             * PRICE VALIDATION
             * ==========================================
             */
            Decimal price;

            try {

                price = Decimal.valueOf(priceText);

            } catch (Exception e) {

                rowResults.add(
                    createFailedResult(
                        rowNumber,
                        row,
                        'Price must be a valid numeric value.'
                    )
                );

                continue;
            }

            /*
             * ==========================================
             * CREATE PRODUCT
             * ==========================================
             */
            Product_Import__c product =
                new Product_Import__c();

            product.SKU__c = sku;
            product.Name = name;
            product.Price__c = price;
            product.Category__c = category;
            product.Region__c = region;

            /*
             * Add Product to bulk upsert list.
             */
            productsToUpsert.add(product);

            /*
             * Keep source-row information.
             */
            productRowNumbers.add(rowNumber);
            productRawRows.add(row);
        }

        /*
         * ==========================================
         * BULK UPSERT
         * ==========================================
         *
         * allOrNone = false
         *
         * One bad Product does NOT roll back
         * the other Products.
         */
        if (!productsToUpsert.isEmpty()) {

            Database.UpsertResult[] upsertResults =
                Database.upsert(
                    productsToUpsert,
                    Product_Import__c.SKU__c,
                    false
                );

            /*
             * Process each result individually.
             */
            for (
                Integer i = 0;
                i < upsertResults.size();
                i++
            ) {

                Database.UpsertResult result =
                    upsertResults[i];

                Integer sourceRowNumber =
                    productRowNumbers[i];

                String sourceRawRow =
                    productRawRows[i];

                /*
                 * SUCCESS
                 */
                if (result.isSuccess()) {

                    rowResults.add(
                        createSuccessResult(
                            sourceRowNumber,
                            sourceRawRow
                        )
                    );
                }

                /*
                 * FAILURE
                 */
                else {

                    String errorMessage =
                        buildDatabaseErrorMessage(
                            result
                        );

                    rowResults.add(
                        createFailedResult(
                            sourceRowNumber,
                            sourceRawRow,
                            errorMessage
                        )
                    );
                }
            }
        }

        /*
         * ==========================================
         * INSERT ROW RESULTS
         * ==========================================
         */
        if (!rowResults.isEmpty()) {

            Database.SaveResult[] resultInsertResults =
                Database.insert(
                    rowResults,
                    false
                );

            /*
             * We intentionally use allOrNone=false
             * so one result-record failure doesn't
             * destroy all other row results.
             */
        }
    }

    /*
     * ==========================================
     * FINISH
     * ==========================================
     */
    public void finish(
        Database.BatchableContext context
    ) {

        /*
         * Count successful rows.
         */
        Integer successCount = [
            SELECT COUNT()
            FROM Import_Row_Result__c
            WHERE Import_Batch__c = :batchId
            AND Status__c = 'Success'
        ];

        /*
         * Count failed rows.
         */
        Integer failureCount = [
            SELECT COUNT()
            FROM Import_Row_Result__c
            WHERE Import_Batch__c = :batchId
            AND Status__c = 'Failed'
        ];

        /*
         * Calculate total.
         */
        Integer totalRows =
            successCount + failureCount;

        /*
         * Determine final status.
         */
        String finalStatus;

        if (failureCount == 0) {

            finalStatus = 'Completed';

        } else {

            finalStatus = 'Completed with Errors';
        }

        /*
         * Update parent Import Batch.
         */
        update new Import_Batch__c(
            Id = batchId,
            Total_Rows__c = totalRows,
            Success_Count__c = successCount,
            Failure_Count__c = failureCount,
            Status__c = finalStatus
        );

        System.debug(
            'Import completed. ' +
            'Total=' + totalRows +
            ', Success=' + successCount +
            ', Failed=' + failureCount
        );
    }

    /*
     * ==========================================
     * CREATE FAILED RESULT
     * ==========================================
     */
    private Import_Row_Result__c createFailedResult(
        Integer rowNumber,
        String rawRow,
        String errorMessage
    ) {

        Import_Row_Result__c result =
            new Import_Row_Result__c();

        result.Import_Batch__c = batchId;
        result.Row_Number__c = rowNumber;
        result.Status__c = 'Failed';
        result.Error_Message__c = errorMessage;
        result.Raw_Row_Data__c = rawRow;

        return result;
    }

    /*
     * ==========================================
     * CREATE SUCCESS RESULT
     * ==========================================
     */
    private Import_Row_Result__c createSuccessResult(
        Integer rowNumber,
        String rawRow
    ) {

        Import_Row_Result__c result =
            new Import_Row_Result__c();

        result.Import_Batch__c = batchId;
        result.Row_Number__c = rowNumber;
        result.Status__c = 'Success';
        result.Error_Message__c = null;
        result.Raw_Row_Data__c = rawRow;

        return result;
    }

    /*
     * ==========================================
     * GET FIELD
     * ==========================================
     */
    private static String getField(
        List<String> fields,
        Integer index
    ) {

        if (
            index == null ||
            index < 0 ||
            index >= fields.size()
        ) {

            return '';
        }

        String value = fields[index];

        if (value == null) {

            return '';
        }

        return value.trim();
    }

    /*
     * ==========================================
     * REQUIRED INDEX VALIDATION
     * ==========================================
     */
    private Boolean hasRequiredIndexes(
        List<String> fields
    ) {

        if (
            columnMap == null ||
            columnMap.isEmpty()
        ) {

            return false;
        }

        List<String> requiredColumns =
            new List<String>{
                'SKU',
                'Name',
                'Price',
                'Category',
                'Region'
            };

        for (String columnName : requiredColumns) {

            Integer index =
                columnMap.get(columnName);

            if (
                index == null ||
                index < 0 ||
                index >= fields.size()
            ) {

                return false;
            }
        }

        return true;
    }

    /*
     * ==========================================
     * BLANK ROW CHECK
     * ==========================================
     */
    private Boolean isBlankRow(
        List<String> fields
    ) {

        for (String field : fields) {

            if (!String.isBlank(field)) {

                return false;
            }
        }

        return true;
    }

    /*
     * ==========================================
     * DATABASE ERROR MESSAGE
     * ==========================================
     */
    private String buildDatabaseErrorMessage(
        Database.UpsertResult result
    ) {

        List<String> messages =
            new List<String>();

        for (
            Database.Error error :
            result.getErrors()
        ) {

            String message =
                error.getMessage();

            if (String.isBlank(message)) {

                message =
                    'Unknown Salesforce error.';
            }

            messages.add(message);
        }

        if (messages.isEmpty()) {

            return 'Product upsert failed.';
        }

        return String.join(
            messages,
            ' | '
        );
    }

    /*
     * ==========================================
     * CSV PARSER
     * ==========================================
     *
     * Handles:
     * - commas
     * - quoted values
     * - commas inside quotes
     * - escaped quotes
     * - empty fields
     * - mismatched quotes
     */
    private static List<String> parseCsvLine(
        String line
    ) {

        List<String> fields =
            new List<String>();

        if (line == null) {

            fields.add('');

            return fields;
        }

        /*
         * Fast Path: Native split for unquoted lines (100x faster Apex CPU speed).
         */
        if (!line.contains('"')) {

            return line.split(',', -1);
        }

        String currentField = '';

        Boolean insideQuotes = false;

        for (
            Integer i = 0;
            i < line.length();
            i++
        ) {

            String character =
                line.substring(
                    i,
                    i + 1
                );

            /*
             * QUOTE
             */
            if (character == '"') {

                /*
                 * Escaped quote:
                 *
                 * ""
                 *
                 * becomes:
                 *
                 * "
                 */
                if (
                    insideQuotes &&
                    i + 1 < line.length() &&
                    line.substring(
                        i + 1,
                        i + 2
                    ) == '"'
                ) {

                    currentField += '"';

                    i++;

                } else {

                    insideQuotes =
                        !insideQuotes;
                }
            }

            /*
             * COMMA OUTSIDE QUOTES
             */
            else if (
                character == ',' &&
                !insideQuotes
            ) {

                fields.add(
                    currentField
                );

                currentField = '';
            }

            /*
             * NORMAL CHARACTER
             */
            else {

                currentField += character;
            }
        }

        /*
         * MISMATCHED QUOTES
         */
        if (insideQuotes) {

            throw new CsvParseException(
                'Mismatched quotation marks.'
            );
        }

        /*
         * Add final field.
         */
        fields.add(
            currentField
        );

        return fields;
    }

    /*
     * ==========================================
     * CUSTOM EXCEPTION
     * ==========================================
     */
    public class CsvParseException
        extends Exception {
    }
}
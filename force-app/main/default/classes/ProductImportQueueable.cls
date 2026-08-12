public with sharing class ProductImportQueueable implements Queueable {

    private Id batchId;
    private Id contentVersionId;

    /*
     * Constructor
     */
    public ProductImportQueueable(
        Id batchId,
        Id contentVersionId
    ) {
        this.batchId = batchId;
        this.contentVersionId = contentVersionId;
    }

    /*
     * ==========================================
     * EXECUTE
     * ==========================================
     */
    public void execute(
        QueueableContext context
    ) {

        ContentVersion cv;

        /*
         * Read uploaded file.
         */
        try {

            cv = [
                SELECT
                    Id,
                    VersionData,
                    Title,
                    FileExtension
                FROM ContentVersion
                WHERE Id = :contentVersionId
                LIMIT 1
            ];

        } catch (Exception e) {

            updateBatchAsFailed(
                'Unable to read the uploaded file: ' +
                e.getMessage()
            );

            return;
        }

        /*
         * ==========================================
         * READ CSV CONTENT
         * ==========================================
         */
        String csvText;

        try {

            csvText =
                cv.VersionData.toString();

        } catch (Exception e) {

            updateBatchAsFailed(
                'Unable to read the uploaded CSV file.'
            );

            return;
        }

        /*
         * Check empty file.
         */
        if (String.isBlank(csvText)) {

            updateBatchAsFailed(
                'The uploaded CSV file is empty.'
            );

            return;
        }

        /*
         * ==========================================
         * SPLIT CSV INTO ROWS
         * ==========================================
         *
         * This version handles normal CSV records
         * separated by physical lines.
         *
         * The Batch class handles quoted commas
         * and escaped quotes inside each row.
         */
        List<String> lines;

        try {

            lines =
                csvText.split('\\r?\\n');

        } catch (Exception e) {

            updateBatchAsFailed(
                'Unable to split the CSV into rows: ' +
                e.getMessage()
            );

            return;
        }

        /*
         * Check that at least a header exists.
         */
        if (
            lines == null ||
            lines.isEmpty()
        ) {

            updateBatchAsFailed(
                'No CSV rows were found.'
            );

            return;
        }

        /*
         * ==========================================
         * PARSE HEADER
         * ==========================================
         */
        String headerLine =
            lines[0];

        List<String> headers;

        try {

            headers =
                parseCsvLine(headerLine);

        } catch (CsvParseException e) {

            updateBatchAsFailed(
                'CSV header parsing error: ' +
                e.getMessage()
            );

            return;
        } catch (Exception e) {

            updateBatchAsFailed(
                'Unable to parse CSV header: ' +
                e.getMessage()
            );

            return;
        }

        /*
         * ==========================================
         * REQUIRED COLUMNS
         * ==========================================
         */
        List<String> requiredColumns =
            new List<String>{
                'SKU',
                'Name',
                'Price',
                'Category',
                'Region'
            };

        /*
         * ==========================================
         * BUILD COLUMN MAP
         * ==========================================
         *
         * Example:
         *
         * SKU       -> 0
         * Name      -> 1
         * Price     -> 2
         * Category  -> 3
         * Region    -> 4
         */
        Map<String, Integer> columnMap =
            new Map<String, Integer>();

        /*
         * Detect duplicate headers.
         */
        Set<String> duplicateHeaders =
            new Set<String>();

        for (
            Integer i = 0;
            i < headers.size();
            i++
        ) {

            String header =
                headers[i];

            if (header == null) {

                continue;
            }

            String normalizedHeader =
                header.trim();

            /*
             * Ignore completely blank headers.
             */
            if (
                String.isBlank(
                    normalizedHeader
                )
            ) {

                continue;
            }

            /*
             * Duplicate column name.
             */
            if (
                columnMap.containsKey(
                    normalizedHeader
                )
            ) {

                duplicateHeaders.add(
                    normalizedHeader
                );

            } else {

                columnMap.put(
                    normalizedHeader,
                    i
                );
            }
        }

        /*
         * ==========================================
         * DUPLICATE HEADER VALIDATION
         * ==========================================
         */
        if (!duplicateHeaders.isEmpty()) {

            updateBatchAsFailed(
                'Duplicate CSV header(s): ' +
                String.join(
                    new List<String>(
                        duplicateHeaders
                    ),
                    ', '
                )
            );

            return;
        }

        /*
         * ==========================================
         * REQUIRED COLUMN VALIDATION
         * ==========================================
         */
        List<String> missingColumns =
            new List<String>();

        for (
            String requiredColumn :
            requiredColumns
        ) {

            if (
                !columnMap.containsKey(
                    requiredColumn
                )
            ) {

                missingColumns.add(
                    requiredColumn
                );
            }
        }

        /*
         * Missing required columns.
         */
        if (!missingColumns.isEmpty()) {

            updateBatchAsFailed(
                'Missing required column(s): ' +
                String.join(
                    missingColumns,
                    ', '
                )
            );

            return;
        }

        /*
         * ==========================================
         * HEADER STRUCTURE VALIDATION
         * ==========================================
         *
         * At minimum, the CSV must have the
         * five required columns.
         */
        if (headers.size() < 5) {

            updateBatchAsFailed(
                'CSV header contains fewer than 5 columns.'
            );

            return;
        }

        /*
         * ==========================================
         * REMOVE HEADER
         * ==========================================
         */
        lines.remove(0);

        /*
         * ==========================================
         * COUNT SOURCE ROWS
         * ==========================================
         */
        Integer totalRows =
            lines.size();

        /*
         * ==========================================
         * UPDATE IMPORT BATCH
         * ==========================================
         */
        try {

            update new Import_Batch__c(
                Id = batchId,
                Status__c = 'Processing',
                Total_Rows__c = totalRows,
                Success_Count__c = 0,
                Failure_Count__c = 0
            );

        } catch (Exception e) {

            updateBatchAsFailed(
                'Unable to update Import Batch: ' +
                e.getMessage()
            );

            return;
        }

        /*
         * ==========================================
         * START BATCH APEX
         * ==========================================
         *
         * IMPORTANT:
         *
         * The Batch constructor now expects:
         *
         * 1. batchId
         * 2. lines
         * 3. columnMap
         */
        try {

            Database.executeBatch(
                new ProductImportBatch(
                    batchId,
                    lines,
                    columnMap
                ),
                2000
            );

        } catch (Exception e) {

            updateBatchAsFailed(
                'Unable to start Batch Apex: ' +
                e.getMessage()
            );

            return;
        }
    }

    /*
     * ==========================================
     * CSV PARSER
     * ==========================================
     *
     * Handles:
     *
     * - normal comma-separated fields
     * - quoted fields
     * - commas inside quotes
     * - escaped quotes
     * - empty fields
     * - mismatched quotation marks
     */
    private static List<String> parseCsvLine(
        String line
    ) {

        List<String> fields =
            new List<String>();

        /*
         * Null line.
         */
        if (line == null) {

            fields.add('');

            return fields;
        }

        /*
         * Fast Path: Native split for unquoted lines.
         */
        if (!line.contains('"')) {

            return line.split(',', -1);
        }

        String currentField = '';

        Boolean insideQuotes = false;

        /*
         * Read every character.
         */
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
             * ======================================
             * QUOTE
             * ======================================
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

                    /*
                     * Skip second quote.
                     */
                    i++;

                } else {

                    /*
                     * Start or end quoted field.
                     */
                    insideQuotes =
                        !insideQuotes;
                }
            }

            /*
             * ======================================
             * COMMA OUTSIDE QUOTES
             * ======================================
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
             * ======================================
             * NORMAL CHARACTER
             * ======================================
             */
            else {

                currentField +=
                    character;
            }
        }

        /*
         * ==========================================
         * MISMATCHED QUOTES
         * ==========================================
         */
        if (insideQuotes) {

            throw new CsvParseException(
                'Mismatched quotation marks in CSV header.'
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
     * UPDATE BATCH AS FAILED
     * ==========================================
     */
    private void updateBatchAsFailed(
        String errorMessage
    ) {

        try {

            update new Import_Batch__c(
                Id = batchId,
                Status__c = 'Completed with Errors',
                Total_Rows__c = 0,
                Success_Count__c = 0,
                Failure_Count__c = 0
            );

        } catch (Exception e) {

            System.debug(
                'Unable to update Import Batch: ' +
                e.getMessage()
            );
        }

        System.debug(
            'Import failed: ' +
            errorMessage
        );
    }

    /*
     * ==========================================
     * CUSTOM CSV EXCEPTION
     * ==========================================
     */
    public class CsvParseException
        extends Exception {
    }
}
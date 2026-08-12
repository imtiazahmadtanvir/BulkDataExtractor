public with sharing class ProductImportBatch
    implements Database.Batchable<String> {

    private Id batchId;
    private List<String> rows;

    public ProductImportBatch(Id batchId, List<String> rows) {
        this.batchId = batchId;
        this.rows = rows;
    }

    /*
     * START
     *
     * Provides CSV rows to Batch Apex.
     */
    public Iterable<String> start(Database.BatchableContext context) {
        return rows;
    }

    /*
     * EXECUTE
     *
     * For now, we only parse each CSV row.
     * Validation and upsert will be added next.
     */
    public void execute(
        Database.BatchableContext context,
        List<String> scope
    ) {

        for (String row : scope) {

            List<String> fields = parseCsvLine(row);

            System.debug('Original Row: ' + row);
            System.debug('Parsed Fields: ' + fields);
        }
    }

    /*
     * FINISH
     */
    public void finish(Database.BatchableContext context) {

        System.debug(
            'Batch finished for Import Batch: ' + batchId
        );
    }

    /*
     * CSV PARSER
     *
     * Handles:
     * 1. Normal commas
     * 2. Commas inside quotes
     * 3. Quoted fields
     * 4. Escaped quotes ("")
     * 5. Empty fields
     */
    private static List<String> parseCsvLine(String line) {

        List<String> fields = new List<String>();

        if (line == null) {
            fields.add('');
            return fields;
        }

        String currentField = '';
        Boolean insideQuotes = false;

        for (Integer i = 0; i < line.length(); i++) {

            String character = line.substring(i, i + 1);

            /*
             * Handle quotation marks
             */
            if (character == '"') {

                /*
                 * If we are already inside quotes and
                 * the next character is also a quote,
                 * this represents an escaped quote.
                 *
                 * Example:
                 * "Dell ""Inspiron"" Laptop"
                 */
                if (insideQuotes &&
                    i + 1 < line.length() &&
                    line.substring(i + 1, i + 2) == '"') {

                    currentField += '"';

                    // Skip the second quote
                    i++;

                } else {

                    // Start or end quoted section
                    insideQuotes = !insideQuotes;
                }

            }

            /*
             * Comma outside quotes = field separator
             */
            else if (character == ',' && !insideQuotes) {

                fields.add(currentField);
                currentField = '';
            }

            /*
             * Normal character
             */
            else {

                currentField += character;
            }
        }

        /*
         * Add final field.
         *
         * This is important because CSV rows do not
         * end with a comma.
         */
        fields.add(currentField);

        return fields;
    }
}
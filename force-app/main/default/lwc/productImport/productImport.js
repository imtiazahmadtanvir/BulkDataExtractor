import { LightningElement } from 'lwc';

import uploadCsv
    from '@salesforce/apex/ProductImportController.uploadCsv';

import getImportBatch
    from '@salesforce/apex/ProductImportController.getImportBatch';

import getRowResults
    from '@salesforce/apex/ProductImportController.getRowResults';

import { ShowToastEvent }
    from 'lightning/platformShowToastEvent';


export default class ProductImport extends LightningElement {

    fileName = '';

    base64Data = '';

    batchId = null;

    isProcessing = false;

    isReadingFile = false;

    errorMessage = '';

    successMessage = '';

    importBatch = null;

    rowResults = [];

    selectedFilter = 'All';


    // ============================================================
    // Upload button state
    // ============================================================

    get isUploadDisabled() {

        return (
            !this.base64Data ||
            this.isProcessing ||
            this.isReadingFile
        );
    }


    // ============================================================
    // File selection
    // ============================================================

    handleFileChange(event) {

        this.fileName = '';
        this.base64Data = '';

        this.batchId = null;

        this.importBatch = null;

        this.rowResults = [];

        this.errorMessage = '';

        this.successMessage = '';

        const files = event.target.files;

        if (!files || files.length === 0) {

            return;
        }

        const file = files[0];

        console.log(
            'Selected file:',
            file.name
        );

        console.log(
            'File size:',
            file.size
        );

        // Only CSV
        if (
            !file.name
                .toLowerCase()
                .endsWith('.csv')
        ) {

            this.errorMessage =
                'Only CSV files are allowed.';

            return;
        }

        // Empty physical file
        if (file.size === 0) {

            this.errorMessage =
                'The selected file is empty.';

            return;
        }

        this.fileName = file.name;

        this.isReadingFile = true;

        /*
         * Read the file as Base64.
         */
        const reader = new FileReader();

        reader.onload = () => {

            try {

                const result = reader.result;

                console.log(
                    'FileReader result received.'
                );

                if (!result) {

                    throw new Error(
                        'FileReader returned empty data.'
                    );
                }

                /*
                 * Data URL looks like:
                 *
                 * data:text/csv;base64,SGt...
                 *
                 * We need only the Base64 part.
                 */
                const commaIndex =
                    result.indexOf(',');

                if (commaIndex === -1) {

                    throw new Error(
                        'Invalid Base64 data received from the file.'
                    );
                }

                const base64 =
                    result.substring(
                        commaIndex + 1
                    );

                if (!base64) {

                    throw new Error(
                        'Base64 conversion returned empty data.'
                    );
                }

                this.base64Data = base64;

                this.isReadingFile = false;

                console.log(
                    'Base64 length:',
                    this.base64Data.length
                );

                this.successMessage =
                    'File loaded successfully. Ready to upload.';

            } catch (error) {

                console.error(
                    'File processing error:',
                    error
                );

                this.base64Data = '';

                this.isReadingFile = false;

                this.errorMessage =
                    error.message ||
                    'Unable to read the CSV file.';
            }
        };


        reader.onerror = () => {

            console.error(
                'FileReader error:',
                reader.error
            );

            this.base64Data = '';

            this.isReadingFile = false;

            this.errorMessage =
                'Unable to read the selected CSV file.';
        };


        reader.onabort = () => {

            this.base64Data = '';

            this.isReadingFile = false;

            this.errorMessage =
                'CSV file reading was cancelled.';
        };


        reader.readAsDataURL(file);
    }


    // ============================================================
    // Upload CSV
    // ============================================================

    async handleUpload() {

        this.errorMessage = '';

        this.successMessage = '';

        /*
         * Important safety check.
         */
        if (!this.fileName) {

            this.errorMessage =
                'Please select a CSV file first.';

            return;
        }

        if (!this.base64Data) {

            this.errorMessage =
                'The CSV file has not finished loading. Please wait a moment and try again.';

            return;
        }

        console.log(
            'Uploading file:',
            this.fileName
        );

        console.log(
            'Base64 length before upload:',
            this.base64Data.length
        );

        this.isProcessing = true;

        try {

            const result =
                await uploadCsv({

                    fileName:
                        this.fileName,

                    base64Data:
                        this.base64Data
                });

            console.log(
                'Import Batch Id:',
                result
            );

            this.batchId = result;

            this.successMessage =
                'CSV uploaded successfully. Processing has started.';

            this.showToast(
                'Upload Started',
                this.successMessage,
                'success'
            );

            /*
             * Check asynchronous processing.
             */
            await this.checkImportStatus();

        } catch (error) {

            console.error(
                'Upload error:',
                error
            );

            this.errorMessage =
                this.getErrorMessage(error);

            this.isProcessing = false;

            this.showToast(
                'Upload Failed',
                this.errorMessage,
                'error'
            );
        }
    }


    // ============================================================
    // Check Batch Status
    // ============================================================

    async checkImportStatus() {

        if (!this.batchId) {

            return;
        }

        try {

            const batch =
                await getImportBatch({

                    batchId:
                        this.batchId
                });

            this.importBatch = batch;

            console.log(
                'Import status:',
                batch.Status__c
            );

            if (
                batch.Status__c === 'Queued' ||
                batch.Status__c === 'Processing'
            ) {

                this.isProcessing = true;

                setTimeout(() => {

                    this.checkImportStatus();

                }, 2000);

                return;
            }

            this.isProcessing = false;

            await this.loadRowResults();

            if (
                batch.Status__c === 'Completed'
            ) {

                this.successMessage =
                    'Import completed successfully.';

            } else {

                this.successMessage =
                    'Import completed with errors.';
            }

        } catch (error) {

            console.error(
                'Status error:',
                error
            );

            this.errorMessage =
                this.getErrorMessage(error);

            this.isProcessing = false;
        }
    }


    // ============================================================
    // Load Row Results
    // ============================================================

    async loadRowResults() {

        if (!this.batchId) {

            return;
        }

        try {

            this.rowResults =
                await getRowResults({

                    batchId:
                        this.batchId
                });

        } catch (error) {

            console.error(
                'Result loading error:',
                error
            );

            this.errorMessage =
                this.getErrorMessage(error);
        }
    }


    // ============================================================
    // Filter
    // ============================================================

    handleFilterChange(event) {

        this.selectedFilter =
            event.target.dataset.filter;
    }


    get filteredResults() {

        if (
            this.selectedFilter === 'Success'
        ) {

            return this.rowResults.filter(
                row =>
                    row.Status__c ===
                    'Success'
            );
        }

        if (
            this.selectedFilter === 'Failed'
        ) {

            return this.rowResults.filter(
                row =>
                    row.Status__c ===
                    'Failed'
            );
        }

        return this.rowResults;
    }


    // ============================================================
    // Error message
    // ============================================================

    getErrorMessage(error) {

        if (
            error &&
            error.body &&
            error.body.message
        ) {

            return error.body.message;
        }

        if (
            error &&
            error.message
        ) {

            return error.message;
        }

        return 'An unexpected error occurred.';
    }


    // ============================================================
    // Toast
    // ============================================================

    showToast(
        title,
        message,
        variant
    ) {

        this.dispatchEvent(
            new ShowToastEvent({

                title: title,

                message: message,

                variant: variant
            })
        );
    }
}
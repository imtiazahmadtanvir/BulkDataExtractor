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


    /*
     * Datatable columns
     */
    columns = [

        {
            label: 'Row Number',
            fieldName: 'Row_Number__c',
            type: 'number'
        },

        {
            label: 'Status',
            fieldName: 'Status__c',
            type: 'text'
        },

        {
            label: 'Error Message',
            fieldName: 'Error_Message__c',
            type: 'text',
            wrapText: true
        },

        {
            label: 'Raw Row Data',
            fieldName: 'Raw_Row_Data__c',
            type: 'text',
            wrapText: true
        }

    ];



    /*
     * Upload button control
     */
    get isUploadDisabled() {

        return (

            !this.base64Data ||

            this.isProcessing ||

            this.isReadingFile

        );
    }




    /*
     * File Selection
     */
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



        if (

            !file.name
                .toLowerCase()
                .endsWith('.csv')

        ) {


            this.errorMessage =
                'Only CSV files are allowed.';


            return;

        }




        if (file.size === 0) {


            this.errorMessage =
                'The selected file is empty.';


            return;

        }




        this.fileName = file.name;


        this.isReadingFile = true;



        const reader = new FileReader();



        reader.onload = () => {


            const result = reader.result;



            const commaIndex =
                result.indexOf(',');



            if (commaIndex === -1) {


                this.errorMessage =
                    'Unable to convert file.';


                this.isReadingFile = false;


                return;

            }




            this.base64Data =
                result.substring(
                    commaIndex + 1
                );



            this.isReadingFile = false;



            this.successMessage =
                'File loaded successfully. Ready to upload.';


        };




        reader.onerror = () => {


            this.errorMessage =
                'Unable to read file.';


            this.isReadingFile = false;


        };



        reader.readAsDataURL(file);

    }





    /*
     * Upload CSV
     */
    async handleUpload() {


        this.errorMessage = '';

        this.successMessage = '';



        if (!this.base64Data) {


            this.errorMessage =
                'Please select a CSV file first.';


            return;

        }




        this.isProcessing = true;



        try {



            const result =

                await uploadCsv({

                    fileName:
                        this.fileName,


                    base64Data:
                        this.base64Data

                });




            this.batchId = result;



            this.successMessage =

                'CSV uploaded successfully. Processing started.';



            this.showToast(

                'Upload Started',

                this.successMessage,

                'success'

            );




            await this.checkImportStatus();




        }

        catch(error) {



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





    /*
     * Check Batch Status
     */
    async checkImportStatus() {


        const batch =

            await getImportBatch({

                batchId:
                    this.batchId

            });



        this.importBatch = batch;




        if (

            batch.Status__c === 'Queued'

            ||

            batch.Status__c === 'Processing'

        ) {


            this.isProcessing = true;



            setTimeout(

                () => {

                    this.checkImportStatus();

                },

                2000

            );



            return;

        }





        this.isProcessing = false;



        await this.loadRowResults();




        if (

            batch.Status__c === 'Completed'

        ) {



            this.successMessage =
                'Import completed successfully.';


        }

        else {


            this.successMessage =
                'Import completed with errors.';


        }


    }






    /*
     * Load Row Results
     */
    async loadRowResults() {

        this.rowResults =
            await getRowResults({
                batchId: this.batchId,
                filterStatus: this.selectedFilter
            });
    }


    /*
     * Filter
     */
    async handleFilterChange(event) {

        this.selectedFilter =
            event.target.dataset.filter;

        await this.loadRowResults();
    }


    get filteredResults() {

        return this.rowResults || [];
    }

    get isAllVariant() {
        return this.selectedFilter === 'All' ? 'brand' : 'neutral';
    }

    get isSuccessVariant() {
        return this.selectedFilter === 'Success' ? 'brand' : 'neutral';
    }

    get isFailedVariant() {
        return this.selectedFilter === 'Failed' ? 'brand' : 'neutral';
    }

    get statusBadgeClass() {
        if (!this.importBatch) return 'status-badge';
        switch (this.importBatch.Status__c) {
            case 'Completed':
                return 'status-badge status-completed';
            case 'Completed with Errors':
                return 'status-badge status-errors';
            case 'Processing':
                return 'status-badge status-processing';
            default:
                return 'status-badge status-queued';
        }
    }

    get hasResults() {
        return this.filteredResults && this.filteredResults.length > 0;
    }

    get isResultEmpty() {
        return this.importBatch && (!this.filteredResults || this.filteredResults.length === 0);
    }






    /*
     * Error Handler
     */
    getErrorMessage(error) {


        if (

            error.body &&

            error.body.message

        ) {


            return error.body.message;


        }



        return 'Unexpected error occurred.';


    }






    /*
     * Toast
     */
    showToast(

        title,

        message,

        variant

    ) {



        this.dispatchEvent(

            new ShowToastEvent({

                title,

                message,

                variant

            })

        );

    }


}
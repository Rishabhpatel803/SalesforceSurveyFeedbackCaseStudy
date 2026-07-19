global with sharing class NightlySurveyAggregationBatch
implements Database.Batchable<SObject>, Schedulable {

    global Database.QueryLocator start(Database.BatchableContext bc) {

        return Database.getQueryLocator([
            SELECT Id
            FROM Tour_Package__c
            WHERE Id IN (
                SELECT Tour_Package__c
                FROM Travel_Booking__c
                WHERE Survey_Completed__c = TRUE
            )
        ]);
    }

    global void execute(Database.BatchableContext bc,
                        List<Tour_Package__c> scope) {

        Set<Id> packageIds = new Set<Id>();

        for(Tour_Package__c tp : scope){
            packageIds.add(tp.Id);
        }

        Map<Id, AggregateResult> aggregateMap = new Map<Id, AggregateResult>();

        for(AggregateResult ar : [

            SELECT
                Tour_Package__c packageId,
                AVG(Average_Rating__c) avgRating,
                COUNT(Id) totalResponses,
                AVG(NPS_Score__c) avgNPS

            FROM Travel_Booking__c

            WHERE Tour_Package__c IN :packageIds
            AND Survey_Completed__c = TRUE

            GROUP BY Tour_Package__c

        ]){

            aggregateMap.put(
                (Id)ar.get('packageId'),
                ar
            );
        }

        List<Tour_Package__c> updates = new List<Tour_Package__c>();

        for(Id packageId : packageIds){

            AggregateResult ar = aggregateMap.get(packageId);

            if(ar == null)
                continue;

            Double avgRating = (Double)ar.get('avgRating');
            Double avgNps = (Double)ar.get('avgNPS');

            updates.add(new Tour_Package__c(

                Id = packageId,

                Average_Rating__c =
                    avgRating == null
                    ? null
                    : Decimal.valueOf(avgRating).setScale(2),

                Total_Responses__c =
                    (Integer)ar.get('totalResponses'),

                NPS__c =
                    avgNps == null
                    ? null
                    : Decimal.valueOf(avgNps).setScale(2)

            ));
        }

        if(!updates.isEmpty()){
            update updates;
        }
    }

    global void finish(Database.BatchableContext bc){

        Messaging.SingleEmailMessage email =
            new Messaging.SingleEmailMessage();

        email.setToAddresses(
            new String[]{
                UserInfo.getUserEmail()
            });

        email.setSubject('Nightly Survey Aggregation Completed');

        email.setPlainTextBody(
            'Nightly survey aggregation completed successfully.'
        );

        Messaging.sendEmail(
            new Messaging.SingleEmailMessage[]{email}
        );
    }

    global void execute(SchedulableContext sc){

        Database.executeBatch(
            new NightlySurveyAggregationBatch(),
            200
        );
    }


    /*
    System.schedule(
        'Nightly Survey Aggregation',
        '0 0 1 * * ?',
        new NightlySurveyAggregationBatch()
    );
    */
}
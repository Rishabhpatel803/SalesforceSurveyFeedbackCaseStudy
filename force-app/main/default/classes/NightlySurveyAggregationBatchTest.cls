@isTest
private class NightlySurveyAggregationBatchTest {

    @testSetup
    static void setupData() {

        Account acc = new Account(
            Name = 'Test Account'
        );
        insert acc;

        Contact con = new Contact(
            FirstName = 'John',
            LastName = 'Doe',
            AccountId = acc.Id
        );
        insert con;

        List<Tour_Package__c> packages = new List<Tour_Package__c>();

        packages.add(new Tour_Package__c(
            Name='Goa Package',
            Category__c='Beach',
            Destination__c='Goa'
        ));

        packages.add(new Tour_Package__c(
            Name='Manali Package',
            Category__c='Mountains',
            Destination__c='Manali'
        ));

        insert packages;

        List<Travel_Booking__c> bookings = new List<Travel_Booking__c>();

        // Package 1 - Completed Surveys
        bookings.add(new Travel_Booking__c(
            Contact__c = con.Id,
            Status__c = 'Completed',   // Replace with a valid picklist value
            Tour_Package__c = packages[0].Id,
            Survey_Completed__c = true,
            Average_Rating__c = 4,
            NPS_Score__c = 9
        ));

        bookings.add(new Travel_Booking__c(
            Contact__c = con.Id,
            Status__c = 'Completed',
            Tour_Package__c=packages[0].Id,
            Survey_Completed__c=true,
            Average_Rating__c=5,
            NPS_Score__c=10
        ));

        bookings.add(new Travel_Booking__c(
            Contact__c = con.Id,
            Status__c = 'Completed',
            Tour_Package__c=packages[0].Id,
            Survey_Completed__c=true,
            Average_Rating__c=3,
            NPS_Score__c=8
        ));

        // Package 2
        bookings.add(new Travel_Booking__c(
            Contact__c = con.Id,
            Status__c = 'Completed',
            Tour_Package__c=packages[1].Id,
            Survey_Completed__c=true,
            Average_Rating__c=2,
            NPS_Score__c=5
        ));

        // Not completed survey
        bookings.add(new Travel_Booking__c(
            Contact__c = con.Id,
            Status__c = 'Completed',
            Tour_Package__c=packages[1].Id,
            Survey_Completed__c=false,
            Average_Rating__c=5,
            NPS_Score__c=10
        ));

        insert bookings;
    }

    @isTest
    static void testBatchExecution() {

        Test.startTest();

        Database.executeBatch(
            new NightlySurveyAggregationBatch(),
            200
        );

        Test.stopTest();

        Map<String,Tour_Package__c> packageMap =
            new Map<String,Tour_Package__c>();

        for(Tour_Package__c tp : [
            SELECT Name,
                   Average_Rating__c,
                   Total_Responses__c,
                   NPS__c
            FROM Tour_Package__c
        ]){
            packageMap.put(tp.Name,tp);
        }

        Tour_Package__c goa = packageMap.get('Goa Package');

        System.assertEquals(
            4.00,
            goa.Average_Rating__c
        );

        System.assertEquals(
            3,
            goa.Total_Responses__c
        );

        System.assertEquals(
            9.00,
            goa.NPS__c
        );

        Tour_Package__c manali = packageMap.get('Manali Package');

        System.assertEquals(
            2.00,
            manali.Average_Rating__c
        );

        System.assertEquals(
            1,
            manali.Total_Responses__c
        );

        System.assertEquals(
            5.00,
            manali.NPS__c
        );
    }

    @isTest
    static void testScheduler() {

        Test.startTest();

        String jobId = System.schedule(
            'Nightly Batch Test',
            '0 0 1 * * ?',
            new NightlySurveyAggregationBatch()
        );

        Test.stopTest();

        CronTrigger ct = [
            SELECT Id,
                   CronExpression,
                   State
            FROM CronTrigger
            WHERE Id=:jobId
        ];

        System.assertEquals(
            '0 0 1 * * ?',
            ct.CronExpression
        );
    }

    @isTest
    static void testNoCompletedSurveys() {

        Tour_Package__c pkg = new Tour_Package__c(
            Name='Empty Package',
            Category__c='Adventure',
            Destination__c='Leh'
        );

        insert pkg;

        Contact con = [
            SELECT Id
            FROM Contact
            LIMIT 1
        ];

        insert new Travel_Booking__c(
            Contact__c = con.Id,
            Status__c = 'Completed',
            Tour_Package__c = pkg.Id,
            Survey_Completed__c = false
        );

        Test.startTest();

        Database.executeBatch(
            new NightlySurveyAggregationBatch(),
            200
        );

        Test.stopTest();

        pkg = [
            SELECT Average_Rating__c,
                   Total_Responses__c,
                   NPS__c
            FROM Tour_Package__c
            WHERE Id=:pkg.Id
        ];

        System.assertEquals(
            null,
            pkg.Average_Rating__c
        );

        System.assertEquals(
            null,
            pkg.Total_Responses__c
        );

        System.assertEquals(
            null,
            pkg.NPS__c
        );
    }

    @isTest
    static void testSingleBookingAggregation() {

        Tour_Package__c pkg = new Tour_Package__c(
            Name='Single Booking Package',
            Category__c='Wildlife',
            Destination__c='Kabini'
        );

        insert pkg;

        Contact con = [
            SELECT Id
            FROM Contact
            LIMIT 1
        ];

        insert new Travel_Booking__c(
            Contact__c = con.Id,
            Status__c = 'Completed',
            Tour_Package__c = pkg.Id,
            Survey_Completed__c = true,
            Average_Rating__c = 4,
            NPS_Score__c = 7
        );

        Test.startTest();

        Database.executeBatch(
            new NightlySurveyAggregationBatch(),
            200
        );

        Test.stopTest();

        pkg = [
            SELECT Average_Rating__c,
                   Total_Responses__c,
                   NPS__c
            FROM Tour_Package__c
            WHERE Id=:pkg.Id
        ];

        System.assertEquals(
            4,
            pkg.Average_Rating__c
        );

        System.assertEquals(
            1,
            pkg.Total_Responses__c
        );

        System.assertEquals(
            7,
            pkg.NPS__c
        );
    }
}
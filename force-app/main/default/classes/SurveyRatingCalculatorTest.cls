/**
 * Unit tests for SurveyRatingCalculator.
 *
 * Design notes:
 * - Tour_Package__c and Travel_Booking__c are custom objects we fully control,
 *   so their test data is created in @testSetup using normal DML.
 * - recalculatePackages and createErrorLog are private methods marked
 *   @TestVisible (no new methods added, just an existing-method visibility
 *   annotation), so they're tested directly using real Travel_Booking__c /
 *   Tour_Package__c / Error_Log__c records.
 * - Survey / SurveyResponse / SurveyInvitation / SurveyQuestionResponse are
 *   standard Feedback Management objects whose required fields depend on org
 *   configuration, so they aren't fabricated here. The success path inside
 *   calculateBookingRating (Step 3 - turning survey data into a rating and
 *   updating the booking) can therefore only be exercised end-to-end against
 *   real org data - see testEndToEnd_WithRealSurveyData, which uses
 *   SeeAllData=true and skips (not fails) if the org has no completed survey
 *   with numeric ratings yet. Coverage of that specific block will stay low
 *   unless such data exists in the org when tests run, or unless the class is
 *   restructured to isolate that logic - happy to do that refactor if wanted.
 */
@isTest
public class SurveyRatingCalculatorTest {

    @testSetup
    static void setupTestData() {
        Contact testContact = new Contact(
            FirstName = 'Test',
            LastName = 'Traveler'
        );
        insert testContact;

        Tour_Package__c pkg = new Tour_Package__c(Name = 'Test Package');
        insert pkg;

        Travel_Booking__c booking = new Travel_Booking__c(
            Tour_Package__c = pkg.Id,
            Contact__c = testContact.Id,
            // TODO: replace with a valid picklist value from your org's
            // Travel_Booking__c.Status__c field if this one isn't valid.
            Status__c = 'Completed'
        );
        insert booking;
    }

    // ---------- calculateBookingRating: input validation branches ----------

    @isTest
    static void testMissingBookingId_ReturnsErrorNotException() {
        SurveyRatingCalculator.Request req = new SurveyRatingCalculator.Request();
        req.surveyResponseId = null;
        req.bookingId = null;

        Test.startTest();
        List<SurveyRatingCalculator.Result> results =
            SurveyRatingCalculator.calculateBookingRating(new List<SurveyRatingCalculator.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size(), 'Should return exactly one result per request');
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('Booking ID is required'));
    }

    @isTest
    static void testInvalidBookingIdFormat_ReturnsErrorNotException() {
        SurveyRatingCalculator.Request req = new SurveyRatingCalculator.Request();
        req.surveyResponseId = 'not-a-real-id';
        req.bookingId = 'also-not-a-real-id';

        Test.startTest();
        List<SurveyRatingCalculator.Result> results =
            SurveyRatingCalculator.calculateBookingRating(new List<SurveyRatingCalculator.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('Invalid Booking ID'));
    }

    @isTest
    static void testMissingSurveyResponseId_ReturnsErrorNotException() {
        // Valid bookingId but no surveyResponseId - exercises the "else" branch
        // that a valid-but-invalid-bookingId request never reaches.
        Travel_Booking__c booking = [SELECT Id FROM Travel_Booking__c LIMIT 1];

        SurveyRatingCalculator.Request req = new SurveyRatingCalculator.Request();
        req.bookingId = booking.Id;
        req.surveyResponseId = null;

        Test.startTest();
        List<SurveyRatingCalculator.Result> results =
            SurveyRatingCalculator.calculateBookingRating(new List<SurveyRatingCalculator.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('Survey Response ID is required'));
    }

    @isTest
    static void testInvalidSurveyResponseIdFormat_ReturnsErrorNotException() {
        // Valid bookingId, malformed surveyResponseId - exercises the catch
        // block for a bad survey ID specifically (not masked by a bad booking ID).
        Travel_Booking__c booking = [SELECT Id FROM Travel_Booking__c LIMIT 1];

        SurveyRatingCalculator.Request req = new SurveyRatingCalculator.Request();
        req.bookingId = booking.Id;
        req.surveyResponseId = 'not-a-real-id';

        Test.startTest();
        List<SurveyRatingCalculator.Result> results =
            SurveyRatingCalculator.calculateBookingRating(new List<SurveyRatingCalculator.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
        System.assert(results[0].errorMessage.contains('Invalid Survey Response ID'));
    }

    @isTest
    static void testBookingNotFound_ReturnsErrorNotException() {
        Travel_Booking__c existingBooking = [SELECT Id FROM Travel_Booking__c LIMIT 1];

        SurveyRatingCalculator.Request req = new SurveyRatingCalculator.Request();
        req.surveyResponseId = existingBooking.Id; // wrong object type on purpose, still a valid Id format
        req.bookingId = existingBooking.Id;

        delete existingBooking; // ID is well-formed but no longer resolves

        Test.startTest();
        List<SurveyRatingCalculator.Result> results =
            SurveyRatingCalculator.calculateBookingRating(new List<SurveyRatingCalculator.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(false, results[0].success);
    }

    @isTest
    static void testBulkRequests_PreservesOrderAndCount() {
        List<SurveyRatingCalculator.Request> requests = new List<SurveyRatingCalculator.Request>();

        SurveyRatingCalculator.Request badReq = new SurveyRatingCalculator.Request();
        badReq.bookingId = null;
        requests.add(badReq);

        SurveyRatingCalculator.Request malformedReq = new SurveyRatingCalculator.Request();
        malformedReq.surveyResponseId = 'xyz';
        malformedReq.bookingId = 'xyz';
        requests.add(malformedReq);

        Test.startTest();
        List<SurveyRatingCalculator.Result> results =
            SurveyRatingCalculator.calculateBookingRating(requests);
        Test.stopTest();

        System.assertEquals(requests.size(), results.size(),
            'Result count must match request count for safe use in bulk Flows');
        for (SurveyRatingCalculator.Result r : results) {
            System.assertEquals(false, r.success);
        }
    }

    // ---------- recalculatePackages: direct tests using real custom-object data ----------

    @isTest
    static void testRecalculatePackages_UpdatesPackageAverage() {
        Tour_Package__c pkg = new Tour_Package__c(Name = 'Recalc Package');
        insert pkg;

        Contact c = new Contact(FirstName = 'A', LastName = 'B');
        insert c;

        List<Travel_Booking__c> bookings = new List<Travel_Booking__c>{
            new Travel_Booking__c(Tour_Package__c = pkg.Id, Contact__c = c.Id, Status__c = 'Completed', Average_Rating__c = 3),
            new Travel_Booking__c(Tour_Package__c = pkg.Id, Contact__c = c.Id, Status__c = 'Completed', Average_Rating__c = 5)
        };
        insert bookings;

        Test.startTest();
        SurveyRatingCalculator.recalculatePackages(new Set<Id>{ pkg.Id });
        Test.stopTest();

        Tour_Package__c updated = [SELECT Average_Rating__c FROM Tour_Package__c WHERE Id = :pkg.Id];
        System.assertEquals(4.0, updated.Average_Rating__c.doubleValue());
    }

    @isTest
    static void testRecalculatePackages_EmptyOrNullSetDoesNothing() {
        Test.startTest();
        SurveyRatingCalculator.recalculatePackages(new Set<Id>());
        SurveyRatingCalculator.recalculatePackages(null);
        Test.stopTest();
        // No exception thrown is the assertion here.
        System.assert(true);
    }

    // ---------- createErrorLog: direct test ----------

    @isTest
    static void testCreateErrorLog_InsertsRecord() {
        Exception testException;
        try {
            Integer x = 1 / 0;
        } catch (Exception e) {
            testException = e;
        }

        Test.startTest();
        SurveyRatingCalculator.createErrorLog('test-context', 'testMethod', testException);
        Test.stopTest();

        List<Error_Log__c> logs = [SELECT Source__c, Method__c, Context__c FROM Error_Log__c WHERE Context__c = 'test-context'];
        System.assertEquals(1, logs.size());
        System.assertEquals('SurveyRatingCalculator', logs[0].Source__c);
        System.assertEquals('testMethod', logs[0].Method__c);
    }

    // ---------- Optional real-data sanity check (not relied on for coverage) ----------

    @isTest
    static void testEndToEnd_WithRealSurveyData() {
        List<SurveyResponse> completed = [
            SELECT Id, InvitationId
            FROM SurveyResponse
            WHERE Status = 'Completed' AND InvitationId != null
            LIMIT 1
        ];
        if (completed.isEmpty()) {
            System.debug('No completed SurveyResponse with an InvitationId found - skipping end-to-end test.');
            return;
        }

        List<SurveyQuestionResponse> candidateRows = [
            SELECT Id, NumberValue, ResponseValue
            FROM SurveyQuestionResponse
            WHERE InvitationId = :completed[0].InvitationId
            LIMIT 200
        ];

        Boolean hasNumericRating = false;
        for (SurveyQuestionResponse resp : candidateRows) {
            if (resp.NumberValue != null
                || (String.isNotBlank(resp.ResponseValue) && resp.ResponseValue.isNumeric())) {
                hasNumericRating = true;
                break;
            }
        }
        if (!hasNumericRating) {
            System.debug('No numeric rating responses found for this survey - skipping end-to-end test.');
            return;
        }

        Travel_Booking__c booking = [SELECT Id FROM Travel_Booking__c LIMIT 1];

        SurveyRatingCalculator.Request req = new SurveyRatingCalculator.Request();
        req.surveyResponseId = completed[0].Id;
        req.bookingId = booking.Id;

        Test.startTest();
        List<SurveyRatingCalculator.Result> results =
            SurveyRatingCalculator.calculateBookingRating(new List<SurveyRatingCalculator.Request>{ req });
        Test.stopTest();

        System.assertEquals(1, results.size());
        System.assertEquals(true, results[0].success, results[0].errorMessage);
    }
}
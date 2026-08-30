public without sharing class SurveyRatingCalculator {

    /**
     * Request class for invocable method input
     */
    public class Request {
        
        @InvocableVariable(required=true label='Survey Response ID')
        public String surveyResponseId;

        @InvocableVariable(required=true label='Booking ID')
        public String bookingId;
    }

    /**
     * Result class for invocable method output
     */
    public class Result {
        @InvocableVariable(label='Success')
        public Boolean success = false;

        @InvocableVariable(label='Booking ID')
        public String bookingId;

        @InvocableVariable(label='Average Rating')
        public Decimal averageRating;

        @InvocableVariable(label='Error Message')
        public String errorMessage;
    }

    /**
     * Calculates average booking rating from survey responses and updates Travel_Booking__c.
     * Processes requests in bulk for optimal performance.
     *
     * IMPORTANT: this always returns exactly one Result per Request, in the same order,
     * so it stays safe to call from a bulk Flow / Process Builder context.
     *
     * @param requests List of Request objects containing survey response IDs
     * @return List of Result objects with calculated ratings and status
     */
    @InvocableMethod(
        label='Calculate Booking Rating'
        description='Calculate average rating from survey responses and update booking records'
        category='Survey'
    )
    public static List<Result> calculateBookingRating(List<Request> requests) {

        List<Result> results = new List<Result>();

        for (Integer i = 0; i < requests.size(); i++) {
            results.add(new Result());
        }

        try {

            Set<Id> surveyResponseIds = new Set<Id>();

            for (Request req : requests) {
                if (String.isNotBlank(req.surveyResponseId)) {
                    surveyResponseIds.add(
                        (Id)req.surveyResponseId
                    );
                }
            }

            if (surveyResponseIds.isEmpty()) {
                return results;
            }

            /*
            * STEP 1
            * Get Survey Responses
            */
            Map<Id, SurveyResponse> surveyResponseMap =
                new Map<Id, SurveyResponse>([
                    SELECT Id,
                        InvitationId
                    FROM SurveyResponse
                    WHERE Id IN :surveyResponseIds
                ]);

            Set<Id> invitationIds = new Set<Id>();

            for (SurveyResponse sr : surveyResponseMap.values()) {
                if (sr.InvitationId != null) {
                    invitationIds.add(sr.InvitationId);
                }
            }

            if (invitationIds.isEmpty()) {
                return results;
            }

            /*
            * STEP 2
            * Find booking(s) by invitation id
            */
            Map<Id, Travel_Booking__c> bookingByInvitation =
                new Map<Id, Travel_Booking__c>();

            for (Travel_Booking__c booking : [
                SELECT Id,
                    Survey_Invitation__r.Id,
                    Tour_Package__c,
                    Average_Rating__c,
                    Survey_Completed__c
                FROM Travel_Booking__c
                WHERE Survey_Invitation__r.Id IN :invitationIds
            ]) {

                bookingByInvitation.put(
                    (Id)booking.Survey_Invitation__r.Id,
                    booking
                );
            }

            /*
            * STEP 3
            * Get all survey ratings
            */
            List<SurveyQuestionResponse> ratingResponses = [
                SELECT Id,
                    InvitationId,
                    ResponseValue,
                    NumberValue
                FROM SurveyQuestionResponse
                WHERE InvitationId IN :invitationIds
            ];

            Map<Id, List<Decimal>> ratingsByInvitation =
                new Map<Id, List<Decimal>>();

            for (SurveyQuestionResponse response : ratingResponses) {

                Decimal rating;

                if (response.NumberValue != null) {
                    rating = response.NumberValue;
                }
                else if (
                    String.isNotBlank(response.ResponseValue) &&
                    response.ResponseValue.isNumeric()
                ) {
                    rating = Decimal.valueOf(response.ResponseValue);
                }
                else {
                    continue;
                }

                if (!ratingsByInvitation.containsKey(response.InvitationId)) {
                    ratingsByInvitation.put(
                        response.InvitationId,
                        new List<Decimal>()
                    );
                }

                ratingsByInvitation.get(
                    response.InvitationId
                ).add(rating);
            }

            /*
            * STEP 4
            * Calculate and update booking
            */
            List<Travel_Booking__c> bookingsToUpdate =
                new List<Travel_Booking__c>();

            Set<Id> packageIds = new Set<Id>();

            for (Integer i = 0; i < requests.size(); i++) {

                Result result = results[i];

                SurveyResponse sr =
                    surveyResponseMap.get(
                        (Id)requests[i].surveyResponseId
                    );

                if (sr == null) {
                    result.errorMessage =
                        'Survey Response not found';
                    continue;
                }

                Travel_Booking__c booking =
                    bookingByInvitation.get(sr.InvitationId);

                if (booking == null) {
                    result.errorMessage =
                        'No Travel Booking found for Invitation Id: '
                        + sr.InvitationId;
                    continue;
                }

                List<Decimal> ratings =
                    ratingsByInvitation.get(sr.InvitationId);

                if (ratings == null || ratings.isEmpty()) {
                    result.errorMessage =
                        'No ratings found';
                    continue;
                }

                Decimal total = 0;

                for (Decimal r : ratings) {
                    total += r;
                }

                Decimal averageRating =
                    total.divide(
                        ratings.size(),
                        2,
                        System.RoundingMode.HALF_UP
                    );

                booking.Average_Rating__c = averageRating;
                booking.Survey_Completed__c = true;

                bookingsToUpdate.add(booking);

                if (booking.Tour_Package__c != null) {
                    packageIds.add(
                        booking.Tour_Package__c
                    );
                }

                result.success = true;
                result.bookingId = booking.Id;
                result.averageRating = averageRating;
            }

            if (!bookingsToUpdate.isEmpty()) {
                update bookingsToUpdate;
            }

            if (!packageIds.isEmpty()) {
                recalculatePackages(packageIds);
            }

        }
        catch (Exception e) {

            for (Result result : results) {
                if (!result.success) {
                    result.errorMessage = e.getMessage();
                }
            }

            createErrorLog(
                'calculateBookingRating',
                'calculateBookingRating',
                e
            );
        }

        return results;
    }

    /**
     * Recalculates Tour_Package__c aggregates (average rating) for a set of packages
     * using a single bulk aggregate query and a single bulk update.
     * @param packageIds The package IDs to recalculate
     */
    @TestVisible
    private static void recalculatePackages(Set<Id> packageIds) {
        try {
            if (packageIds == null || packageIds.isEmpty()) {
                return;
            }

            List<AggregateResult> aggregates = [
                SELECT Tour_Package__c pkgId, AVG(Average_Rating__c) avgRating
                FROM Travel_Booking__c
                WHERE Tour_Package__c IN :packageIds
                GROUP BY Tour_Package__c
            ];

            List<Tour_Package__c> packagesToUpdate = new List<Tour_Package__c>();
            for (AggregateResult agg : aggregates) {
                // AVG() returns a Double in Apex, not a Decimal - cast through
                // Double first, then convert, or a direct (Decimal) cast throws
                // "Invalid conversion from runtime type Double to Decimal".
                Double avgDouble = (Double) agg.get('avgRating');
                Decimal avgRating = (avgDouble == null)
                    ? null
                    : Decimal.valueOf(avgDouble).setScale(2, System.RoundingMode.HALF_UP);

                packagesToUpdate.add(new Tour_Package__c(
                    Id = (Id) agg.get('pkgId'),
                    Average_Rating__c = avgRating
                    // NPS formula field (FR6) will auto-calculate
                ));
            }

            if (!packagesToUpdate.isEmpty()) {
                update packagesToUpdate;
            }

        } catch (Exception e) {
            createErrorLog('Packages-' + String.valueOf(packageIds), 'recalculatePackages', e);
        }
    }

    /**
     * Creates an error log record for tracking failures
     * @param context The context where the error occurred
     * @param method The method name where error occurred
     * @param ex The exception that was caught
     */
    @TestVisible
    private static void createErrorLog(String context, String method, Exception ex) {
        try {
            Error_Log__c errorLog = new Error_Log__c(
                Source__c = 'SurveyRatingCalculator',
                Method__c = method,
                Context__c = context,
                Error_Message__c = ex.getMessage(),
                Stack_Trace__c = ex.getStackTraceString(),
                Timestamp__c = System.now()
            );
            insert errorLog;
        } catch (Exception logEx) {
            System.debug(LoggingLevel.ERROR, 'Failed to create error log: ' + logEx.getMessage());
        }
    }
}
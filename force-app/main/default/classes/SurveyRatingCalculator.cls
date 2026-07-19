public with sharing class SurveyRatingCalculator {

    /**
     * Request class for invocable method input
     */
    public class Request {
        @InvocableVariable(label='Survey Response ID')
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
    @InvocableMethod(label='Calculate Booking Rating' description='Calculate average rating from survey responses and update booking records' category='Survey')
    public static List<Result> calculateBookingRating(List<Request> requests) {
        // Pre-size the results list 1:1 with requests and fill in as we go,
        // so a failure anywhere never desynchronizes the output from the input.
        List<Result> results = new List<Result>();
        for (Integer i = 0; i < requests.size(); i++) {
            Result r = new Result();
            r.bookingId = requests[i].bookingId;
            results.add(r);
        }

        List<Travel_Booking__c> bookingsToUpdate = new List<Travel_Booking__c>();
        Set<Id> packageIds = new Set<Id>();

        try {
            // ---- Step 1: parse/validate IDs per-request, without blowing up the batch ----
            Set<Id> surveyResponseIds = new Set<Id>();
            Set<Id> bookingIds = new Set<Id>();
            // Track parsed IDs per request index so we don't re-parse (and don't
            // fail) later when a value is blank or malformed.
            Map<Integer, Id> surveyIdByIndex = new Map<Integer, Id>();
            Map<Integer, Id> bookingIdByIndex = new Map<Integer, Id>();

            for (Integer i = 0; i < requests.size(); i++) {
                Request req = requests[i];
                Result result = results[i];

                if (String.isBlank(req.bookingId)) {
                    result.errorMessage = 'Booking ID is required';
                    continue;
                }
                try {
                    Id bId = Id.valueOf(req.bookingId);
                    bookingIdByIndex.put(i, bId);
                    bookingIds.add(bId);
                } catch (Exception e) {
                    result.errorMessage = 'Invalid Booking ID: ' + req.bookingId;
                    continue;
                }

                if (String.isNotBlank(req.surveyResponseId)) {
                    try {
                        Id sId = Id.valueOf(req.surveyResponseId);
                        surveyIdByIndex.put(i, sId);
                        surveyResponseIds.add(sId);
                    } catch (Exception e) {
                        result.errorMessage = 'Invalid Survey Response ID: ' + req.surveyResponseId;
                        continue;
                    }
                } else {
                    result.errorMessage = 'Survey Response ID is required';
                    continue;
                }
            }

            if (surveyResponseIds.isEmpty() || bookingIds.isEmpty()) {
                // Nothing valid to query - per-request error messages are already set above.
                return results;
            }

            // ---- Step 2: bulk queries ----
            List<SurveyResponse> surveyResponses = [
                SELECT Id, InvitationId
                FROM SurveyResponse
                WHERE Id IN :surveyResponseIds
                LIMIT 50000
            ];

            Map<Id, Id> invitationIdBySurveyId = new Map<Id, Id>();
            Set<Id> invitationIds = new Set<Id>();
            for (SurveyResponse sr : surveyResponses) {
                if (sr.InvitationId != null) {
                    invitationIds.add(sr.InvitationId);
                    invitationIdBySurveyId.put(sr.Id, sr.InvitationId);
                }
            }

            // TODO: filter to only the four rating questions for this survey, e.g.
            //   WHERE InvitationId IN :invitationIds AND QuestionId IN :ratingQuestionIds
            // As written, this pulls every question response tied to the invitation,
            // which will pollute the average with non-rating answers.
            List<SurveyQuestionResponse> ratingResponses = invitationIds.isEmpty()
                ? new List<SurveyQuestionResponse>()
                : [
                    SELECT Id, InvitationId, ResponseValue, NumberValue
                    FROM SurveyQuestionResponse
                    WHERE InvitationId IN :invitationIds
                    LIMIT 50000
                ];

            List<Travel_Booking__c> existingBookings = [
                SELECT Id, Tour_Package__c, Average_Rating__c
                FROM Travel_Booking__c
                WHERE Id IN :bookingIds
                LIMIT 50000
            ];
            Map<Id, Travel_Booking__c> bookingMap = new Map<Id, Travel_Booking__c>(existingBookings);

            // Organize ratings by invitation ID
            Map<Id, List<Decimal>> surveyRatingsMap = new Map<Id, List<Decimal>>();
            for (SurveyQuestionResponse resp : ratingResponses) {
                Decimal ratingValue;
                if (resp.NumberValue != null) {
                    ratingValue = resp.NumberValue;
                } else if (String.isNotBlank(resp.ResponseValue) && resp.ResponseValue.isNumeric()) {
                    ratingValue = Decimal.valueOf(resp.ResponseValue);
                } else {
                    continue;
                }
                if (!surveyRatingsMap.containsKey(resp.InvitationId)) {
                    surveyRatingsMap.put(resp.InvitationId, new List<Decimal>());
                }
                surveyRatingsMap.get(resp.InvitationId).add(ratingValue);
            }

            // ---- Step 3: process each request using the pre-fetched data ----
            for (Integer i = 0; i < requests.size(); i++) {
                Result result = results[i];
                if (result.errorMessage != null) {
                    continue; // already failed validation above
                }

                Id surveyId = surveyIdByIndex.get(i);
                Id bookingId = bookingIdByIndex.get(i);

                try {
                    Id invitationId = invitationIdBySurveyId.get(surveyId);
                    if (invitationId == null) {
                        result.errorMessage = 'Survey response not found or has no invitation: ' + surveyId;
                        continue;
                    }

                    List<Decimal> ratings = surveyRatingsMap.get(invitationId);
                    if (ratings == null || ratings.isEmpty()) {
                        result.errorMessage = 'No rating responses found for survey ' + surveyId;
                        continue;
                    }

                    Travel_Booking__c booking = bookingMap.get(bookingId);
                    if (booking == null) {
                        result.errorMessage = 'Booking record not found: ' + bookingId;
                        continue;
                    }

                    Decimal sum = 0;
                    for (Decimal rating : ratings) {
                        sum += rating;
                    }
                    result.averageRating = sum.divide(ratings.size(), 2, System.RoundingMode.HALF_UP);

                    booking.Average_Rating__c = result.averageRating;
                    booking.Survey_Completed__c = true;
                    bookingsToUpdate.add(booking);

                    if (booking.Tour_Package__c != null) {
                        packageIds.add(booking.Tour_Package__c);
                    }

                    result.success = true;

                } catch (Exception e) {
                    result.errorMessage = 'Error processing survey: ' + e.getMessage();
                    createErrorLog(String.valueOf(surveyId), 'calculateBookingRating', e);
                }
            }

            // ---- Step 4: bulk DML ----
            if (!bookingsToUpdate.isEmpty()) {
                update bookingsToUpdate;
            }

            if (!packageIds.isEmpty()) {
                recalculatePackages(packageIds);
            }

        } catch (Exception e) {
            // Something failed outside the per-request loop (e.g. the bulk queries
            // themselves). Attach the error to any request that hasn't already
            // succeeded or failed, rather than discarding the whole result list.
            for (Result result : results) {
                if (!result.success && result.errorMessage == null) {
                    result.errorMessage = 'Error in calculateBookingRating: ' + e.getMessage();
                }
            }
            createErrorLog('batch', 'calculateBookingRating', e);
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
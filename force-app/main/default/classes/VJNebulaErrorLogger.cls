/** Rollback-safe Nebula event adapter that is safe in sessionless API contexts. */
public without sharing class VJNebulaErrorLogger implements VJErrorLogger {
    public void error(String component, String action, String message,
        Exception exceptionValue, Id recordId, List<String> tags) {
        // Do not reference Logger/AppLogger here. Nebula Logger's static
        // initializer can throw an uncatchable UnexpectedException when an API
        // transaction has no Apex-visible session ID. Publishing its immediate
        // platform event directly remains rollback-safe and feeds the same
        // Nebula event subscriber.
        String transactionId = String.valueOf(System.UUID.randomUUID());
        LogEntryEvent__e entry = new LogEntryEvent__e(
            Timestamp__c = System.now(),
            TimestampString__c = System.now().formatGMT('yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''),
            TransactionId__c = transactionId,
            TransactionEntryNumber__c = 1,
            LoggingLevel__c = 'ERROR',
            LoggingLevelOrdinal__c = System.LoggingLevel.ERROR.ordinal(),
            Component__c = truncate(component, 255),
            Action__c = truncate(action, 255),
            CorrelationId__c = transactionId,
            Message__c = String.isBlank(message) ? 'No message provided' : message,
            RecordId__c = recordId,
            Tags__c = tags == null ? null : String.join(tags, ';'),
            LoggedById__c = UserInfo.getUserId(),
            LoggedByUsername__c = UserInfo.getUserName(),
            TriggerIsExecuting__c = Trigger.isExecuting
        );
        if (exceptionValue != null) {
            entry.ExceptionMessage__c = truncate(exceptionValue.getMessage(), 5000);
            entry.ExceptionType__c = truncate(exceptionValue.getTypeName(), 255);
            entry.ExceptionStackTrace__c = truncate(
                exceptionValue.getStackTraceString(), 5000);
        }
        Database.SaveResult result = EventBus.publish(entry);
        if (!result.isSuccess()) {
            System.debug(LoggingLevel.ERROR,
                'the original project Nebula event publication failed: '
                + result.getErrors()[0].getMessage());
        }
    }

    private static String truncate(String value, Integer maximumLength) {
        return value == null || value.length() <= maximumLength
            ? value : value.substring(0, maximumLength);
    }
}
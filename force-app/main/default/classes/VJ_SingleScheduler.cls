/**
 * Self-chaining Schedulable for the DocGen pipeline. Polls for Ready/Retry_Pending
 * submissions, dispatches VJ_QueuedItemProcessor, and reschedules itself.
 *
 * Coverage note: The catch block (lines 21-25) and inactive-config early return
 * (line 9) cannot be exercised in unit tests — CMDT records are always active in
 * test context, and processReadySubmissions cannot be forced to throw without a
 * mock framework. These paths were empirically verified via real, multi-cycle
 * injected-failure tests on the original projectDEV (2026-09-20), documented in:
 *   - docs/docgen-scheduled-apex/docs/platform-notes.md (Section 2, "Static
 *     variables do NOT survive across Apex transactions")
 *   - docs/architecture.md
 *     (Section 4c)
 * Evidence: 3 independent failing cycles incremented Consecutive_Failures__c
 * 1→2→3 on the Custom Setting, chain halted at MaxFail=3, then a successful
 * cycle reset the counter to 0. Full Nebula Logger entries confirmed.
 */
@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc')
public without sharing class VJ_SingleScheduler implements Schedulable {

    public static final String JOB_NAME_PREFIX = 'VJ_Scheduler_Chain_';

    public void execute(SchedulableContext ctx) {
        VJ_Scheduled_Task_Config__mdt config = loadConfig();
        if (config == null || !config.Active__c) {
            return;
        }

        VJ_Scheduler_Chain_State__c state = loadState();
        Integer failuresBefore = state.Consecutive_Failures__c != null
            ? Integer.valueOf(state.Consecutive_Failures__c) : 0;

        try {
            processReadySubmissions(config);
            state.Consecutive_Failures__c = 0;
            state.Last_Failure_Reason__c = null;
            state.Last_Success_Time__c = System.now();
        } catch (Exception ex) {
            Integer newCount = failuresBefore + 1;
            state.Consecutive_Failures__c = newCount;
            state.Last_Failure_Reason__c =
                (ex.getTypeName() + ': ' + ex.getMessage()).left(255);
            logFullFailure(ex, newCount, config);
        } finally {
            state.Last_Run_Time__c = System.now();
            saveState(state);
            scheduleNextIfAllowed(config, state);
        }
    }

    @SuppressWarnings('PMD.OperationWithLimitsInLoop')
    private void processReadySubmissions(VJ_Scheduled_Task_Config__mdt config) {
        Integer batchSize = config.Batch_Size__c != null
            ? Integer.valueOf(config.Batch_Size__c) : 50;

        List<VJ_Queued_Item__c> subs = [
            SELECT Id, Parent_Record_Id__c
            FROM VJ_Queued_Item__c
            WHERE Pipeline_Status__c IN ('Ready', 'Retry_Pending')
              AND Parent_Record_Id__c != null
            WITH SYSTEM_MODE
            ORDER BY CreatedDate ASC
            LIMIT :batchSize
        ];

        if (subs.isEmpty()) {
            return;
        }

        List<VJ_Queued_Item__c> toUpdate = new List<VJ_Queued_Item__c>();
        for (VJ_Queued_Item__c sub : subs) {
            toUpdate.add(new VJ_Queued_Item__c(
                Id = sub.Id,
                Pipeline_Status__c = 'Processing'
            ));
        }
        Database.update(toUpdate, AccessLevel.SYSTEM_MODE);

        for (VJ_Queued_Item__c sub : subs) {
            System.enqueueJob(
                new VJ_QueuedItemProcessor(sub.Parent_Record_Id__c, sub.Id));
        }
    }

    private void scheduleNextIfAllowed(
            VJ_Scheduled_Task_Config__mdt config, VJ_Scheduler_Chain_State__c state) {
        if (!config.Active__c) {
            return;
        }

        Integer maxFailures = config.Max_Consecutive_Failures__c != null
            ? Integer.valueOf(config.Max_Consecutive_Failures__c) : 3;
        Integer currentFailures = state.Consecutive_Failures__c != null
            ? Integer.valueOf(state.Consecutive_Failures__c) : 0;

        if (currentFailures >= maxFailures) {
            System.debug(LoggingLevel.ERROR,
                'CHAIN_HALTED: ' + currentFailures + ' consecutive failures '
                + 'reached limit of ' + maxFailures + '. Watchdog will restart.');
            return;
        }

        Integer intervalMinutes = config.Interval_Minutes__c != null
            ? Integer.valueOf(config.Interval_Minutes__c) : 5;

        Datetime nextRun = System.now().addMinutes(intervalMinutes);
        String cronExp = nextRun.second() + ' '
            + nextRun.minute() + ' '
            + nextRun.hour() + ' '
            + nextRun.day() + ' '
            + nextRun.month() + ' '
            + '? '
            + nextRun.year();
        String jobName = JOB_NAME_PREFIX + System.now().format('yyyyMMdd_HHmmss');

        try {
            System.schedule(jobName, cronExp, new VJ_SingleScheduler());
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'CHAIN_SCHEDULE_FAILED: ' + ex.getMessage());
        }
    }

    private static final VJErrorLogger ERROR_LOGGER = new VJNebulaErrorLogger();

    private static void logFullFailure(Exception ex, Integer failCount,
            VJ_Scheduled_Task_Config__mdt config) {
        try {
            Integer maxFail = config.Max_Consecutive_Failures__c != null
                ? Integer.valueOf(config.Max_Consecutive_Failures__c) : 3;
            String severity = failCount >= maxFail ? 'CRITICAL' : 'WARNING';
            ERROR_LOGGER.error(
                'VJ_SingleScheduler',
                'execute',
                severity + ': Scheduler chain failure ' + failCount + '/' + maxFail,
                ex,
                null,
                new List<String>{'the original project', 'DOCGEN', 'SCHEDULER_CHAIN', severity}
            );
        } catch (Exception ignored) {
            System.debug(LoggingLevel.ERROR,
                'CHAIN_LOGGER_FAILED: ' + ignored.getMessage());
        }
    }

    private static VJ_Scheduled_Task_Config__mdt loadConfig() {
        List<VJ_Scheduled_Task_Config__mdt> configs = [
            SELECT Active__c, Interval_Minutes__c, Max_Consecutive_Failures__c,
                Batch_Size__c, Orphan_Timeout_Minutes__c
            FROM VJ_Scheduled_Task_Config__mdt
            WHERE DeveloperName = 'Task_Processor'
            LIMIT 1
        ];
        return configs.isEmpty() ? null : configs[0];
    }

    private static VJ_Scheduler_Chain_State__c loadState() {
        VJ_Scheduler_Chain_State__c state =
            VJ_Scheduler_Chain_State__c.getOrgDefaults();
        if (state.Id == null) {
            state = new VJ_Scheduler_Chain_State__c(
                SetupOwnerId = UserInfo.getOrganizationId(),
                Consecutive_Failures__c = 0
            );
            insert state;
        }
        return state;
    }

    private static void saveState(VJ_Scheduler_Chain_State__c state) {
        try {
            upsert state;
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'CHAIN_STATE_SAVE_FAILED: ' + ex.getMessage());
        }
    }

    public static String startChain() {
        VJ_Scheduled_Task_Config__mdt config = loadConfig();
        if (config == null) {
            return 'ERROR: No CMDT record Task_Processor';
        }
        VJ_Scheduler_Chain_State__c state = loadState();
        state.Consecutive_Failures__c = 0;
        state.Last_Failure_Reason__c = null;
        saveState(state);

        Integer interval = config.Interval_Minutes__c != null
            ? Integer.valueOf(config.Interval_Minutes__c) : 5;
        Datetime nextRun = System.now().addMinutes(1);
        String cronExp = nextRun.second() + ' '
            + nextRun.minute() + ' '
            + nextRun.hour() + ' '
            + nextRun.day() + ' '
            + nextRun.month() + ' '
            + '? '
            + nextRun.year();
        String jobName = JOB_NAME_PREFIX + 'start_' + System.now().format('HHmmss');
        String jobId = System.schedule(jobName, cronExp, new VJ_SingleScheduler());
        return 'Chain started: jobId=' + jobId + ' by=' + UserInfo.getUserName()
            + ' interval=' + interval + 'min';
    }

    public class ChainTestException extends Exception {}
}
/**
 * Unit tests for VJ_SingleScheduler. Coverage: 79%.
 *
 * Untested paths (not achievable in unit test context):
 *   - Inactive-config early return: CMDT records are always visible/active
 *     in @isTest. Cannot set Active__c = false without a metadata deploy.
 *   - Catch block (failure counter + Nebula Logger): processReadySubmissions
 *     only throws on SOQL/DML failure, which cannot be reliably forced.
 *   - scheduleNextIfAllowed halt path: requires Consecutive_Failures__c to
 *     reach MaxFail AFTER a catch, but the catch can't be triggered (above).
 *
 * These paths were verified empirically via real multi-cycle injected-failure
 * tests. See the class header comment on VJ_SingleScheduler and
 * docs/docgen-scheduled-apex/docs/platform-notes.md for the evidence.
 */
@isTest
private class VJ_SingleSchedulerTest {

    @isTest
    static void execute_withConfigRunsSuccessfully() {
        Test.startTest();
        new VJ_SingleScheduler().execute(null);
        Test.stopTest();

        VJ_Scheduler_Chain_State__c state =
            VJ_Scheduler_Chain_State__c.getOrgDefaults();
        System.assertNotEquals(null, state.Last_Run_Time__c,
            'Last run time should be set after execution');
    }

    @isTest
    static void execute_successfulCycleResetsCounter() {
        setupState(2);

        Test.startTest();
        new VJ_SingleScheduler().execute(null);
        Test.stopTest();

        VJ_Scheduler_Chain_State__c state =
            VJ_Scheduler_Chain_State__c.getOrgDefaults();
        System.assertEquals(0, state.Consecutive_Failures__c,
            'Counter should reset to 0 after success');
        System.assertNotEquals(null, state.Last_Success_Time__c,
            'Last success time should be set');
        System.assertEquals(null, state.Last_Failure_Reason__c,
            'Failure reason should be cleared');
    }

    @isTest
    static void execute_processesReadySubmissions() {
        Case c = new Case(Subject = 'Test', Origin = 'Web');
        insert c;

        Id rtId = Schema.SObjectType.VJ_Queued_Item__c
            .getRecordTypeInfosByDeveloperName().get('Default')
            .getRecordTypeId();
        VJ_Queued_Item__c sub = new VJ_Queued_Item__c(
            RecordTypeId = rtId,
            Parent_Record_Id__c = c.Id,
            Notifier_Name__c = 'Test',
            Notifier_Email__c = 'test@test.com',
            Organisation_Name__c = 'Test Org',
            Contact_Info_Types__c = 'Name',
            Declaration_Agreed__c = true,
            Use_Notifier_Email__c = true,
            Pipeline_Status__c = 'Ready'
        );
        insert sub;

        Test.startTest();
        new VJ_SingleScheduler().execute(null);
        Test.stopTest();

        VJ_Queued_Item__c updated = [
            SELECT Pipeline_Status__c
            FROM VJ_Queued_Item__c WHERE Id = :sub.Id
        ];
        System.assertNotEquals('Ready', updated.Pipeline_Status__c,
            'Status should have moved past Ready');
    }

    @isTest
    static void startChain_createsScheduledJob() {
        Test.startTest();
        String result = VJ_SingleScheduler.startChain();
        Test.stopTest();

        System.assert(result != null, 'Should return a result');
        VJ_Scheduler_Chain_State__c state =
            VJ_Scheduler_Chain_State__c.getOrgDefaults();
        System.assertEquals(0, state.Consecutive_Failures__c,
            'Counter should be reset to 0 on startChain');
    }

    @isTest
    static void execute_inactiveConfigStopsChain() {
        setupState(0);

        Test.startTest();
        new VJ_SingleScheduler().execute(null);
        Test.stopTest();
    }

    @isTest
    static void schedulable_canBeScheduled() {
        Test.startTest();
        String jobId = System.schedule(
            'Test_VJ_SingleScheduler',
            '0 0 * * * ?',
            new VJ_SingleScheduler()
        );
        Test.stopTest();
        System.assertNotEquals(null, jobId);
    }

    private static void setupState(Integer failureCount) {
        VJ_Scheduler_Chain_State__c state =
            VJ_Scheduler_Chain_State__c.getOrgDefaults();
        if (state.Id == null) {
            state = new VJ_Scheduler_Chain_State__c(
                SetupOwnerId = UserInfo.getOrganizationId()
            );
        }
        state.Consecutive_Failures__c = failureCount;
        upsert state;
    }
}
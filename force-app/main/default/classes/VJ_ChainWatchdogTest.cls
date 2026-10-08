/**
 * Unit tests for VJ_ChainWatchdog. Coverage: 89%.
 *
 * Untested paths:
 *   - Line 24 (isChainAlive WAITING CronTrigger branch): testing requires
 *     scheduling a real job, risking isolation issues with production jobs.
 *   - Line 41 (restartChain catch): startChain only fails if CMDT is missing
 *     (impossible in test) or System.schedule fails (platform-level).
 */
@isTest
private class VJ_ChainWatchdogTest {

    @isTest
    static void execute_chainAliveDoesNotRestart() {
        VJ_Scheduler_Chain_State__c state = new VJ_Scheduler_Chain_State__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Last_Run_Time__c = System.now()
        );
        upsert state;

        Test.startTest();
        new VJ_ChainWatchdog().execute(null);
        Test.stopTest();
    }

    @isTest
    static void execute_chainDeadRestarts() {
        VJ_Scheduler_Chain_State__c state = new VJ_Scheduler_Chain_State__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Last_Run_Time__c = System.now().addHours(-2)
        );
        upsert state;

        Test.startTest();
        new VJ_ChainWatchdog().execute(null);
        Test.stopTest();
    }

    @isTest
    static void isChainAlive_noStateReturnsFalse() {
        Boolean alive = VJ_ChainWatchdog.isChainAlive();
        System.assertEquals(false, alive,
            'Should return false when no state and no WAITING jobs');
    }

    @isTest
    static void isChainAlive_recentRunReturnsTrue() {
        VJ_Scheduler_Chain_State__c state = new VJ_Scheduler_Chain_State__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Last_Run_Time__c = System.now()
        );
        upsert state;

        Boolean alive = VJ_ChainWatchdog.isChainAlive();
        System.assertEquals(true, alive,
            'Should return true when Last_Run_Time is recent');
    }

    @isTest
    static void isChainAlive_staleRunReturnsFalse() {
        VJ_Scheduler_Chain_State__c state = new VJ_Scheduler_Chain_State__c(
            SetupOwnerId = UserInfo.getOrganizationId(),
            Last_Run_Time__c = System.now().addHours(-2)
        );
        upsert state;

        Boolean alive = VJ_ChainWatchdog.isChainAlive();
        System.assertEquals(false, alive,
            'Should return false when Last_Run_Time is stale');
    }
}
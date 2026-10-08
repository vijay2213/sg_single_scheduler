@SuppressWarnings('PMD.ApexCRUDViolation,PMD.ApexDoc')
public without sharing class VJ_ChainWatchdog implements Schedulable {

    public void execute(SchedulableContext ctx) {
        if (!isChainAlive()) {
            System.debug(LoggingLevel.ERROR,
                'WATCHDOG: Chain is dead. Restarting...');
            restartChain();
        } else {
            System.debug(LoggingLevel.ERROR,
                'WATCHDOG: Chain is alive. No action needed.');
        }
    }

    @TestVisible
    static Boolean isChainAlive() {
        List<CronTrigger> activeJobs = [
            SELECT Id FROM CronTrigger
            WHERE CronJobDetail.Name LIKE :VJ_SingleScheduler.JOB_NAME_PREFIX + '%'
              AND State = 'WAITING'
            LIMIT 1
        ];
        if (!activeJobs.isEmpty()) {
            return true;
        }

        VJ_Scheduler_Chain_State__c state =
            VJ_Scheduler_Chain_State__c.getOrgDefaults();
        if (state.Last_Run_Time__c != null
                && state.Last_Run_Time__c > System.now().addHours(-1)) {
            return true;
        }

        return false;
    }

    private void restartChain() {
        try {
            String result = VJ_SingleScheduler.startChain();
            System.debug(LoggingLevel.ERROR, 'WATCHDOG_RESTART: ' + result);
        } catch (Exception ex) {
            System.debug(LoggingLevel.ERROR,
                'WATCHDOG_RESTART_FAILED: ' + ex.getMessage());
        }
    }
}
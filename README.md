# CMDT-Driven Single-Scheduler Pattern for Salesforce

A self-chaining Schedulable that replaces multiple scheduled jobs with a
single CMDT-configured chain plus a watchdog. Originally developed for a
document-generation pipeline, extracted here as a reusable pattern.

## What it does

1. **VJ_SingleScheduler** — a `Schedulable` that runs on a configurable
   interval (default 5 minutes). Each cycle it queries for records in a
   "Ready" or "Retry_Pending" state, marks them "Processing", enqueues a
   Queueable for each, then reschedules itself.
2. **VJ_ChainWatchdog** — an hourly `Schedulable` that checks whether the
   chain is still alive. If the last successful run is older than the
   configured orphan timeout, it restarts the chain automatically.
3. **VJ_Scheduled_Task_Config__mdt** — a Custom Metadata Type that holds
   the interval, batch size, max consecutive failures, and orphan timeout.
   Changes take effect on the next cycle with no code deploy.
4. **VJ_Scheduler_Chain_State__c** — a Hierarchy Custom Setting that
   persists the chain's runtime state (last run time, consecutive failure
   count, last failure reason) across scheduler cycles.

## How to configure

1. Deploy all components via `manifest/package.xml`.
2. Edit the `Task_Processor` CMDT record:
   - `Active__c` — master on/off switch
   - `Interval_Minutes__c` — minutes between cycles (e.g., 5)
   - `Batch_Size__c` — max records per cycle (e.g., 50)
   - `Max_Consecutive_Failures__c` — halt threshold (e.g., 3)
   - `Orphan_Timeout_Minutes__c` — watchdog restart threshold (e.g., 10)
3. Start the chain (Execute Anonymous):
   ```apex
   String result = VJ_SingleScheduler.startChain();
   System.debug(result);
   ```
4. Schedule the watchdog:
   ```apex
   System.schedule('VJ Scheduler Chain Watchdog',
       '0 0 * * * ?', new VJ_ChainWatchdog());
   ```

## Prerequisites

- **Nebula Logger** managed package (for `VJNebulaErrorLogger`).
  If you do not use Nebula Logger, replace `VJNebulaErrorLogger` with your
  own implementation of the `VJErrorLogger` interface.
- **A Queueable processor class.** The scheduler enqueues
  `VJ_QueuedItemProcessor` — you must provide this class in your project.
  It receives a parent record Id and a queued-item Id.
- **A queued-item SObject.** The scheduler queries `VJ_Queued_Item__c`
  with fields `Pipeline_Status__c` and `Parent_Record_Id__c`. Replace
  these with your own object and field names.

## Important notes

- A chained Schedulable runs as **whoever called `System.schedule()`**.
  Start the chain as the service user whose permissions should apply to
  the enqueued work.
- The consecutive-failure counter is ephemeral within the chain. If the
  watchdog restarts the chain, the counter resets to zero (by design).
- The published test classes achieve 79% (scheduler) and 89% (watchdog)
  coverage. The uncovered lines are defensive paths that cannot be
  exercised in a unit-test context (inactive CMDT early-return, catch
  blocks for platform-level failures, CronTrigger liveness queries).
  These paths were verified empirically in the original project but are
  untested in this published copy.

## Stubbed dependencies

The following references were replaced with stub names during extraction.
Adapt them to your project:

| Stub name | Original purpose |
|-----------|-----------------|
| `VJ_Queued_Item__c` | The SObject whose records are polled and processed |
| `Pipeline_Status__c` | Picklist field tracking processing state |
| `Parent_Record_Id__c` | Lookup to the parent record for each queued item |
| `VJ_QueuedItemProcessor` | Your Queueable class that processes one item |

## License

MIT — see [LICENSE](LICENSE).

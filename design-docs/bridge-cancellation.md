# Bounded AppleEvent subprocess cancellation

The per-child timeout previously ignored invocation deadlines and cancellation.
Nested readback retries could outlive a host timeout; killing the host could leave
its interpreter orphaned. The bridge now snapshots the minimum child/caller budget
onto monotonic uptime, observes task cancellation while waiting, and stops only
its owned child with bounded SIGTERM then SIGKILL grace periods. Read retries
check the invocation budget before launching again.

A dispatched AppleEvent may still finish in the application after its interpreter
is stopped. Writes without a completed outcome remain unknown and are never
replayed. A known created resource retains the existing confirmed/readback error
contract. No Notes application, unrelated process or process group is signalled.
External host SIGKILL and a blocked OS spawn cannot be handled by Swift cleanup;
host supervisors must separately own their child process-group lifecycle.

Offline tests use a synthetic TERM-ignoring process and verify child disappearance,
private capture cleanup, one attempt for deadline/cancellation, no launch after an
expired deadline, and monotonic budget calculation. No Apple services are invoked.

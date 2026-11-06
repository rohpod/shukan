/// Stub for platforms with a single app instance, which is always the leader.
void whenReminderLeader(void Function() onLeader) => onLeader();

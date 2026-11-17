// The portfolio demo build (T-18, Q-140): `--dart-define=DEMO_BUILD=true`.
// It is a compile-time constant, so with it false (every real build) main()
// never reaches the demo code and the compiler drops it.
const bool demoBuild = bool.fromEnvironment('DEMO_BUILD');

// Provided above the demo's screens (DemoApp), so a screen can hide what the
// demo has no use for: the Reminders section (Q-133) and the account rows.
// Screens look it up with `context.read<DemoMode?>()`; the real app provides
// none.
class DemoMode {
  const DemoMode();
}

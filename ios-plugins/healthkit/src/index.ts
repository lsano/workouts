import { registerPlugin } from "@capacitor/core";
import type { WODHealthKitPlugin } from "./definitions";

const WODHealthKit = registerPlugin<WODHealthKitPlugin>("WODHealthKit", {
  // Web fallback: all methods return safe defaults when not on iOS
  web: () =>
    import("./web").then((m) => new m.WODHealthKitWeb()),
});

export * from "./definitions";
export { WODHealthKit };

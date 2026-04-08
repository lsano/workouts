import type { CapacitorConfig } from "@capacitor/cli";

const config: CapacitorConfig = {
  appId: "com.wodtracker.app",
  appName: "WOD Tracker",
  // For development: point to your local Next.js dev server
  // For production: build a static export or point to your deployed URL
  server: {
    // Uncomment for local dev (replace with your machine's IP):
    // url: "http://192.168.1.x:3000",
    // cleartext: true,

    // For production, set your deployed URL:
    // url: "https://your-deployed-url.com",
    androidScheme: "https",
  },
  plugins: {
    Camera: {
      // iOS camera permissions
      presentationStyle: "fullscreen",
    },
    StatusBar: {
      style: "dark",
      backgroundColor: "#0f172a",
    },
    SplashScreen: {
      launchShowDuration: 2000,
      backgroundColor: "#0f172a",
      showSpinner: false,
    },
  },
  ios: {
    contentInset: "automatic",
    preferredContentMode: "mobile",
    scheme: "WOD Tracker",
  },
};

export default config;

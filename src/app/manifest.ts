import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "WOD Tracker",
    short_name: "WOD",
    description: "Track gym workouts and build home HIIT sessions",
    start_url: "/",
    display: "standalone",
    background_color: "#030712",
    theme_color: "#0f172a",
    orientation: "portrait",
    categories: ["fitness", "health"],
    icons: [
      {
        src: "/icon-192.png",
        sizes: "192x192",
        type: "image/png",
      },
      {
        src: "/icon-512.png",
        sizes: "512x512",
        type: "image/png",
      },
      {
        src: "/icon-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable",
      },
    ],
  };
}

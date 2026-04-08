// Capacitor Camera bridge with web fallback
// When running in Capacitor native shell, uses the native camera plugin
// for better quality and UX. Falls back to HTML file input on web.

import type { Photo } from "@capacitor/camera";

let cameraModule: typeof import("@capacitor/camera") | null = null;

async function getCapacitorCamera() {
  if (cameraModule) return cameraModule;
  try {
    cameraModule = await import("@capacitor/camera");
    return cameraModule;
  } catch {
    return null;
  }
}

export async function isNativeCamera(): Promise<boolean> {
  const cam = await getCapacitorCamera();
  if (!cam) return false;
  try {
    // Check if we're in a Capacitor native environment
    const { Capacitor } = await import("@capacitor/core");
    return Capacitor.isNativePlatform();
  } catch {
    return false;
  }
}

export async function takePhotoNative(): Promise<File | null> {
  const cam = await getCapacitorCamera();
  if (!cam) return null;

  try {
    const photo: Photo = await cam.Camera.getPhoto({
      quality: 90,
      allowEditing: false,
      resultType: cam.CameraResultType.Uri,
      source: cam.CameraSource.Camera,
      width: 1920,
      height: 1920,
    });

    if (!photo.webPath) return null;

    // Convert to File object for the upload API
    const response = await fetch(photo.webPath);
    const blob = await response.blob();
    return new File([blob], "whiteboard.jpg", { type: "image/jpeg" });
  } catch {
    return null;
  }
}

// Trigger haptic feedback when available (Capacitor native)
export async function hapticImpact(style: "light" | "medium" | "heavy" = "medium") {
  try {
    const { Haptics, ImpactStyle } = await import("@capacitor/haptics");
    const styleMap = {
      light: ImpactStyle.Light,
      medium: ImpactStyle.Medium,
      heavy: ImpactStyle.Heavy,
    };
    await Haptics.impact({ style: styleMap[style] });
  } catch {
    // Not in native environment or haptics not available
  }
}

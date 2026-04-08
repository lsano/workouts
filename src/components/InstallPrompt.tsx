"use client";

import { useState, useEffect } from "react";

export function InstallPrompt() {
  const [showPrompt, setShowPrompt] = useState(false);
  const [isIOS, setIsIOS] = useState(false);
  const [dismissed, setDismissed] = useState(false);

  useEffect(() => {
    // Check if already installed as standalone
    const isStandalone = window.matchMedia("(display-mode: standalone)").matches;
    if (isStandalone) return;

    // Check if previously dismissed
    const wasDismissed = localStorage.getItem("wod-install-dismissed");
    if (wasDismissed) {
      const dismissedAt = parseInt(wasDismissed, 10);
      // Show again after 7 days
      if (Date.now() - dismissedAt < 7 * 24 * 60 * 60 * 1000) return;
    }

    const ios = /iPad|iPhone|iPod/.test(navigator.userAgent) && !("MSStream" in window);
    setIsIOS(ios);

    // Show after a short delay so it doesn't block initial interaction
    const timer = setTimeout(() => setShowPrompt(true), 3000);
    return () => clearTimeout(timer);
  }, []);

  const dismiss = () => {
    setDismissed(true);
    setShowPrompt(false);
    localStorage.setItem("wod-install-dismissed", String(Date.now()));
  };

  if (!showPrompt || dismissed) return null;

  return (
    <div className="fixed bottom-0 left-0 right-0 z-50 p-4 pb-[max(1rem,env(safe-area-inset-bottom))]">
      <div className="max-w-lg mx-auto bg-white dark:bg-gray-800 rounded-2xl shadow-2xl border border-gray-200 dark:border-gray-700 p-4">
        <div className="flex items-start gap-3">
          <img src="/icon-192.png" alt="WOD Tracker" className="w-12 h-12 rounded-xl" />
          <div className="flex-1 min-w-0">
            <h3 className="font-bold text-base">Install WOD Tracker</h3>
            {isIOS ? (
              <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                Tap the <span className="inline-block px-1 text-blue-500 font-medium">Share</span> button
                in Safari, then <span className="font-medium">&quot;Add to Home Screen&quot;</span> for
                the best gym experience.
              </p>
            ) : (
              <p className="text-sm text-gray-500 dark:text-gray-400 mt-1">
                Add to your home screen for quick access and offline support.
              </p>
            )}
          </div>
          <button
            onClick={dismiss}
            className="text-gray-400 p-1 -mt-1 -mr-1"
            aria-label="Dismiss"
          >
            &#x2715;
          </button>
        </div>
      </div>
    </div>
  );
}

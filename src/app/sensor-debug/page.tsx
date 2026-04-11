"use client";

import { useState, useEffect, useRef, useCallback } from "react";
import Link from "next/link";
import type { SensorSample, SensorSource } from "@/lib/sensor-types";

interface DiscoveredDevice {
  id: string;
  name: string;
  rssi: number;
}

interface ConnectedDevice {
  id: string;
  side: "left" | "right";
  name: string;
  connected: boolean;
  batteryLevel?: number;
}

interface SensorBuffer {
  left_foot: SensorSample[];
  right_foot: SensorSample[];
  watch: SensorSample[];
}

const BUFFER_MAX = 500; // ~10s at 50Hz
const CHART_POINTS = 200;

export default function SensorDebugPage() {
  const [scanning, setScanning] = useState(false);
  const [discovered, setDiscovered] = useState<DiscoveredDevice[]>([]);
  const [connected, setConnected] = useState<ConnectedDevice[]>([]);
  const [recording, setRecording] = useState(false);
  const [sampleCounts, setSampleCounts] = useState({ left_foot: 0, right_foot: 0, watch: 0 });
  const [activeSource, setActiveSource] = useState<SensorSource>("left_foot");
  const [watchConnected, setWatchConnected] = useState(false);

  const bufferRef = useRef<SensorBuffer>({
    left_foot: [],
    right_foot: [],
    watch: [],
  });
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const animFrameRef = useRef<number>(0);
  const cleanupFns = useRef<Array<() => void>>([]);

  // Draw the real-time chart
  const drawChart = useCallback(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;
    const ctx = canvas.getContext("2d");
    if (!ctx) return;

    const dpr = window.devicePixelRatio || 1;
    const rect = canvas.getBoundingClientRect();
    canvas.width = rect.width * dpr;
    canvas.height = rect.height * dpr;
    ctx.scale(dpr, dpr);

    const w = rect.width;
    const h = rect.height;

    // Clear
    ctx.fillStyle = "#111";
    ctx.fillRect(0, 0, w, h);

    const samples = bufferRef.current[activeSource];
    if (samples.length < 2) {
      ctx.fillStyle = "#666";
      ctx.font = "14px monospace";
      ctx.textAlign = "center";
      ctx.fillText("Waiting for sensor data...", w / 2, h / 2);
      animFrameRef.current = requestAnimationFrame(drawChart);
      return;
    }

    const recent = samples.slice(-CHART_POINTS);
    const xStep = w / CHART_POINTS;

    // Draw grid
    ctx.strokeStyle = "#333";
    ctx.lineWidth = 0.5;
    for (let y = 0; y <= h; y += h / 6) {
      ctx.beginPath();
      ctx.moveTo(0, y);
      ctx.lineTo(w, y);
      ctx.stroke();
    }

    // Scale: -4g to +4g
    const gRange = 4;
    const yScale = (val: number) => h / 2 - (val / gRange) * (h / 2);

    // Draw axes
    const channels: { key: keyof SensorSample; color: string; label: string }[] = [
      { key: "ax", color: "#ef4444", label: "X" },
      { key: "ay", color: "#22c55e", label: "Y" },
      { key: "az", color: "#3b82f6", label: "Z" },
    ];

    for (const ch of channels) {
      ctx.strokeStyle = ch.color;
      ctx.lineWidth = 1.5;
      ctx.beginPath();
      for (let i = 0; i < recent.length; i++) {
        const x = i * xStep;
        const y = yScale(recent[i][ch.key] as number);
        if (i === 0) ctx.moveTo(x, y);
        else ctx.lineTo(x, y);
      }
      ctx.stroke();
    }

    // Legend
    ctx.font = "12px monospace";
    channels.forEach((ch, i) => {
      ctx.fillStyle = ch.color;
      ctx.fillRect(8 + i * 50, 8, 12, 12);
      ctx.fillStyle = "#ccc";
      ctx.textAlign = "left";
      ctx.fillText(ch.label, 24 + i * 50, 18);
    });

    // Latest values
    if (recent.length > 0) {
      const last = recent[recent.length - 1];
      ctx.fillStyle = "#999";
      ctx.font = "11px monospace";
      ctx.textAlign = "right";
      ctx.fillText(
        `ax:${(last.ax as number).toFixed(2)} ay:${(last.ay as number).toFixed(2)} az:${(last.az as number).toFixed(2)}`,
        w - 8,
        18
      );
    }

    animFrameRef.current = requestAnimationFrame(drawChart);
  }, [activeSource]);

  // Start animation loop
  useEffect(() => {
    animFrameRef.current = requestAnimationFrame(drawChart);
    return () => cancelAnimationFrame(animFrameRef.current);
  }, [drawChart]);

  // Simulate sensor data in browser for testing
  useEffect(() => {
    if (typeof window === "undefined") return;

    // Check if running in Capacitor (native) or browser
    const isNative = !!(window as unknown as { Capacitor?: unknown }).Capacitor;

    if (!isNative) {
      // Simulate sensor data for browser testing
      const interval = setInterval(() => {
        if (!recording) return;

        const t = Date.now();
        const freq = 1.5; // Simulate pogo hops at 1.5Hz
        const phase = (t / 1000) * freq * Math.PI * 2;

        const sample: SensorSample = {
          timestamp: t,
          ax: Math.sin(phase) * 0.3 + (Math.random() - 0.5) * 0.1,
          ay: Math.cos(phase) * 2.0 + (Math.random() - 0.5) * 0.2,
          az: Math.sin(phase * 0.5) * 0.5 + 9.8 + (Math.random() - 0.5) * 0.1,
          gx: Math.cos(phase) * 0.5,
          gy: Math.sin(phase) * 0.3,
          gz: (Math.random() - 0.5) * 0.1,
        };

        for (const source of ["left_foot", "right_foot", "watch"] as SensorSource[]) {
          const offset = source === "right_foot" ? Math.PI * 0.1 : 0;
          const adjusted = {
            ...sample,
            ax: sample.ax + Math.sin(phase + offset) * 0.1,
            ay: sample.ay + Math.cos(phase + offset) * 0.15,
          };
          bufferRef.current[source].push(adjusted);
          if (bufferRef.current[source].length > BUFFER_MAX) {
            bufferRef.current[source] = bufferRef.current[source].slice(-BUFFER_MAX);
          }
        }

        setSampleCounts({
          left_foot: bufferRef.current.left_foot.length,
          right_foot: bufferRef.current.right_foot.length,
          watch: bufferRef.current.watch.length,
        });
      }, 20); // 50Hz

      return () => clearInterval(interval);
    }

    return () => {
      cleanupFns.current.forEach((fn) => fn());
      cleanupFns.current = [];
    };
  }, [recording]);

  const handleStartScan = async () => {
    setScanning(true);
    setDiscovered([]);

    // In browser mode, simulate device discovery
    const isNative = !!(window as unknown as { Capacitor?: unknown }).Capacitor;
    if (!isNative) {
      setTimeout(() => {
        setDiscovered([
          { id: "sim-left-001", name: "Stryd Left (Simulated)", rssi: -45 },
          { id: "sim-right-002", name: "Stryd Right (Simulated)", rssi: -48 },
        ]);
      }, 1500);
      setTimeout(() => setScanning(false), 3000);
      return;
    }

    try {
      const { startSensorScanning, onDeviceDiscovered } = await import(
        "@/lib/sensor-service"
      );
      const removeFn = await onDeviceDiscovered((device) => {
        setDiscovered((prev) => {
          if (prev.find((d) => d.id === device.id)) return prev;
          return [...prev, device];
        });
      });
      if (removeFn) cleanupFns.current.push(removeFn);
      await startSensorScanning();
      setTimeout(async () => {
        const { stopSensorScanning } = await import("@/lib/sensor-service");
        await stopSensorScanning();
        setScanning(false);
      }, 10000);
    } catch {
      setScanning(false);
    }
  };

  const handleConnect = async (deviceId: string, side: "left" | "right") => {
    const isNative = !!(window as unknown as { Capacitor?: unknown }).Capacitor;
    if (!isNative) {
      setConnected((prev) => [
        ...prev.filter((d) => d.side !== side),
        { id: deviceId, side, name: `Stryd ${side} (Sim)`, connected: true, batteryLevel: 87 },
      ]);
      return;
    }

    try {
      const { connectSensor } = await import("@/lib/sensor-service");
      const ok = await connectSensor(deviceId, side);
      if (ok) {
        setConnected((prev) => [
          ...prev.filter((d) => d.side !== side),
          { id: deviceId, side, name: `Stryd ${side}`, connected: true },
        ]);
      }
    } catch {
      // handle error
    }
  };

  const toggleRecording = () => {
    if (recording) {
      setRecording(false);
    } else {
      bufferRef.current = { left_foot: [], right_foot: [], watch: [] };
      setSampleCounts({ left_foot: 0, right_foot: 0, watch: 0 });
      setRecording(true);
    }
  };

  const exportData = () => {
    const data = {
      exportedAt: new Date().toISOString(),
      sources: {
        left_foot: bufferRef.current.left_foot,
        right_foot: bufferRef.current.right_foot,
        watch: bufferRef.current.watch,
      },
    };
    const blob = new Blob([JSON.stringify(data, null, 2)], {
      type: "application/json",
    });
    const url = URL.createObjectURL(blob);
    const a = document.createElement("a");
    a.href = url;
    a.download = `sensor-recording-${Date.now()}.json`;
    a.click();
    URL.revokeObjectURL(url);
  };

  const sourceColors: Record<SensorSource, string> = {
    left_foot: "text-red-400",
    right_foot: "text-blue-400",
    watch: "text-green-400",
  };

  return (
    <main className="flex-1 flex flex-col p-4 max-w-lg mx-auto w-full">
      {/* Header */}
      <div className="flex items-center gap-3 mb-6">
        <Link
          href="/"
          className="text-gray-400 hover:text-white transition-colors"
        >
          &larr;
        </Link>
        <h1 className="text-2xl font-bold">Sensor Debug</h1>
      </div>

      {/* Connection Status */}
      <section className="mb-6">
        <h2 className="text-sm font-semibold text-gray-400 uppercase mb-3">
          Sensor Connections
        </h2>
        <div className="grid grid-cols-3 gap-2 mb-3">
          {(["left_foot", "right_foot", "watch"] as SensorSource[]).map(
            (source) => {
              const isConnected =
                source === "watch"
                  ? watchConnected
                  : connected.some((d) => d.side === (source === "left_foot" ? "left" : "right") && d.connected);
              return (
                <div
                  key={source}
                  className={`p-3 rounded-xl border text-center ${
                    isConnected
                      ? "border-green-500/50 bg-green-500/10"
                      : "border-gray-700 bg-gray-800/50"
                  }`}
                >
                  <div
                    className={`w-3 h-3 rounded-full mx-auto mb-1 ${
                      isConnected ? "bg-green-500" : "bg-gray-600"
                    }`}
                  />
                  <div className="text-xs font-medium">
                    {source === "left_foot"
                      ? "Left Foot"
                      : source === "right_foot"
                        ? "Right Foot"
                        : "Watch"}
                  </div>
                  <div className="text-xs text-gray-500">
                    {isConnected ? "Connected" : "---"}
                  </div>
                </div>
              );
            }
          )}
        </div>

        <button
          onClick={handleStartScan}
          disabled={scanning}
          className="w-full py-2.5 rounded-xl bg-blue-600 text-white font-medium disabled:opacity-50 disabled:cursor-not-allowed active:scale-[0.98] transition-transform"
        >
          {scanning ? "Scanning..." : "Scan for Sensors"}
        </button>

        {/* Discovered Devices */}
        {discovered.length > 0 && (
          <div className="mt-3 space-y-2">
            {discovered.map((device) => (
              <div
                key={device.id}
                className="flex items-center justify-between p-3 rounded-xl bg-gray-800 border border-gray-700"
              >
                <div>
                  <div className="font-medium text-sm">{device.name || "Unknown"}</div>
                  <div className="text-xs text-gray-500">
                    RSSI: {device.rssi}dBm
                  </div>
                </div>
                <div className="flex gap-2">
                  <button
                    onClick={() => handleConnect(device.id, "left")}
                    className="px-3 py-1.5 text-xs rounded-lg bg-red-600/20 text-red-400 border border-red-600/30 active:scale-95"
                  >
                    Left
                  </button>
                  <button
                    onClick={() => handleConnect(device.id, "right")}
                    className="px-3 py-1.5 text-xs rounded-lg bg-blue-600/20 text-blue-400 border border-blue-600/30 active:scale-95"
                  >
                    Right
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </section>

      {/* Real-time Chart */}
      <section className="mb-6">
        <h2 className="text-sm font-semibold text-gray-400 uppercase mb-3">
          Live Accelerometer
        </h2>
        <div className="flex gap-1 mb-2">
          {(["left_foot", "right_foot", "watch"] as SensorSource[]).map(
            (source) => (
              <button
                key={source}
                onClick={() => setActiveSource(source)}
                className={`flex-1 py-1.5 text-xs font-medium rounded-lg transition-colors ${
                  activeSource === source
                    ? `${sourceColors[source]} bg-gray-700 border border-gray-600`
                    : "text-gray-500 bg-gray-800/50 border border-gray-800"
                }`}
              >
                {source === "left_foot"
                  ? "L Foot"
                  : source === "right_foot"
                    ? "R Foot"
                    : "Watch"}
              </button>
            )
          )}
        </div>
        <canvas
          ref={canvasRef}
          className="w-full rounded-xl border border-gray-700"
          style={{ height: "200px" }}
        />
      </section>

      {/* Sample Counts */}
      <section className="mb-6">
        <h2 className="text-sm font-semibold text-gray-400 uppercase mb-3">
          Sample Buffer
        </h2>
        <div className="grid grid-cols-3 gap-2">
          {(["left_foot", "right_foot", "watch"] as SensorSource[]).map(
            (source) => (
              <div
                key={source}
                className="p-3 rounded-xl bg-gray-800/50 border border-gray-700 text-center"
              >
                <div className={`text-2xl font-bold ${sourceColors[source]}`}>
                  {sampleCounts[source]}
                </div>
                <div className="text-xs text-gray-500">
                  {source === "left_foot"
                    ? "Left"
                    : source === "right_foot"
                      ? "Right"
                      : "Watch"}
                </div>
              </div>
            )
          )}
        </div>
      </section>

      {/* Recording Controls */}
      <section className="space-y-3">
        <button
          onClick={toggleRecording}
          className={`w-full py-3 rounded-xl font-semibold text-white active:scale-[0.98] transition-transform ${
            recording
              ? "bg-red-600 animate-pulse"
              : "bg-green-600"
          }`}
        >
          {recording ? "Stop Recording" : "Start Recording"}
        </button>

        {sampleCounts.left_foot > 0 && (
          <button
            onClick={exportData}
            className="w-full py-3 rounded-xl font-semibold text-white bg-gray-700 active:scale-[0.98] transition-transform"
          >
            Export Recording (JSON)
          </button>
        )}
      </section>

      {/* Watch Connection Toggle */}
      <section className="mt-6">
        <button
          onClick={() => setWatchConnected(!watchConnected)}
          className="w-full py-2.5 rounded-xl bg-gray-800 border border-gray-700 text-sm text-gray-300 active:scale-[0.98]"
        >
          {watchConnected
            ? "Disconnect Watch (Simulated)"
            : "Connect Watch (Simulated)"}
        </button>
      </section>
    </main>
  );
}

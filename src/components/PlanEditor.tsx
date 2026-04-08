"use client";

import { useState, useCallback } from "react";

interface TranscribedExercise {
  exercise_name: string;
  notes?: string | null;
}

interface TranscribedSection {
  name: string;
  section_type: string;
  work_seconds?: number | null;
  rest_seconds?: number | null;
  rounds?: number | null;
  exercises: TranscribedExercise[];
}

export interface TranscribedPlan {
  name?: string;
  sections: TranscribedSection[];
}

interface PlanEditorProps {
  plan: TranscribedPlan;
  onChange: (plan: TranscribedPlan) => void;
  onStart: () => void;
  onRescan: () => void;
}

export function PlanEditor({ plan, onChange, onStart, onRescan }: PlanEditorProps) {
  const [dragSource, setDragSource] = useState<{ type: "section" | "exercise"; sectionIdx: number; exerciseIdx?: number } | null>(null);
  const [dragOver, setDragOver] = useState<{ type: "section" | "exercise"; sectionIdx: number; exerciseIdx?: number } | null>(null);
  const [editingExercise, setEditingExercise] = useState<{ sectionIdx: number; exerciseIdx: number } | null>(null);
  const [editingSection, setEditingSection] = useState<number | null>(null);

  // -- Section operations --

  const moveSection = useCallback((fromIdx: number, toIdx: number) => {
    if (fromIdx === toIdx) return;
    const sections = [...plan.sections];
    const [moved] = sections.splice(fromIdx, 1);
    sections.splice(toIdx, 0, moved);
    onChange({ ...plan, sections });
  }, [plan, onChange]);

  const updateSection = useCallback((idx: number, updates: Partial<TranscribedSection>) => {
    const sections = plan.sections.map((s, i) => i === idx ? { ...s, ...updates } : s);
    onChange({ ...plan, sections });
  }, [plan, onChange]);

  const deleteSection = useCallback((idx: number) => {
    onChange({ ...plan, sections: plan.sections.filter((_, i) => i !== idx) });
  }, [plan, onChange]);

  // -- Exercise operations --

  const moveExercise = useCallback((fromSection: number, fromIdx: number, toSection: number, toIdx: number) => {
    if (fromSection === toSection && fromIdx === toIdx) return;
    const sections = plan.sections.map(s => ({ ...s, exercises: [...s.exercises] }));
    const [moved] = sections[fromSection].exercises.splice(fromIdx, 1);
    sections[toSection].exercises.splice(toIdx, 0, moved);
    onChange({ ...plan, sections });
  }, [plan, onChange]);

  const updateExercise = useCallback((sectionIdx: number, exerciseIdx: number, updates: Partial<TranscribedExercise>) => {
    const sections = plan.sections.map((s, si) => si === sectionIdx ? {
      ...s,
      exercises: s.exercises.map((e, ei) => ei === exerciseIdx ? { ...e, ...updates } : e),
    } : s);
    onChange({ ...plan, sections });
  }, [plan, onChange]);

  const deleteExercise = useCallback((sectionIdx: number, exerciseIdx: number) => {
    const sections = plan.sections.map((s, si) => si === sectionIdx ? {
      ...s,
      exercises: s.exercises.filter((_, ei) => ei !== exerciseIdx),
    } : s);
    onChange({ ...plan, sections: sections.filter(s => s.exercises.length > 0) });
  }, [plan, onChange]);

  // -- Touch-based reordering via buttons --

  const moveSectionUp = (idx: number) => { if (idx > 0) moveSection(idx, idx - 1); };
  const moveSectionDown = (idx: number) => { if (idx < plan.sections.length - 1) moveSection(idx, idx + 1); };
  const moveExerciseUp = (si: number, ei: number) => { if (ei > 0) moveExercise(si, ei, si, ei - 1); };
  const moveExerciseDown = (si: number, ei: number) => {
    if (ei < plan.sections[si].exercises.length - 1) moveExercise(si, ei, si, ei + 1);
  };

  // -- Drag and drop handlers --

  const handleDragStart = (type: "section" | "exercise", sectionIdx: number, exerciseIdx?: number) => {
    setDragSource({ type, sectionIdx, exerciseIdx });
  };

  const handleDragOver = (e: React.DragEvent, type: "section" | "exercise", sectionIdx: number, exerciseIdx?: number) => {
    e.preventDefault();
    setDragOver({ type, sectionIdx, exerciseIdx });
  };

  const handleDrop = (e: React.DragEvent) => {
    e.preventDefault();
    if (!dragSource || !dragOver) return;

    if (dragSource.type === "section" && dragOver.type === "section") {
      moveSection(dragSource.sectionIdx, dragOver.sectionIdx);
    } else if (dragSource.type === "exercise" && dragOver.type === "exercise" && dragSource.exerciseIdx !== undefined && dragOver.exerciseIdx !== undefined) {
      moveExercise(dragSource.sectionIdx, dragSource.exerciseIdx, dragOver.sectionIdx, dragOver.exerciseIdx);
    }

    setDragSource(null);
    setDragOver(null);
  };

  const handleDragEnd = () => {
    setDragSource(null);
    setDragOver(null);
  };

  const SECTION_TYPES = ["warmup", "station", "circuit", "tabata", "amrap", "emom", "cooldown", "choice"];

  return (
    <div className="space-y-4">
      {/* Header */}
      <div className="flex items-center justify-between">
        <div className="flex-1">
          <input
            type="text"
            value={plan.name || ""}
            onChange={(e) => onChange({ ...plan, name: e.target.value })}
            placeholder="Workout name"
            className="text-lg font-bold w-full bg-transparent border-b border-transparent focus:border-blue-500 outline-none px-1 py-0.5"
          />
        </div>
        <button onClick={onRescan} className="text-sm text-blue-500 font-medium ml-3">
          Re-scan
        </button>
      </div>

      <p className="text-xs text-gray-500">
        Tap exercises to edit. Use arrows or drag to reorder.
      </p>

      {/* Sections */}
      {plan.sections.map((section, si) => {
        const isSectionDragOver = dragOver?.type === "section" && dragOver.sectionIdx === si;

        return (
          <div
            key={si}
            draggable
            onDragStart={() => handleDragStart("section", si)}
            onDragOver={(e) => handleDragOver(e, "section", si)}
            onDrop={handleDrop}
            onDragEnd={handleDragEnd}
            className={`bg-white dark:bg-gray-800 rounded-xl shadow-sm overflow-hidden transition-all ${
              isSectionDragOver ? "ring-2 ring-blue-500" : ""
            }`}
          >
            {/* Section header */}
            <div className="p-3 bg-gray-50 dark:bg-gray-750 border-b border-gray-100 dark:border-gray-700">
              <div className="flex items-center gap-2">
                {/* Reorder buttons */}
                <div className="flex flex-col gap-0.5">
                  <button
                    onClick={() => moveSectionUp(si)}
                    disabled={si === 0}
                    className="text-gray-400 disabled:opacity-20 text-xs leading-none p-0.5"
                    aria-label="Move section up"
                  >
                    &#x25B2;
                  </button>
                  <button
                    onClick={() => moveSectionDown(si)}
                    disabled={si === plan.sections.length - 1}
                    className="text-gray-400 disabled:opacity-20 text-xs leading-none p-0.5"
                    aria-label="Move section down"
                  >
                    &#x25BC;
                  </button>
                </div>

                {/* Section name / type */}
                <div className="flex-1 min-w-0">
                  {editingSection === si ? (
                    <div className="space-y-2">
                      <input
                        type="text"
                        value={section.name}
                        onChange={(e) => updateSection(si, { name: e.target.value })}
                        onBlur={() => setEditingSection(null)}
                        autoFocus
                        className="font-semibold text-sm w-full bg-white dark:bg-gray-700 rounded px-2 py-1 outline-none ring-1 ring-blue-400"
                      />
                      <select
                        value={section.section_type}
                        onChange={(e) => updateSection(si, { section_type: e.target.value })}
                        className="text-xs bg-white dark:bg-gray-700 rounded px-2 py-1"
                      >
                        {SECTION_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
                      </select>
                    </div>
                  ) : (
                    <div className="flex items-center gap-2 cursor-pointer" onClick={() => setEditingSection(si)}>
                      <h3 className="font-semibold text-sm truncate">{section.name}</h3>
                      <span className="text-[10px] px-1.5 py-0.5 rounded-full bg-blue-100 dark:bg-blue-900 text-blue-700 dark:text-blue-300 flex-shrink-0">
                        {section.section_type}
                      </span>
                    </div>
                  )}
                </div>

                {/* Delete section */}
                <button
                  onClick={() => deleteSection(si)}
                  className="text-red-400 hover:text-red-600 text-sm p-1"
                  aria-label="Delete section"
                >
                  &#x2715;
                </button>
              </div>

              {/* Timing */}
              {editingSection === si && (
                <div className="flex gap-2 mt-2">
                  <label className="text-xs text-gray-500">
                    Work
                    <input
                      type="number"
                      value={section.work_seconds ?? ""}
                      onChange={(e) => updateSection(si, { work_seconds: e.target.value ? Number(e.target.value) : null })}
                      placeholder="sec"
                      className="block w-16 mt-0.5 bg-white dark:bg-gray-700 rounded px-2 py-1 text-xs"
                    />
                  </label>
                  <label className="text-xs text-gray-500">
                    Rest
                    <input
                      type="number"
                      value={section.rest_seconds ?? ""}
                      onChange={(e) => updateSection(si, { rest_seconds: e.target.value ? Number(e.target.value) : null })}
                      placeholder="sec"
                      className="block w-16 mt-0.5 bg-white dark:bg-gray-700 rounded px-2 py-1 text-xs"
                    />
                  </label>
                  <label className="text-xs text-gray-500">
                    Rounds
                    <input
                      type="number"
                      value={section.rounds ?? ""}
                      onChange={(e) => updateSection(si, { rounds: e.target.value ? Number(e.target.value) : null })}
                      placeholder="#"
                      className="block w-16 mt-0.5 bg-white dark:bg-gray-700 rounded px-2 py-1 text-xs"
                    />
                  </label>
                </div>
              )}

              {editingSection !== si && (section.work_seconds || section.rest_seconds || section.rounds) && (
                <div className="flex gap-3 mt-1 text-[11px] text-gray-500">
                  {section.work_seconds && <span>Work: {section.work_seconds}s</span>}
                  {section.rest_seconds && <span>Rest: {section.rest_seconds}s</span>}
                  {section.rounds && <span>Rounds: {section.rounds}</span>}
                </div>
              )}
            </div>

            {/* Exercises */}
            <div className="p-2 space-y-1">
              {section.exercises.map((ex, ei) => {
                const isExDragOver = dragOver?.type === "exercise" && dragOver.sectionIdx === si && dragOver.exerciseIdx === ei;
                const isEditing = editingExercise?.sectionIdx === si && editingExercise?.exerciseIdx === ei;

                return (
                  <div
                    key={ei}
                    draggable
                    onDragStart={(e) => { e.stopPropagation(); handleDragStart("exercise", si, ei); }}
                    onDragOver={(e) => { e.stopPropagation(); handleDragOver(e, "exercise", si, ei); }}
                    onDrop={(e) => { e.stopPropagation(); handleDrop(e); }}
                    onDragEnd={handleDragEnd}
                    className={`flex items-center gap-1.5 rounded-lg px-2 py-1.5 transition-all ${
                      isExDragOver ? "bg-blue-50 dark:bg-blue-900/30 ring-1 ring-blue-400" : "hover:bg-gray-50 dark:hover:bg-gray-750"
                    }`}
                  >
                    {/* Reorder */}
                    <div className="flex flex-col gap-0">
                      <button
                        onClick={() => moveExerciseUp(si, ei)}
                        disabled={ei === 0}
                        className="text-gray-400 disabled:opacity-20 text-[10px] leading-none p-0.5"
                      >
                        &#x25B2;
                      </button>
                      <button
                        onClick={() => moveExerciseDown(si, ei)}
                        disabled={ei === section.exercises.length - 1}
                        className="text-gray-400 disabled:opacity-20 text-[10px] leading-none p-0.5"
                      >
                        &#x25BC;
                      </button>
                    </div>

                    {/* Exercise content */}
                    <div className="flex-1 min-w-0">
                      {isEditing ? (
                        <div className="space-y-1">
                          <input
                            type="text"
                            value={ex.exercise_name}
                            onChange={(e) => updateExercise(si, ei, { exercise_name: e.target.value })}
                            autoFocus
                            className="text-sm w-full bg-white dark:bg-gray-700 rounded px-2 py-1 outline-none ring-1 ring-blue-400"
                          />
                          <input
                            type="text"
                            value={ex.notes || ""}
                            onChange={(e) => updateExercise(si, ei, { notes: e.target.value || null })}
                            onBlur={() => setEditingExercise(null)}
                            placeholder="Notes (optional)"
                            className="text-xs w-full bg-white dark:bg-gray-700 rounded px-2 py-1 outline-none ring-1 ring-gray-300 dark:ring-gray-600"
                          />
                        </div>
                      ) : (
                        <div
                          className="cursor-pointer"
                          onClick={() => setEditingExercise({ sectionIdx: si, exerciseIdx: ei })}
                        >
                          <span className="text-sm">{ex.exercise_name}</span>
                          {ex.notes && (
                            <span className="text-xs text-gray-400 ml-1">({ex.notes})</span>
                          )}
                        </div>
                      )}
                    </div>

                    {/* Delete exercise */}
                    <button
                      onClick={() => deleteExercise(si, ei)}
                      className="text-red-400 hover:text-red-600 text-xs p-1 flex-shrink-0"
                    >
                      &#x2715;
                    </button>
                  </div>
                );
              })}
            </div>
          </div>
        );
      })}

      {/* Start button */}
      <button
        onClick={onStart}
        className="w-full py-4 rounded-2xl font-bold text-lg bg-green-500 text-white active:bg-green-600 shadow-lg"
      >
        Start Workout
      </button>
    </div>
  );
}

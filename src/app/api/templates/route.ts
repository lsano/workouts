import { NextRequest, NextResponse } from "next/server";
import { getTemplates } from "@/lib/hiit-templates";

export async function GET(request: NextRequest) {
  const { searchParams } = new URL(request.url);
  const style = searchParams.get("style") || undefined;
  const equipment = searchParams.get("equipment") || undefined;
  const difficulty = searchParams.get("difficulty") || undefined;
  const muscleGroup = searchParams.get("muscleGroup") || undefined;

  const templates = getTemplates({ style, equipment, difficulty, muscleGroup });
  return NextResponse.json(templates);
}

import { NextRequest, NextResponse } from "next/server";
import { updateSet } from "@/lib/workouts";

export async function PATCH(
  request: NextRequest,
  { params }: { params: Promise<{ setId: string }> }
) {
  const { setId } = await params;
  const body = await request.json();
  updateSet(setId, body);
  return NextResponse.json({ success: true });
}

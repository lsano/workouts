import { NextRequest, NextResponse } from "next/server";

// This endpoint accepts an image and uses the Anthropic API to transcribe
// a whiteboard workout plan into structured data.
// Requires ANTHROPIC_API_KEY environment variable.

const SYSTEM_PROMPT = `You are a workout plan transcriber. Given an image of a whiteboard with a workout plan written on it, extract and structure the workout into JSON format.

Output ONLY valid JSON with this structure:
{
  "name": "Workout name or date-based name",
  "sections": [
    {
      "name": "Section name (e.g. Warm-Up, Station 1, Tabata, etc.)",
      "section_type": "warmup|station|circuit|tabata|amrap|emom|cooldown|choice",
      "work_seconds": number or null,
      "rest_seconds": number or null,
      "rounds": number or null,
      "exercises": [
        {
          "exercise_name": "Exercise name",
          "notes": "Any notes like R+L, or alternative exercises"
        }
      ]
    }
  ]
}

Rules:
- Parse timing notations like "0:31/0:15" as work_seconds: 31, rest_seconds: 15
- Parse "x4" as rounds: 4
- For warm-ups with "30s each", set work_seconds: 30
- If exercises have alternatives (marked with "or"), include both with notes
- Clean up fun/themed names but keep them recognizable (e.g., "KB Goblin Squats" stays as-is)
- For bilateral exercises marked with (R+L), add that to notes
- Tabata notation "0:20/0:10 x4" means work_seconds: 20, rest_seconds: 10, rounds: 4
- Group exercises under their station/section headers`;

export async function POST(request: NextRequest) {
  const apiKey = process.env.ANTHROPIC_API_KEY;

  if (!apiKey) {
    // Return a demo transcription when no API key is configured
    return NextResponse.json({
      name: "Demo Workout (Set ANTHROPIC_API_KEY for real transcription)",
      sections: [
        {
          name: "Warm-Up",
          section_type: "warmup",
          work_seconds: 30,
          rest_seconds: null,
          rounds: null,
          exercises: [
            { exercise_name: "Floor Slides", notes: null },
            { exercise_name: "Lying Rotation w/ Shoulder Sweep", notes: "R+L" },
            { exercise_name: "Down Dog Knee Extensions", notes: null },
            { exercise_name: "Squat to Stand", notes: null },
            { exercise_name: "Kneeling Adductor Rocks", notes: "R+L" },
          ],
        },
        {
          name: "Station 1",
          section_type: "station",
          work_seconds: 31,
          rest_seconds: 15,
          rounds: 4,
          exercises: [
            { exercise_name: "KB Goblin Squats", notes: null },
            { exercise_name: "Pumpkin Push-ups", notes: null },
            { exercise_name: "Partner Pumpkin Toss", notes: "or Dead Bugs" },
            { exercise_name: "Blood Curdling Bicep Curls", notes: null },
          ],
        },
        {
          name: "Station 2",
          section_type: "station",
          work_seconds: 31,
          rest_seconds: 15,
          rounds: 4,
          exercises: [
            { exercise_name: "BOO-ty Band Walks", notes: null },
            { exercise_name: "Walking Dead Lunges", notes: null },
            { exercise_name: "BOO Burpees", notes: null },
            { exercise_name: "Spider Crawls", notes: null },
          ],
        },
        {
          name: "Booty Tabata",
          section_type: "tabata",
          work_seconds: 20,
          rest_seconds: 10,
          rounds: 4,
          exercises: [
            { exercise_name: "Band Glute Bridge", notes: null },
            { exercise_name: "Donkey Kicks", notes: "R+L" },
          ],
        },
      ],
    });
  }

  try {
    const formData = await request.formData();
    const imageFile = formData.get("image") as File;

    if (!imageFile) {
      return NextResponse.json({ error: "No image provided" }, { status: 400 });
    }

    // Validate file size (max 10MB)
    const MAX_FILE_SIZE = 10 * 1024 * 1024;
    if (imageFile.size > MAX_FILE_SIZE) {
      return NextResponse.json({ error: "File too large (max 10MB)" }, { status: 413 });
    }

    // Validate MIME type
    const ALLOWED_TYPES = ["image/jpeg", "image/png", "image/webp", "image/gif"];
    if (!ALLOWED_TYPES.includes(imageFile.type)) {
      return NextResponse.json({ error: "Invalid file type. Use JPEG, PNG, or WebP." }, { status: 400 });
    }

    const bytes = await imageFile.arrayBuffer();
    const base64 = Buffer.from(bytes).toString("base64");
    const mediaType = imageFile.type;

    const response = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": apiKey,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-sonnet-4-20250514",
        max_tokens: 2000,
        system: SYSTEM_PROMPT,
        messages: [
          {
            role: "user",
            content: [
              {
                type: "image",
                source: {
                  type: "base64",
                  media_type: mediaType,
                  data: base64,
                },
              },
              {
                type: "text",
                text: "Transcribe this whiteboard workout plan into structured JSON.",
              },
            ],
          },
        ],
      }),
    });

    if (!response.ok) {
      console.error("Anthropic API error:", response.status, await response.text());
      return NextResponse.json(
        { error: "Image transcription service error. Please try again." },
        { status: 502 }
      );
    }

    const result = await response.json();
    const textContent = result.content.find((c: { type: string }) => c.type === "text");
    const jsonText = textContent?.text || "{}";

    // Parse the JSON from the response (may be wrapped in ```json blocks)
    const cleaned = jsonText.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();

    let parsed;
    try {
      parsed = JSON.parse(cleaned);
    } catch {
      console.error("Failed to parse transcription response as JSON");
      return NextResponse.json(
        { error: "Could not parse the workout from this image. Try a clearer photo." },
        { status: 422 }
      );
    }

    // Validate basic structure
    if (!parsed.sections || !Array.isArray(parsed.sections)) {
      return NextResponse.json(
        { error: "Could not identify workout sections in this image." },
        { status: 422 }
      );
    }

    return NextResponse.json(parsed);
  } catch (error) {
    console.error("Transcription error:", error);
    return NextResponse.json(
      { error: "Failed to transcribe image. Please try again." },
      { status: 500 }
    );
  }
}

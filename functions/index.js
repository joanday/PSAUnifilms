// Force redeploy - SDK upgrade to @google/genai@latest
// redeploy-trigger-v2

const {onDocumentUpdated, onDocumentCreated} = require("firebase-functions/v2/firestore");
const {onCall, HttpsError} = require("firebase-functions/v2/https");
const {initializeApp} = require("firebase-admin/app");
const {getMessaging} = require("firebase-admin/messaging");
const {getFirestore, FieldValue} = require("firebase-admin/firestore");
const axios = require("axios");
const fs = require("fs");
const path = require("path");
const os = require("os");
const { GoogleGenAI } = require("@google/genai");
const { defineSecret } = require("firebase-functions/params");

initializeApp();

const db = getFirestore();

// Reads the value you stored with: firebase functions:secrets:set PSAUNIFILMS
const geminiApiKeySecret = defineSecret("PSAUNIFILMS");

// FIX: ONE embedding model used everywhere in this file.
// We strictly use "gemini-embedding-2" to ensure vector compatibility
// and prevent empty search results caused by differing embedding spaces.
const EMBEDDING_MODEL = "gemini-embedding-2";
const EMBEDDING_DIMENSION = 768;

// Lazy-initialize AI client to avoid deployment timeout during module analysis
let _ai = null;
function getAI() {
    if (!_ai) _ai = new GoogleGenAI({ apiKey: geminiApiKeySecret.value() });
    return _ai;
}

// Trigger when a film is approved by an officer
exports.notifyOnNewUpload = onDocumentUpdated(
    "films/{filmId}",
    async (event) => {
        const newData = event.data.after.data();
        const previousData = event.data.before.data();

        if (newData.status === 'approved' && previousData.status !== 'approved') {
            const message = {
                notification: {
                    title: 'New Documentary Available!',
                    body: `${newData.title} has just been added. Watch it now!`,
                },
                topic: 'all_users',
            };

            try {
                await getMessaging().send(message);
                console.log('Notification sent successfully for film:', newData.title);
            } catch (error) {
                console.error('Error sending notification:', error);
            }
        }
    }
);

// NEW: Flips a film's visibility status from "processing" to "approved"
// once Bunny encoding + the AI analysis (success, fallback, or even total
// failure) have all finished running. It ONLY does this if the film is
// still sitting at "processing" -- so it will never touch a film that's
// already "approved" or one an admin deliberately "archived" (e.g. when
// they hit "Retry AI" on an old film from the Edit Documentary Videos
// screen, this function runs again but leaves its status alone).
//
// It fires on every exit path of processCBVR (full success, fallback
// success, and even total failure) on purpose: a video should never stay
// permanently hidden from Watch just because the AI step hit an error --
// the admin can always fix the AI insights later with Retry AI once the
// film is already visible.
async function markApprovedIfProcessing(filmId) {
    try {
        const doc = await db.collection("films").doc(filmId).get();
        if (doc.exists && doc.data().status === "processing") {
            await db.collection("films").doc(filmId).update({ status: "approved" });
            console.log(`Film ${filmId} finished processing -- now approved and visible on Watch.`);
        }
    } catch (e) {
        console.error(`Failed to mark film ${filmId} as approved:`, e.message);
    }
}

// Fallback: embed ONLY the uploader-provided text (title, description, genre,
// director). Used when full video analysis is blocked or fails for any reason,
// so the film still becomes searchable via vector search instead of vanishing
// from search entirely.
async function generateFallbackEmbedding(filmId, filmData, reason) {
    try {
        console.log(`Generating FALLBACK embedding for ${filmId} (reason: ${reason})`);

        const fallbackText = `
Title: ${filmData.title || ''}
Director: ${filmData.director || ''}
Genre: ${filmData.genre || ''}
Description: ${filmData.description || '(no description provided)'}
        `.trim();

        const embedResult = await getAI().models.embedContent({
            model: EMBEDDING_MODEL,
            contents: fallbackText,
            config: { outputDimensionality: EMBEDDING_DIMENSION }
        });

        const embeddingVector = embedResult.embeddings[0].values;

        await db.collection("films").doc(filmId).update({
            embedding: FieldValue.vector(embeddingVector),
            cbvrStatus: "completed_fallback",
            cbvrError: `Full video analysis unavailable (${reason}). Search is based on the uploader's title/description only.`,
            // Make sure the uploader's own description is what shows as the
            // summary, since AI could not produce one.
            aiSummary: filmData.aiSummary || filmData.description || '',
            aiKeywords: filmData.aiKeywords || [],
        });

        console.log(`Fallback embedding saved for ${filmId}.`);
        await markApprovedIfProcessing(filmId);
        return true;
    } catch (fallbackError) {
        console.error(`Fallback embedding ALSO failed for ${filmId}:`, fallbackError.message);
        await db.collection("films").doc(filmId).update({
            cbvrStatus: "failed",
            cbvrError: `Both full analysis and fallback embedding failed: ${fallbackError.message}`
        });
        // Even a total AI failure shouldn't hide the film forever -- the
        // video itself is fine, only the AI insights are missing. The
        // admin can fix that later with Retry AI once it's already live.
        await markApprovedIfProcessing(filmId);
        return false;
    }
}

async function processCBVR(filmId, filmData) {
    if (!filmData.videoUrl) throw new Error("No video URL");

    try {
        const urlParts = filmData.videoUrl.split("/");
        if (urlParts.length < 5) throw new Error("Invalid Bunny.net URL format");

        const pullZone = urlParts[2];
        const guid = urlParts[3];
        const mp4Url = `https://${pullZone}/${guid}/play_480p.mp4`;

        // Mark as waiting for video to be ready
        await db.collection("films").doc(filmId).update({ cbvrStatus: "waiting" });

        let isReady = false;
        for (let i = 0; i < 30; i++) {
            try {
                const resp = await axios.head(mp4Url);
                if (resp.status === 200) {
                    isReady = true;
                    break;
                }
            } catch (e) {}
            console.log(`Video not ready. Waiting 20s... (${i+1}/30)`);
            await new Promise(r => setTimeout(r, 20000));
        }

        if (!isReady) {
            throw new Error("Video took too long to encode or 480p fallback is not enabled.");
        }

        console.log("Video is ready! Downloading to /tmp...");
        await db.collection("films").doc(filmId).update({ cbvrStatus: "downloading" });

        const tempFilePath = path.join(os.tmpdir(), `${guid}.mp4`);
        const writer = fs.createWriteStream(tempFilePath);

        const response = await axios({
            url: mp4Url,
            method: "GET",
            responseType: "stream"
        });

        response.data.pipe(writer);

        await new Promise((resolve, reject) => {
            writer.on("finish", resolve);
            writer.on("error", reject);
        });

        console.log("Uploading to Gemini File API via REST...");
        await db.collection("films").doc(filmId).update({ cbvrStatus: "uploading", cbvrProgress: 0 });

        // Step 1: Upload file to Gemini File API using direct REST (bypasses SDK v1beta issues)
        // Fixed: Use fs.statSync to get size instead of readFileSync to avoid Out-Of-Memory limits
        const stat = fs.statSync(tempFilePath);
        const fileSize = stat.size;
        const GEMINI_BASE = "https://generativelanguage.googleapis.com";

        // Initiate resumable upload
        const initUpload = await axios.post(
            `${GEMINI_BASE}/upload/v1beta/files?key=${geminiApiKeySecret.value()}`,
            { file: { display_name: `film_${filmId}` } },
            {
                headers: {
                    "X-Goog-Upload-Protocol": "resumable",
                    "X-Goog-Upload-Command": "start",
                    "X-Goog-Upload-Header-Content-Length": fileSize,
                    "X-Goog-Upload-Header-Content-Type": "video/mp4",
                    "Content-Type": "application/json",
                }
            }
        );

        const uploadUrl = initUpload.headers["x-goog-upload-url"];
        if (!uploadUrl) throw new Error("No upload URL returned from Gemini File API");

        // Upload the actual bytes using the official Google Gen AI SDK.
        // This is 100% stable and handles resumable uploads reliably without hanging.

        let simProgress = 0;
        const progressInterval = setInterval(() => {
            if (simProgress < 90) {
                simProgress += 5;
                db.collection("films").doc(filmId)
                  .update({ cbvrProgress: simProgress })
                  .catch(() => {});
            }
        }, 3000);

        let uploadResp;
        try {
            uploadResp = await getAI().files.upload({
                file: tempFilePath,
                mimeType: "video/mp4",
                displayName: `film_${filmId}`
            });
        } finally {
            clearInterval(progressInterval);
        }

        let fileUri = uploadResp.uri;
        let fileName = uploadResp.name;
        let fileState = uploadResp.state;

        if (!fileUri) throw new Error("File upload failed -- no URI returned");

        // Ensure progress hits 100% when upload completes
        await db.collection("films").doc(filmId).update({ cbvrProgress: 100 });

        console.log(`File uploaded: ${fileName}. State: ${fileState}. Waiting for processing...`);
        await db.collection("films").doc(filmId).update({ cbvrStatus: "analyzing" });

        // Step 2: Wait for file to be ACTIVE
        while (fileState === "PROCESSING") {
            await new Promise(r => setTimeout(r, 5000));
            const statusResp = await axios.get(
                `${GEMINI_BASE}/v1beta/${fileName}?key=${geminiApiKeySecret.value()}`
            );
            fileState = statusResp.data?.state;
            console.log(`File state: ${fileState}`);
        }

        if (fileState === "FAILED") throw new Error("Gemini File processing failed.");

        console.log("Analyzing with Gemini via REST...");

        const prompt = `You are an expert documentary film analyst for a Philippine university platform called PSAUnifilms.

Your task is to DEEPLY ANALYZE this documentary video by watching the entire video carefully, frame by frame, listening to every word of narration,dialogue, and ambient sounds.

UPLOADER'S SUBMITTED DESCRIPTION:
"""
${filmData.description || "(No description provided by uploader)"}
"""

WHAT TO ANALYZE:
1. NARRATION & DIALOGUE: Transcribe and summarize EVERY word spoken -- by narrators, subjects, and interviewees. Include the actual topics, facts,names, and specific details mentioned.
2. VISUAL SCENES: Describe EVERY significant scene. What is shown? Who are the people? What are they doing? What is their occupation, role, or activity?
3. OBJECTS & ELEMENTS: List EVERY significant physical object, animal, food, tool, body of water, location, landmark, or cultural item visible.
4. THEMES & STORY: What is the documentary actually ABOUT? What story does it tell? What cultural, social, or personal issues does it highlight?
5. LANGUAGE DETECTION: What is the PRIMARY spoken language? (e.g., Tagalog, Kapampangan, Ilocano, English)
6. DESCRIPTION ACCURACY: Compare the "UPLOADER'S SUBMITTED DESCRIPTION" with the ACTUAL content of the video. Is the uploader's description accurate, relevant, and not blank? (Return a boolean).

CRITICAL RULES:
- DO NOT guess, hallucinate, or invent anything. ONLY report what is ACTUALLY in the video.
- The "transcriptSummary" must be written ENTIRELY in the primary spoken language detected.
- If a person's occupation is shown (e.g., fisherman, farmer, jueteng collector), EXPLICITLY name it.
- Keywords must include both English AND Filipino/local language variants (e.g., "mangingisda" AND "fisherman").
- Include scene timestamps as accurately as possible.

Respond ONLY with valid JSON (no markdown, no extra text):
{
  "detectedLanguage": "The primary spoken language",
  "isDescriptionAccurate": true or false,
  "transcriptSummary": "A rich, accurate 3-5 paragraph summary of the documentary's narration, story, and message, written IN THE DETECTED LANGUAGE. Include specific names, occupations, locations, and events mentioned.",
  "scenes": [
    {
      "timestamp": "0:00 - 1:30",
      "description": "Detailed visual and audio description of this scene",
      "objectsVisible": ["object1", "object2"],
      "peopleActivity": "What are the people doing and what is their role"
    }
  ],
  "detectedObjects": ["every significant object, animal, tool, food, location visible in the entire video"],
  "occupations": ["list every occupation/livelihood shown or mentioned: e.g., mangingisda, magsasaka, jueteng collector"],
  "locations": ["every location/place mentioned or shown"],
  "thematicMeaning": ["themes in English", "themes in Tagalog", "themes in local language"],
  "searchKeywords": ["keywords covering every topic in English, Tagalog, and local Filipino languages -- include occupations, objects, themes, character names, and locations"]
}`;

        // Step 3: Call generateContent via official SDK
        const genResp = await getAI().models.generateContent({
            model: 'gemini-3.6-flash',
            contents: [
                {
                    role: "user",
                    parts: [
                        { fileData: { mimeType: "video/mp4", fileUri: fileUri } },
                        { text: prompt }
                    ]
                }
            ],
            config: {
                temperature: 0.1,
                maxOutputTokens: 8192,
                responseMimeType: "application/json",
                thinkingConfig: { thinkingLevel: "minimal" },
                safetySettings: [
                    { category: "HARM_CATEGORY_HARASSMENT", threshold: "BLOCK_NONE" },
                    { category: "HARM_CATEGORY_HATE_SPEECH", threshold: "BLOCK_NONE" },
                    { category: "HARM_CATEGORY_SEXUALLY_EXPLICIT", threshold: "BLOCK_NONE" },
                    { category: "HARM_CATEGORY_DANGEROUS_CONTENT", threshold: "BLOCK_NONE" }
                ]
            }
        });
        console.log("Full response:", JSON.stringify(genResp, null, 2));

        let jsonText = genResp.text || "";

        if (!jsonText) {
            if (genResp.promptFeedback?.blockReason) {
                console.error("Content blocked by promptFeedback:", genResp.promptFeedback.blockReason);
                throw new Error(`Content blocked by safety filter: ${genResp.promptFeedback.blockReason}. Manual review needed.`);
            }
            const finishReason = genResp.candidates?.[0]?.finishReason;
            const safetyRatings = genResp.candidates?.[0]?.safetyRatings;
            console.error("Empty response. finishReason:", finishReason, "safety:", safetyRatings);
            throw new Error(`AI response was empty. finishReason: ${finishReason}`);
        }

        // Parse response (should be strict JSON now due to responseMimeType)
        const jsonMatch = jsonText.match(/\{[\s\S]*\}/);
        if (!jsonMatch) throw new Error("AI response did not contain valid JSON. Raw output: " + jsonText.substring(0, 100));
        const cbvrData = JSON.parse(jsonMatch[0]);

        // Build a comprehensive semantic block for vector search
        // This includes EVERYTHING so searches for any word spoken in the video will work
        const allSceneDescriptions = (cbvrData.scenes || [])
            .map(s => `[${s.timestamp}] ${s.description} People: ${s.peopleActivity || ''} Objects: ${(s.objectsVisible || []).join(', ')}`)
            .join("\n");

        const semanticBlock = `
Title: ${filmData.title || ''}
Description: ${filmData.description || ''}
Language: ${cbvrData.detectedLanguage || ''}
Full Narration Summary: ${cbvrData.transcriptSummary || ''}
Occupations/Livelihoods: ${(cbvrData.occupations || []).join(", ")}
Locations: ${(cbvrData.locations || []).join(", ")}
Themes: ${(cbvrData.thematicMeaning || []).join(", ")}
Objects Detected: ${(cbvrData.detectedObjects || []).join(", ")}
Search Keywords: ${(cbvrData.searchKeywords || []).join(", ")}
Scene-by-Scene: ${allSceneDescriptions}
        `.trim();

        console.log("Generating vector embedding for semantic search...");

        // FIX: use the shared EMBEDDING_MODEL constant, same as searchFilmsCBVR
        const embedResult = await getAI().models.embedContent({
            model: EMBEDDING_MODEL,
            contents: semanticBlock,
            config: { outputDimensionality: EMBEDDING_DIMENSION }
        });

        const embeddingVector = embedResult.embeddings[0].values;

        console.log("Updating Firestore with CBVR Data and Vector...");

        await db.collection("films").doc(filmId).update({
            cbvrData: cbvrData,
            cbvrMetadata: {
                isDescriptionAccurate: cbvrData.isDescriptionAccurate === true
            },
            embedding: FieldValue.vector(embeddingVector),
            cbvrStatus: "completed",
            cbvrError: FieldValue.delete(),
            // Also update aiSummary with the accurate summary from video analysis
            aiSummary: cbvrData.transcriptSummary || filmData.aiSummary || '',
            aiKeywords: cbvrData.searchKeywords || filmData.aiKeywords || [],
        });

        // Cleanup temp files
        try {
            await getAI().files.delete({ name: fileName });
            fs.unlinkSync(tempFilePath);
        } catch (cleanupErr) {
            console.warn("Cleanup warning:", cleanupErr.message);
        }

        console.log("CBVR Generation Complete!");
        // Everything finished (video encoded + AI analysis done) -- safe to
        // reveal this film on Watch/Search now.
        await markApprovedIfProcessing(filmId);
    } catch (error) {
        console.error(`CBVR Generation failed for film ${filmId}:`, error);
        // IMPORTANT: don't just give up here. Even if the full video analysis
        // was blocked (e.g. by a Gemini safety filter) or failed for any other
        // reason, still try to make the film searchable using only the
        // uploader's own title/description text. This keeps "AI Insight
        // Summary generation" and "search indexing" from being tied together.
        await generateFallbackEmbedding(filmId, filmData, error.message || "Unknown error");
    }
}

// Objective 3: Generate CBVR Metadata
exports.generateCBVRMetadata = onDocumentCreated(
    { document: "films/{filmId}", timeoutSeconds: 540, memory: "4GiB", secrets: [geminiApiKeySecret] },
    async (event) => {
        const filmData = event.data.data();
        const filmId = event.params.filmId;

        try {
            await processCBVR(filmId, filmData);
        } catch (error) {
            console.error("Error in generateCBVRMetadata:", error);
            await db.collection("films").doc(filmId).update({
                cbvrStatus: "failed",
                cbvrError: error.message
            });
            // Defensive: processCBVR normally never throws (it handles its
            // own errors internally via generateFallbackEmbedding), but if
            // something truly unexpected slips through, still don't leave
            // the film stuck invisible forever.
            await markApprovedIfProcessing(filmId);
        }
    }
);

// Manual retry endpoint
exports.retryCBVRMetadata = onCall(
    { timeoutSeconds: 3600, memory: "4GiB", secrets: [geminiApiKeySecret] },
    async (request) => {
        const filmId = request.data.filmId;
        if (!filmId) throw new HttpsError("invalid-argument", "Missing filmId.");

        const doc = await db.collection("films").doc(filmId).get();
        if (!doc.exists) {
            throw new HttpsError("not-found", "Film not found.");
        }

        const filmData = doc.data();

        // Mark as processing before starting
        await db.collection("films").doc(filmId).update({
            cbvrStatus: "processing",
            cbvrError: FieldValue.delete()
        });

        try {
            await processCBVR(filmId, filmData);
        } catch (error) {
            console.error("Error in retryCBVRMetadata:", error);
            await db.collection("films").doc(filmId).update({
                cbvrStatus: "failed",
                cbvrError: error.message
            });
            throw new HttpsError("internal", error.message);
        }

        // Check if processing actually succeeded
        const updatedDoc = await db.collection("films").doc(filmId).get();
        const status = updatedDoc.data().cbvrStatus;
        if (status === "failed") {
            throw new HttpsError("internal", updatedDoc.data().cbvrError || "CBVR processing failed.");
        }

        return { success: true };
    }
);

// Objective 3: Semantic Vector Search Endpoint
exports.searchFilmsCBVR = onCall({ secrets: [geminiApiKeySecret] }, async (request) => {
    const queryText = request.data.query;
    if (!queryText) throw new HttpsError("invalid-argument", "Missing query.");

    // 1. Generate embedding for the user's natural language query
    //    FIX: same EMBEDDING_MODEL constant as processCBVR/reembedAllFilms
    const embedResult = await getAI().models.embedContent({
        model: EMBEDDING_MODEL,
        contents: queryText,
        config: { outputDimensionality: EMBEDDING_DIMENSION }
    });

    const queryVector = embedResult.embeddings[0].values;

    // 2. Perform Vector Search on Firestore using findNearest
    const coll = db.collection("films");

    const vectorQuery = coll.findNearest("embedding", FieldValue.vector(queryVector), {
        limit: 10,
        distanceMeasure: "COSINE",
        // FIX: relaxed from 0.25 to 0.5. 0.25 was cutting off legitimate
        // semantic/cross-language matches (e.g. Tagalog query vs Kapampangan
        // content sits farther apart in cosine distance even when the
        // meaning matches). Tune this value based on real test results --
        // if you start seeing irrelevant matches, tighten it back down.
        distanceThreshold: 0.5,
        distanceResultField: "vectorDistance"
    });

    const snapshot = await vectorQuery.get();

    const results = [];
    snapshot.forEach(doc => {
        const data = doc.data();

        // ONLY INCLUDE APPROVED FILMS
        if (data.status === 'approved') {
            // Remove the massive vector array before sending to the client
            delete data.embedding;
            results.push({ id: doc.id, ...data });
        }
    });

    return { results };
});

// Utility: Re-generate embeddings for all completed films using the current model
// This is fast because it uses existing cbvrData without re-analyzing videos
// Run this ONCE after deploying the fix above, so existing films get
// re-embedded with the correct (matching) EMBEDDING_MODEL.
exports.reembedAllFilms = onCall(
    { timeoutSeconds: 540, memory: "1GiB", secrets: [geminiApiKeySecret] },
    async (request) => {
        const snapshot = await db.collection("films")
            .where("cbvrStatus", "==", "completed")
            .get();

        let success = 0, failed = 0;

        for (const doc of snapshot.docs) {
            const filmData = doc.data();
            const cbvrData = filmData.cbvrData;
            if (!cbvrData) continue;

            try {
                const semanticBlock = `
Title: ${filmData.title || ''}
Description: ${filmData.description || ''}
Narration: ${cbvrData.transcriptSummary || ''}
Themes: ${(cbvrData.thematicMeaning || []).join(", ")}
Objects: ${(cbvrData.detectedObjects || []).join(", ")}
Keywords: ${(cbvrData.searchKeywords || []).join(", ")}
Scenes: ${(cbvrData.scenes || []).map(s => s.description).join(" ")}
                `.trim();

                const embedResult = await getAI().models.embedContent({
                    model: EMBEDDING_MODEL,
                    contents: semanticBlock,
                    config: { outputDimensionality: EMBEDDING_DIMENSION }
                });

                await db.collection("films").doc(doc.id).update({
                    embedding: FieldValue.vector(embedResult.embeddings[0].values)
                });

                console.log(`Re-embedded: ${doc.id} (${filmData.title})`);
                success++;
            } catch (e) {
                console.error(`Failed to re-embed ${doc.id}:`, e.message);
                failed++;
            }
        }

        return { success, failed, total: snapshot.size };
    }
);
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

initializeApp();

const db = getFirestore();
// Loaded from flutter env.dart for simplicity in this project
const GEMINI_API_KEY = "REMOVED_SECRET";
const ai = new GoogleGenAI({ apiKey: GEMINI_API_KEY });

// Trigger when a film is approved by an officer
exports.notifyOnNewUpload = onDocumentUpdated(
    "films/{filmId}",
    async (event) => {
      const beforeData = event.data.before.data();
      const afterData = event.data.after.data();

      // Only notify if status changed from something else to 'approved'
      if (beforeData.status !== "approved" && afterData.status === "approved") {
        const message = {
          notification: {
            title: "New Documentary Approved! 🎬",
            body: afterData.title ?
              `"${afterData.title}" is now available to watch!` :
              "A new documentary is now available.",
          },
          topic: "new_uploads",
        };
        await getMessaging().send(message);
      }
    },
);




// Objective 3: Generate CBVR Metadata using Gemini 1.5 Pro
exports.generateCBVRMetadata = onDocumentCreated(
    { document: "films/{filmId}", timeoutSeconds: 540, memory: "1GiB" },
    async (event) => {
        const filmData = event.data.data();
        const filmId = event.params.filmId;
        
        if (!filmData.videoUrl) return;
        
        // Extract Bunny pull zone and guid from HLS URL
        // e.g. https://vz-a8c16596-0d2.b-cdn.net/f5a05b33-.../playlist.m3u8
        const urlParts = filmData.videoUrl.split("/");
        if (urlParts.length < 5) return;
        
        const pullZone = urlParts[2];
        const guid = urlParts[3];
        
        // Bunny.net generates a 480p MP4 fallback automatically (if enabled)
        const mp4Url = `https://${pullZone}/${guid}/play_480p.mp4`;
        
        // Wait for Bunny.net to finish encoding the 480p fallback (max 10 minutes)
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
            console.error("Video took too long to encode or 480p fallback is not enabled.");
            return;
        }
        
        console.log("Video is ready! Downloading to /tmp...");
        
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
        
        console.log("Uploading to Gemini File API...");
        
        let uploadedFile = await ai.files.upload({
            file: tempFilePath,
            mimeType: "video/mp4"
        });
        
        console.log(`File uploaded: ${uploadedFile.name}. Waiting for processing...`);
        
        while (uploadedFile.state === "PROCESSING") {
            await new Promise(r => setTimeout(r, 5000));
            uploadedFile = await ai.files.get({ name: uploadedFile.name });
        }
        
        if (uploadedFile.state === "FAILED") {
            throw new Error("Gemini File processing failed.");
        }
        
        console.log("Analyzing with Gemini 1.5 Pro...");
        
        const prompt = `You are an expert Content-Based Video Retrieval (CBVR) AI for a Philippine university documentary platform.
Watch this documentary film carefully.
Analyze the audio track, visual scenes, objects, and thematic meaning.
CRITICAL INSTRUCTION 1: Detect the primary spoken language in the video (e.g., Tagalog, Kapampangan, or English). You MUST write the "transcriptSummary" entirely in that detected primary language.
CRITICAL INSTRUCTION 2: You MUST generate the "searchKeywords" and "thematicMeaning" in a mix of English, Tagalog, and Kapampangan to support multilingual search.

Respond ONLY with a JSON object in the exact following schema:
{
  "transcriptSummary": "A detailed 2-paragraph summary of the spoken narration and dialogue, written IN THE PRIMARY LANGUAGE SPOKEN IN THE VIDEO.",
  "scenes": [
    { "timestamp": "0:00 - 1:30", "description": "Describe the scene visually and audibly" }
  ],
  "detectedObjects": ["object1", "object2"],
  "thematicMeaning": ["theme_english", "theme_tagalog", "theme_kapampangan"],
  "searchKeywords": ["keyword_en", "keyword_tl", "keyword_pam"]
}`;

        const result = await ai.models.generateContent({
            model: "gemini-1.5-pro",
            contents: [
                uploadedFile,
                prompt
            ],
            config: {
                responseMimeType: "application/json"
            }
        });
        
        const jsonText = result.text;
        const cbvrData = JSON.parse(jsonText);
        
        // Generate Vector Embedding for Semantic Search
        const semanticBlock = `
Title: ${filmData.title}
Description: ${filmData.description}
Narration: ${cbvrData.transcriptSummary}
Themes: ${cbvrData.thematicMeaning.join(", ")}
Objects: ${cbvrData.detectedObjects.join(", ")}
Keywords: ${cbvrData.searchKeywords.join(", ")}
Scenes: ${cbvrData.scenes.map(s => s.description).join(" ")}
        `.trim();
        
        console.log("Generating vector embedding...");
        
        const embedResult = await ai.models.embedContent({
            model: "text-embedding-004",
            contents: semanticBlock,
        });
        
        const embeddingVector = embedResult.embeddings[0].values;
        
        console.log("Updating Firestore with CBVR Data and Vector...");
        
        await db.collection("films").doc(filmId).update({
            cbvrData: cbvrData,
            embedding: FieldValue.vector(embeddingVector),
            cbvrStatus: "completed"
        });
        
        // Cleanup
        await ai.files.delete({ name: uploadedFile.name });
        fs.unlinkSync(tempFilePath);
        
        console.log("CBVR Generation Complete!");
    }
);

// Objective 3: Semantic Vector Search Endpoint
exports.searchFilmsCBVR = onCall(async (request) => {
    const queryText = request.data.query;
    if (!queryText) throw new HttpsError("invalid-argument", "Missing query.");
    
    // 1. Generate embedding for the users natural language query
    const embedResult = await ai.models.embedContent({
        model: "text-embedding-004",
        contents: queryText,
    });
    
    const queryVector = embedResult.embeddings[0].values;
    
    // 2. Perform Vector Search on Firestore using findNearest
    const coll = db.collection("films");
    
    const vectorQuery = coll.findNearest("embedding", FieldValue.vector(queryVector), {
        limit: 10,
        distanceMeasure: "COSINE"
    });
    
    const snapshot = await vectorQuery.get();
    
    const results = [];
    snapshot.forEach(doc => {
        const data = doc.data();
        // Remove the massive vector array before sending to the client
        delete data.embedding;
        results.push({ id: doc.id, ...data });
    });
    
    return { results };
});

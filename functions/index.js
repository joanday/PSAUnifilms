const {onDocumentUpdated} = require("firebase-functions/v2/firestore");
const {initializeApp} = require("firebase-admin/app");
const {getMessaging} = require("firebase-admin/messaging");

const {getFirestore} = require("firebase-admin/firestore");

initializeApp();

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



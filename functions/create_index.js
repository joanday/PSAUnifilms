const admin = require("firebase-admin");
const { FirestoreAdminClient } = require('@google-cloud/firestore').v1;

// Initialize Firebase Admin so we use the local ADC (application default credentials)
admin.initializeApp();

async function createVectorIndex() {
  const client = new FirestoreAdminClient(); 
  
  const projectId = 'my-flutter-app-e482c';
  const parent = `projects/${projectId}/databases/(default)/collectionGroups/films`;

  const request = {
    parent: parent,
    index: {
      queryScope: 'COLLECTION',
      fields: [
        {
          fieldPath: 'embedding',
          vectorConfig: {
            dimension: 768,
            flat: {}
          }
        }
      ]
    }
  };

  try {
    console.log("Creating vector index...");
    const [operation] = await client.createIndex(request);
    console.log(`Operation started: ${operation.name}`);
    console.log("Waiting for index to build... this takes a few minutes...");
    const [response] = await operation.promise();
    console.log('Index created successfully:', response);
  } catch (error) {
    console.error('Error creating index:', error);
  }
}

createVectorIndex();

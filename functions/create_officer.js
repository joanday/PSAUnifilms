const admin = require('firebase-admin');
const serviceAccount = require('../assets/service_account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const auth = admin.auth();
const db = admin.firestore();

const email = 'joanmarieday5@gmail.com';
const password = 'joan_marie15';

async function createOfficer() {
  let userRecord;
  try {
    userRecord = await auth.getUserByEmail(email);
    console.log('User already exists. Updating password...');
    userRecord = await auth.updateUser(userRecord.uid, { password });
  } catch (e) {
    if (e.code === 'auth/user-not-found') {
      console.log('Creating new user...');
      userRecord = await auth.createUser({
        email,
        password,
        displayName: 'Joan Marie',
      });
    } else {
      throw e;
    }
  }

  console.log('Setting role in Firestore...');
  await db.collection('users').doc(userRecord.uid).set({
    email,
    role: 'Officer',
    name: 'Joan Marie',
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
  }, { merge: true });

  console.log('Officer account ready! UID: ' + userRecord.uid);
}

createOfficer().then(() => process.exit(0)).catch(e => {
  console.error(e);
  process.exit(1);
});

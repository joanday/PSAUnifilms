const originalDateNow = Date.now;
Date.now = function() {
    return originalDateNow() - (15 * 60 * 60 * 1000);
};

const admin = require('firebase-admin');
const serviceAccount = require('../assets/service_account.json');

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount)
});

const payload = {
  notification: {
    title: 'Hello from Antigravity! 🚀',
    body: 'Your notification setup is working perfectly. Check your phone!'
  },
  topic: 'new_uploads'
};

admin.messaging().send(payload)
  .then((response) => {
    console.log('Successfully sent message:', response);
    process.exit(0);
  })
  .catch((error) => {
    console.log('Error sending message:', error);
    process.exit(1);
  });

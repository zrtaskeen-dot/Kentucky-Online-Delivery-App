const express = require('express');
const cors = require('cors');

// ✅ Direct Destructuring Import Karein
const { initializeApp, cert } = require('firebase-admin/app');
const { getMessaging } = require('firebase-admin/messaging');

// Service Account Key Path
const serviceAccount = require('./serviceAccountKey.json');

// Initialize Firebase Admin
initializeApp({
  credential: cert(serviceAccount)
});

const app = express();
app.use(cors());
app.use(express.json());

app.get('/', (req, res) => {
  res.send('Order Notification Backend is Running!');
});

// Notification Route
app.post('/send-notification', async (req, res) => {
  const { fcmToken, title, body } = req.body;

  if (!fcmToken) {
    return res.status(400).send({ success: false, message: 'FCM Token is required' });
  }

  const message = {
    notification: {
      title: title || 'Order Update',
      body: body || 'Your order status has been updated.',
    },
    token: fcmToken,
  };

  try {
    const response = await getMessaging().send(message);
    console.log('✅ Notification sent successfully:', response);
    res.status(200).send({ success: true, response });
  } catch (error) {
    console.error('❌ Error sending notification:', error);
    res.status(500).send({ success: false, error: error.message });
  }
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Server running on port ${PORT}`);
});
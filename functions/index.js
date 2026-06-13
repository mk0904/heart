const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const admin = require("firebase-admin");

admin.initializeApp();

const db = admin.firestore();
const messaging = admin.messaging();

exports.sendNotificationPush = onDocumentCreated(
  {
    document: "notifications/{notificationId}",
    region: "us-central1",
  },
  async (event) => {
    const snapshot = event.data;
    if (!snapshot) return;

    const notification = snapshot.data() || {};
    const notificationId = event.params.notificationId;
    const recipientIds = collectRecipientIds(notification);
    if (recipientIds.length === 0) {
      await snapshot.ref.set(
        {
          pushStatus: "skipped_no_recipients",
          pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const tokens = await getRecipientTokens(recipientIds);
    if (tokens.length === 0) {
      await snapshot.ref.set(
        {
          pushStatus: "skipped_no_tokens",
          pushCheckedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
      return;
    }

    const title = cleanText(notification.title) || titleForType(notification.type);
    const body =
      cleanText(notification.message) ||
      cleanText(notification.body) ||
      cleanText(notification.subtitle) ||
      "";
    const type = cleanText(notification.type) || "push";
    const data = stringifyData({
      id: notificationId,
      type,
      title,
      message: body,
      circularId: notification.circularId || notification.circular_id,
      eventId: notification.eventId || notification.event_id,
    });

    let successCount = 0;
    let failureCount = 0;
    for (const tokenBatch of chunk(tokens, 500)) {
      const response = await messaging.sendEachForMulticast({
        tokens: tokenBatch,
        notification: { title, body },
        data,
        android: {
          priority: "high",
          notification: {
            channelId: "heart_notifications",
            sound: "default",
            clickAction: "FLUTTER_NOTIFICATION_CLICK",
          },
        },
        apns: {
          payload: {
            aps: {
              sound: "default",
              category: "mark_read_category",
            },
          },
        },
      });
      successCount += response.successCount;
      failureCount += response.failureCount;
    }

    await snapshot.ref.set(
      {
        pushStatus: failureCount === 0 ? "sent" : "sent_with_failures",
        pushSentAt: admin.firestore.FieldValue.serverTimestamp(),
        pushSuccessCount: successCount,
        pushFailureCount: failureCount,
      },
      { merge: true },
    );
  },
);

function collectRecipientIds(notification) {
  const ids = new Set();
  const recipients = notification.recipients;
  if (Array.isArray(recipients)) {
    for (const id of recipients) {
      if (typeof id === "string" && id.trim()) ids.add(id.trim());
    }
  }
  const recipientId = notification.recipientId;
  if (typeof recipientId === "string" && recipientId.trim()) {
    ids.add(recipientId.trim());
  }
  return [...ids];
}

async function getRecipientTokens(userIds) {
  const tokens = new Set();
  for (const idBatch of chunk(userIds, 300)) {
    const refs = idBatch.map((id) => db.collection("users").doc(id));
    const docs = await db.getAll(...refs);
    for (const doc of docs) {
      if (!doc.exists) continue;
      const data = doc.data() || {};
      if (typeof data.fcmToken === "string" && data.fcmToken.trim()) {
        tokens.add(data.fcmToken.trim());
      }
      if (Array.isArray(data.fcmTokens)) {
        for (const token of data.fcmTokens) {
          if (typeof token === "string" && token.trim()) {
            tokens.add(token.trim());
          }
        }
      }
    }
  }
  return [...tokens];
}

function stringifyData(data) {
  return Object.fromEntries(
    Object.entries(data)
      .filter(([, value]) => value !== undefined && value !== null)
      .map(([key, value]) => [key, String(value)]),
  );
}

function titleForType(type) {
  switch (cleanText(type).toLowerCase()) {
    case "circular":
      return "New Circular";
    case "event":
      return "New Event";
    case "invitation":
      return "New Invitation";
    default:
      return "New Notification";
  }
}

function cleanText(value) {
  return typeof value === "string" ? value.trim() : "";
}

function chunk(items, size) {
  const chunks = [];
  for (let i = 0; i < items.length; i += size) {
    chunks.push(items.slice(i, i + size));
  }
  return chunks;
}

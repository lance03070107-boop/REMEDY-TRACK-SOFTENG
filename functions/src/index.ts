import * as crypto from 'crypto';
import * as admin from 'firebase-admin';
import { onCall, HttpsError, CallableRequest } from 'firebase-functions/v2/https';
import { onDocumentCreated } from 'firebase-functions/v2/firestore';
import { onSchedule } from 'firebase-functions/v2/scheduler';
import { defineSecret } from 'firebase-functions/params';
import { Resend } from 'resend';

// Initialize Firebase Admin SDK
if (!admin.apps.length) {
  admin.initializeApp();
}

const db = admin.firestore();

// Secrets configured via Firebase Secret Manager
const otpSecretParam = defineSecret('OTP_SECRET');
const resendApiKeyParam = defineSecret('RESEND_API_KEY');

// Challenge configuration constants
const OTP_LENGTH = 6;
const OTP_EXPIRY_MS = 10 * 60 * 1000; // 10 minutes
const RESEND_COOLDOWN_MS = 60 * 1000; // 60 seconds
const MAX_HOURLY_SENDS = 5; // Max 5 sends per hour per user
const MAX_ATTEMPTS = 5; // Max 5 wrong attempts
const LOCKOUT_DURATION_MS = 15 * 60 * 1000; // 15 minutes lockout

export type OtpPurpose = 'signup' | 'reauth' | 'delete_account' | 'change_email';

interface OtpChallengeDoc {
  purpose: OtpPurpose;
  email: string;
  salt: string;
  codeHash: string;
  expiresAt: admin.firestore.Timestamp;
  attempts: number;
  createdAt: admin.firestore.Timestamp;
  lastSentAt: admin.firestore.Timestamp;
  hourlySendTimestamps: number[];
  lockUntil?: admin.firestore.Timestamp | null;
}

function isTestOrEmulatorEnv(): boolean {
  return process.env.FUNCTIONS_EMULATOR === 'true' || process.env.NODE_ENV === 'test';
}

/**
 * Returns the active HMAC secret from Secret Manager or explicit env var.
 * Fails closed in production if OTP_SECRET is missing.
 */
function getOtpSecret(): string {
  try {
    const secretVal = otpSecretParam.value();
    if (secretVal && secretVal.trim().length > 0) return secretVal.trim();
  } catch (_) {
    // Secret not bound in local test or emulator
  }
  const envSecret = process.env.OTP_SECRET?.trim();
  if (envSecret && envSecret.length > 0) {
    return envSecret;
  }
  if (isTestOrEmulatorEnv()) {
    return 'remedy-track-emulator-otp-secret';
  }
  throw new HttpsError(
    'failed-precondition',
    'Server OTP configuration is incomplete. Please contact support.'
  );
}

/**
 * Computes a secure HMAC-SHA256 salted hash of the user ID, code, and random salt.
 */
export function hashOtpCode(uid: string, code: string, salt: string, secret?: string): string {
  const hmacKey = secret || getOtpSecret();
  return crypto
    .createHmac('sha256', hmacKey)
    .update(`${uid}:${code}:${salt}`)
    .digest('hex');
}

/**
 * Generates an email template adhering to RA 10173 notice and clean Catppuccin branding.
 */
function buildEmailTemplate(otpCode: string, purpose: OtpPurpose): { html: string; text: string } {
  let actionLabel = 'verify your account';
  if (purpose === 'delete_account') actionLabel = 'confirm account and data erasure';
  if (purpose === 'reauth') actionLabel = 're-authenticate for sensitive operations';
  if (purpose === 'change_email') actionLabel = 'confirm your new email address';

  const text = [
    `RemedyTrack Verification Code: ${otpCode}`,
    ``,
    `Use this code to ${actionLabel}.`,
    `This verification code will expire in 10 minutes.`,
    ``,
    `If you did not request this verification code, please ignore this email. Your medical and dosage data remains protected.`,
    ``,
    `RemedyTrack - Your Personal Health and Dosage Companion`,
  ].join('\n');

  const html = `
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>RemedyTrack Verification</title>
</head>
<body style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Helvetica, Arial, sans-serif; background-color: #eff1f5; margin: 0; padding: 32px 16px;">
  <div style="max-width: 480px; margin: 0 auto; background: #ffffff; border-radius: 16px; padding: 32px; box-shadow: 0 4px 16px rgba(0,0,0,0.06); border: 1px solid #dce0e8;">
    <div style="text-align: center; margin-bottom: 24px;">
      <h1 style="color: #1e66f5; font-size: 24px; font-weight: 800; margin: 0; letter-spacing: -0.5px;">RemedyTrack</h1>
      <p style="color: #6c6f85; font-size: 14px; margin-top: 4px;">Personal Health & Dosage Companion</p>
    </div>
    <div style="background-color: #f8fafc; border-radius: 12px; padding: 20px; text-align: center; border: 1px solid #e2e8f0; margin-bottom: 24px;">
      <p style="color: #4c4f69; font-size: 14px; margin: 0 0 12px 0;">Use this single-use code to ${actionLabel}:</p>
      <div style="font-size: 36px; font-weight: 800; letter-spacing: 8px; color: #1e66f5; font-family: monospace;">${otpCode}</div>
      <p style="color: #8c8fa1; font-size: 12px; margin: 12px 0 0 0;">Expires in 10 minutes • Single-use only</p>
    </div>
    <div style="font-size: 13px; line-height: 1.6; color: #5c5f77;">
      <p style="margin: 0 0 8px 0;"><strong>Security Note:</strong> RemedyTrack staff will never ask you for this code.</p>
      <p style="margin: 0;">If you didn't request this code, you can safely ignore this email. No changes will be made to your account.</p>
    </div>
    <div style="border-top: 1px solid #e6e9ef; margin-top: 24px; padding-top: 16px; text-align: center; font-size: 11px; color: #9ca0b0;">
      RemedyTrack • Compliant with Philippine Data Privacy Act (RA 10173)
    </div>
  </div>
</body>
</html>
`;

  return { html, text };
}

/**
 * Dispatches an email via Resend or logs simulated delivery for dev/test environments.
 * NEVER logs the plaintext OTP code to stdout or Cloud Logging.
 */
async function sendEmailDelivery(toEmail: string, otpCode: string, purpose: OtpPurpose): Promise<void> {
  let apiKey = '';
  try {
    apiKey = resendApiKeyParam.value();
  } catch (_) {}
  if (!apiKey) apiKey = process.env.RESEND_API_KEY || '';

  const { html, text } = buildEmailTemplate(otpCode, purpose);

  if (apiKey && apiKey !== 'mock' && apiKey !== 'test') {
    const resend = new Resend(apiKey);
    const { error } = await resend.emails.send({
      from: 'RemedyTrack <verify@remedytrack.app>',
      to: [toEmail],
      subject: 'Your RemedyTrack Verification Code',
      html,
      text,
    });
    if (error) {
      console.error('Resend delivery failed:', error.message);
      throw new HttpsError('internal', 'Unable to deliver verification email. Please try again.');
    }
  } else if (isTestOrEmulatorEnv()) {
    // Simulated delivery only permitted in local development, test, and emulator
    console.info(`[Email Service] Simulated verification delivery to ${toEmail} for purpose: ${purpose}`);
  } else {
    throw new HttpsError(
      'failed-precondition',
      'Email delivery service is not configured. Please contact support.'
    );
  }
}

// =========================================================================
// Callable Function 1: requestEmailOtp
// =========================================================================
export const requestEmailOtp = onCall(
  {
    region: 'asia-southeast1',
    secrets: [otpSecretParam, resendApiKeyParam],
    cors: true,
  },
  async (request: CallableRequest<{ purpose?: string; email?: string }>) => {
    // 1. Authentication requirement
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated to request a verification code.');
    }

    const uid = request.auth.uid;
    const rawPurpose = request.data?.purpose;
    if (rawPurpose !== undefined && typeof rawPurpose !== 'string') {
      throw new HttpsError('invalid-argument', 'Verification purpose must be a string.');
    }
    const purpose = ((rawPurpose as string | undefined) || 'signup') as OtpPurpose;

    if (!['signup', 'reauth', 'delete_account', 'change_email'].includes(purpose)) {
      throw new HttpsError('invalid-argument', 'Invalid OTP verification purpose specified.');
    }

    // Determine target recipient email
    const rawEmail = request.data?.email;
    if (rawEmail !== undefined && typeof rawEmail !== 'string') {
      throw new HttpsError('invalid-argument', 'Email address must be a string.');
    }
    let recipientEmail = rawEmail?.trim();
    if (!recipientEmail || purpose !== 'change_email') {
      recipientEmail = request.auth.token.email || recipientEmail;
    }

    if (!recipientEmail || recipientEmail.length > 120 || !recipientEmail.includes('@')) {
      throw new HttpsError('invalid-argument', 'Valid email address (120 characters or fewer) is required.');
    }

    const now = Date.now();
    const challengeRef = db.collection('otp_challenges').doc(uid);
    const challengeSnap = await challengeRef.get();

    let hourlySendTimestamps: number[] = [];

    if (challengeSnap.exists) {
      const existing = challengeSnap.data() as OtpChallengeDoc;

      // 2. Lockout check
      if (existing.lockUntil && existing.lockUntil.toMillis() > now) {
        const remainingMinutes = Math.ceil((existing.lockUntil.toMillis() - now) / 60000);
        throw new HttpsError(
          'permission-denied',
          `Too many failed attempts. Verification is locked for ${remainingMinutes} more minute(s).`
        );
      }

      // 3. 60-second Resend Cooldown
      if (existing.lastSentAt) {
        const elapsedMs = now - existing.lastSentAt.toMillis();
        if (elapsedMs < RESEND_COOLDOWN_MS) {
          const remainingSecs = Math.ceil((RESEND_COOLDOWN_MS - elapsedMs) / 1000);
          throw new HttpsError(
            'resource-exhausted',
            `Please wait ${remainingSecs} second(s) before requesting another code.`
          );
        }
      }

      // 4. Hourly Rate Limiting (max 5 sends/hour/user)
      const oneHourAgo = now - 60 * 60 * 1000;
      hourlySendTimestamps = (existing.hourlySendTimestamps || []).filter((ts) => ts > oneHourAgo);
      if (hourlySendTimestamps.length >= MAX_HOURLY_SENDS) {
        throw new HttpsError(
          'resource-exhausted',
          'Hourly rate limit exceeded. You can request a maximum of 5 verification codes per hour.'
        );
      }
    }

    // 5. Cryptographically secure 6-digit random code generation
    const rawOtpCode = crypto.randomInt(100000, 1000000).toString();
    const salt = crypto.randomBytes(16).toString('hex');
    const codeHash = hashOtpCode(uid, rawOtpCode, salt);

    // Record new send timestamp
    hourlySendTimestamps.push(now);

    const newChallenge: OtpChallengeDoc = {
      purpose,
      email: recipientEmail,
      salt,
      codeHash,
      expiresAt: admin.firestore.Timestamp.fromMillis(now + OTP_EXPIRY_MS),
      attempts: 0,
      createdAt: admin.firestore.Timestamp.fromMillis(now),
      lastSentAt: admin.firestore.Timestamp.fromMillis(now),
      hourlySendTimestamps,
      lockUntil: null,
    };

    await challengeRef.set(newChallenge);

    // 6. Deliver email (without logging raw code)
    await sendEmailDelivery(recipientEmail, rawOtpCode, purpose);

    return {
      success: true,
      message: 'Verification code sent to your registered email.',
      cooldownSeconds: 60,
      expiresInMinutes: 10,
    };
  }
);

// =========================================================================
// Callable Function 2: verifyEmailOtp
// =========================================================================
export const verifyEmailOtp = onCall(
  {
    region: 'asia-southeast1',
    secrets: [otpSecretParam],
    cors: true,
  },
  async (request: CallableRequest<{ code?: string; purpose?: string }>) => {
    // 1. Authentication check
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const uid = request.auth.uid;
    const rawCode = request.data?.code;
    const rawPurpose = request.data?.purpose;
    if (typeof rawCode !== 'string') {
      throw new HttpsError('invalid-argument', 'Please enter a valid 6-digit verification code.');
    }
    if (rawPurpose !== undefined && typeof rawPurpose !== 'string') {
      throw new HttpsError('invalid-argument', 'Verification purpose must be a string.');
    }
    const inputCode = rawCode.trim();
    const expectedPurpose = rawPurpose as OtpPurpose | undefined;

    if (!inputCode || inputCode.length !== OTP_LENGTH || !/^\d{6}$/.test(inputCode)) {
      throw new HttpsError('invalid-argument', 'Please enter a valid 6-digit verification code.');
    }

    const now = Date.now();
    const challengeRef = db.collection('otp_challenges').doc(uid);
    const challengeSnap = await challengeRef.get();

    if (!challengeSnap.exists) {
      throw new HttpsError('not-found', 'No active verification challenge found. Please request a new code.');
    }

    const challenge = challengeSnap.data() as OtpChallengeDoc;

    // 2. Lockout check
    if (challenge.lockUntil && challenge.lockUntil.toMillis() > now) {
      const remainingMinutes = Math.ceil((challenge.lockUntil.toMillis() - now) / 60000);
      throw new HttpsError(
        'permission-denied',
        `Account verification is locked due to multiple failed attempts. Try again in ${remainingMinutes} minute(s).`
      );
    }

    // 3. Expiration check
    if (challenge.expiresAt.toMillis() < now) {
      await challengeRef.delete();
      throw new HttpsError('deadline-exceeded', 'The verification code has expired. Please request a new one.');
    }

    // 4. Purpose matching
    if (expectedPurpose && challenge.purpose !== expectedPurpose) {
      throw new HttpsError('failed-precondition', 'Verification code was requested for a different action.');
    }

    // 5. Constant-time secure comparison
    const computedHash = Buffer.from(hashOtpCode(uid, inputCode, challenge.salt), 'hex');
    const storedHash = Buffer.from(challenge.codeHash, 'hex');

    const isMatch =
      computedHash.length === storedHash.length && crypto.timingSafeEqual(computedHash, storedHash);

    if (!isMatch) {
      const newAttempts = (challenge.attempts || 0) + 1;
      const remaining = MAX_ATTEMPTS - newAttempts;

      if (newAttempts >= MAX_ATTEMPTS) {
        // Enforce 15-minute lock
        await challengeRef.update({
          attempts: newAttempts,
          lockUntil: admin.firestore.Timestamp.fromMillis(now + LOCKOUT_DURATION_MS),
        });
        throw new HttpsError(
          'permission-denied',
          'Too many incorrect attempts. Verification is locked for 15 minutes.'
        );
      } else {
        await challengeRef.update({ attempts: newAttempts });
        throw new HttpsError(
          'invalid-argument',
          `Incorrect verification code. ${remaining} attempt(s) remaining.`
        );
      }
    }

    // 6. Update verification status server-side BEFORE deleting challenge
    if (challenge.purpose === 'signup' || challenge.purpose === 'change_email') {
      // Update Firestore user document first
      await db.collection('users').doc(uid).set(
        {
          emailOtpVerified: true,
          emailVerifiedAt: admin.firestore.FieldValue.serverTimestamp(),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // Safely update Firebase Auth emailVerified flag and custom claims
      // (Never spread request.auth.token into setCustomUserClaims because reserved JWT claims like 'aud'/'iss' throw!)
      try {
        const userRecord = await admin.auth().getUser(uid);
        const existingCustomClaims = userRecord.customClaims || {};
        await admin.auth().updateUser(uid, { emailVerified: true });
        await admin.auth().setCustomUserClaims(uid, {
          ...existingCustomClaims,
          emailOtpVerified: true,
        });
      } catch (claimErr) {
        console.warn('Non-fatal warning updating Auth user claims:', claimErr);
      }
    }

    // 7. Single-use: Destroy challenge after verification status is persisted
    await challengeRef.delete();

    return {
      verified: true,
      purpose: challenge.purpose,
      message: 'Email address verified successfully.',
    };
  }
);

/**
 * Callable Cloud Function: deleteUserData
 * Fulfills Philippine RA 10173 Section 16 (Right to Erasure).
 * Recursively and atomically erases all personal health and authentication records:
 * 1. users/{uid} and subcollections (emergency card) via recursiveDelete
 * 2. medications, intake_logs, inventory, appointments, caregivers, otp_challenges
 * 3. Permanently deletes the Firebase Auth record
 */
export const deleteUserData = onCall(
  {
    enforceAppCheck: false,
    region: 'asia-southeast1',
  },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated to request account deletion.');
    }

    const uid = request.auth.uid;

    try {
      // 1. Delete user doc & subcollections (e.g. emergency card)
      const userRef = db.collection('users').doc(uid);
      await db.recursiveDelete(userRef);

      // 2. Batch helper to delete matching queries in chunks <= 400
      const deleteCollectionByField = async (collectionName: string, fieldName: string) => {
        let snapshot = await db.collection(collectionName).where(fieldName, '==', uid).limit(400).get();
        while (!snapshot.empty) {
          const batch = db.batch();
          snapshot.docs.forEach((d) => batch.delete(d.ref));
          await batch.commit();
          snapshot = await db.collection(collectionName).where(fieldName, '==', uid).limit(400).get();
        }
      };

      // 3. Delete medications, intake_logs, inventory
      await deleteCollectionByField('medications', 'userId');
      await deleteCollectionByField('intake_logs', 'userId');
      await deleteCollectionByField('inventory', 'userId');

      // 3.5 Clean up caregiverIds / dependentIds array references on linked user documents
      const [patientRels, caregiverRels] = await Promise.all([
        db.collection('caregivers').where('patientId', '==', uid).get(),
        db.collection('caregivers').where('caregiverId', '==', uid).get(),
      ]);
      for (const doc of patientRels.docs) {
        const cgId = doc.data()?.caregiverId;
        if (typeof cgId === 'string' && cgId && cgId !== uid) {
          await db
            .collection('users')
            .doc(cgId)
            .update({
              dependentIds: admin.firestore.FieldValue.arrayRemove(uid),
            })
            .catch(() => {});
        }
      }
      for (const doc of caregiverRels.docs) {
        const patId = doc.data()?.patientId;
        if (typeof patId === 'string' && patId && patId !== uid) {
          await db
            .collection('users')
            .doc(patId)
            .update({
              caregiverIds: admin.firestore.FieldValue.arrayRemove(uid),
            })
            .catch(() => {});
        }
      }

      // 4. Delete caregiver relationships, invites, and alerts where user is patient or caregiver
      await deleteCollectionByField('caregivers', 'patientId');
      await deleteCollectionByField('caregivers', 'caregiverId');
      await deleteCollectionByField('caregiver_invites', 'patientId');
      await deleteCollectionByField('caregiver_alerts', 'patientId');
      await deleteCollectionByField('caregiver_alerts', 'caregiverId');

      // 5. Delete OTP challenges
      const otpRef = db.collection('otp_challenges').doc(uid);
      await otpRef.delete().catch(() => {});

      // 6. Delete Firebase Auth user
      await admin.auth().deleteUser(uid);

      return {
        success: true,
        message: 'All user data and account records have been permanently erased under RA 10173.',
      };
    } catch (error) {
      console.error(`Account deletion failure for uid ${uid}:`, error);
      throw new HttpsError('internal', 'Failed to complete complete account erasure. Please contact support.');
    }
  }
);

/**
 * Generates a random alphanumeric invite code.
 */
export function generateInviteCode(length = 6): string {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Avoid ambiguous chars 0/O, 1/I
  let result = '';
  const randomBytes = crypto.randomBytes(length);
  for (let i = 0; i < length; i++) {
    result += chars[randomBytes[i] % chars.length];
  }
  return result;
}

/**
 * Callable Cloud Function: generateCaregiverInvite
 * Creates a short-lived (24h), single-use invite code for a patient to link a caregiver.
 */
export const generateCaregiverInvite = onCall(
  {
    enforceAppCheck: false,
    region: 'asia-southeast1',
  },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const patientId = request.auth.uid;
    const rawMedIds = request.data?.allowedMedicationIds;
    if (
      rawMedIds !== undefined &&
      (!Array.isArray(rawMedIds) ||
        rawMedIds.length > 100 ||
        rawMedIds.some((id) => typeof id !== 'string' || id.trim().length === 0 || id.length > 100))
    ) {
      throw new HttpsError('invalid-argument', 'allowedMedicationIds must be an array of valid medication IDs.');
    }
    const allowedMedicationIds = Array.isArray(rawMedIds)
      ? (rawMedIds as string[]).map((id) => id.trim())
      : [];

    // Fetch patient display name
    const patientDoc = await db.collection('users').doc(patientId).get();
    const patientName = patientDoc.exists ? (patientDoc.data()?.displayName || 'Patient') : 'Patient';

    const code = generateInviteCode(6);
    const expiresAtMs = Date.now() + 24 * 60 * 60 * 1000; // 24 hours

    const existingPendingSnap = await db
      .collection('caregiver_invites')
      .where('patientId', '==', patientId)
      .where('status', '==', 'pending')
      .limit(20)
      .get();

    const batch = db.batch();
    for (const doc of existingPendingSnap.docs) {
      if (doc.id !== code) {
        batch.update(doc.ref, {
          status: 'expired',
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        });
      }
    }

    batch.set(db.collection('caregiver_invites').doc(code), {
      code,
      patientId,
      patientName,
      allowedMedicationIds,
      status: 'pending',
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(expiresAtMs),
    });

    await batch.commit();

    return {
      inviteCode: code,
      expiresAt: new Date(expiresAtMs).toISOString(),
    };
  }
);

/**
 * Safely parses a Firestore Timestamp, Date, numeric epoch ms, or ISO-8601 string.
 */
export function parseFirestoreDate(value: unknown): Date | null {
  if (!value) return null;
  if (value instanceof Date) {
    return Number.isNaN(value.getTime()) ? null : value;
  }
  if (typeof (value as { toDate?: () => Date }).toDate === 'function') {
    const parsed = (value as { toDate: () => Date }).toDate();
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  if (typeof value === 'string' || typeof value === 'number') {
    const parsed = new Date(value);
    return Number.isNaN(parsed.getTime()) ? null : parsed;
  }
  return null;
}

/**
 * Callable Cloud Function: acceptCaregiverInvite
 * Accepts an invite code, links the caregiver to the patient with explicit consent,
 * and invalidates the invite code single-use.
 */
export const acceptCaregiverInvite = onCall(
  {
    enforceAppCheck: false,
    region: 'asia-southeast1',
  },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const caregiverId = request.auth.uid;
    const rawCode = request.data?.code;
    if (!rawCode || typeof rawCode !== 'string') {
      throw new HttpsError('invalid-argument', 'Valid invite code is required.');
    }

    const code = rawCode.trim().toUpperCase();
    if (!/^[A-Z0-9]{4,12}$/.test(code)) {
      throw new HttpsError('invalid-argument', 'Invite code format is invalid.');
    }
    const inviteRef = db.collection('caregiver_invites').doc(code);
    const inviteDoc = await inviteRef.get();

    if (!inviteDoc.exists) {
      throw new HttpsError('not-found', 'Invite code is invalid or has expired.');
    }

    const inviteData = inviteDoc.data()!;
    if (inviteData.status !== 'pending') {
      throw new HttpsError('failed-precondition', 'This invite code has already been used.');
    }

    const expiresAt = parseFirestoreDate(inviteData.expiresAt);
    if (!expiresAt || Date.now() > expiresAt.getTime()) {
      await inviteRef.update({ status: 'expired' });
      throw new HttpsError('deadline-exceeded', 'This invite code has expired (24-hour limit).');
    }

    const patientId = inviteData.patientId;
    if (patientId === caregiverId) {
      throw new HttpsError('invalid-argument', 'Patients cannot add themselves as their own caregiver.');
    }

    const relationshipId = `${patientId}_${caregiverId}`;
    const caregiverRelRef = db.collection('caregivers').doc(relationshipId);
    const rawCaregiverName = typeof request.data?.caregiverName === 'string'
      ? request.data.caregiverName.trim().slice(0, 60)
      : '';
    let safeCaregiverName = rawCaregiverName;
    if (!safeCaregiverName) {
      const caregiverUserDoc = await db.collection('users').doc(caregiverId).get();
      const profileName = caregiverUserDoc.exists ? caregiverUserDoc.data()?.displayName : '';
      safeCaregiverName = typeof profileName === 'string' && profileName.trim().length > 0
        ? profileName.trim().slice(0, 60)
        : 'Caregiver';
    }
    const safePatientName = typeof inviteData.patientName === 'string' && inviteData.patientName.trim().length > 0
      ? inviteData.patientName.trim().slice(0, 60)
      : 'Patient';
    const allowedMedicationIds: string[] = Array.isArray(inviteData.allowedMedicationIds)
      ? inviteData.allowedMedicationIds.filter((id: unknown): id is string => typeof id === 'string')
      : [];

    // Atomic transaction: re-verify invite inside tx, establish relationship, update profiles, consume invite
    await db.runTransaction(async (transaction) => {
      const txInviteSnap = await transaction.get(inviteRef);
      if (!txInviteSnap.exists) {
        throw new HttpsError('not-found', 'Invite code is invalid or has expired.');
      }
      const txInvite = txInviteSnap.data()!;
      if (txInvite.status !== 'pending') {
        throw new HttpsError('failed-precondition', 'This invite code has already been used.');
      }

      transaction.set(caregiverRelRef, {
        id: relationshipId,
        patientId,
        patientName: safePatientName,
        caregiverId,
        caregiverName: safeCaregiverName,
        status: 'active',
        allowedMedicationIds,
        permissions: ['view_adherence', 'receive_alerts'],
        inviteCode: code,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });

      // Update patient profile
      transaction.set(
        db.collection('users').doc(patientId),
        {
          caregiverIds: admin.firestore.FieldValue.arrayUnion(caregiverId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // Update caregiver profile
      transaction.set(
        db.collection('users').doc(caregiverId),
        {
          dependentIds: admin.firestore.FieldValue.arrayUnion(patientId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      // Mark invite consumed (populate both used* and accepted* for rules + legacy compatibility)
      transaction.update(inviteRef, {
        status: 'accepted',
        usedBy: caregiverId,
        usedAt: admin.firestore.FieldValue.serverTimestamp(),
        acceptedBy: caregiverId,
        acceptedAt: admin.firestore.FieldValue.serverTimestamp(),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    });

    return {
      success: true,
      patientId,
      patientName: safePatientName,
      caregiverName: safeCaregiverName,
      allowedMedicationIds,
      message: `Successfully linked as caregiver for ${safePatientName}.`,
    };
  }
);

/**
 * Callable Cloud Function: revokeCaregiverAccess
 * Allows either the patient or the caregiver to revoke the link at any time.
 */
export const revokeCaregiverAccess = onCall(
  {
    enforceAppCheck: false,
    region: 'asia-southeast1',
  },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const uid = request.auth.uid;
    const { patientId, caregiverId } = request.data || {};

    if (
      typeof patientId !== 'string' ||
      typeof caregiverId !== 'string' ||
      patientId.trim().length === 0 ||
      caregiverId.trim().length === 0 ||
      patientId.length > 128 ||
      caregiverId.length > 128
    ) {
      throw new HttpsError('invalid-argument', 'Valid patientId and caregiverId are required.');
    }

    if (uid !== patientId && uid !== caregiverId) {
      throw new HttpsError('permission-denied', 'Only the linked patient or caregiver can revoke this relationship.');
    }

    const relationshipId = `${patientId}_${caregiverId}`;
    const relRef = db.collection('caregivers').doc(relationshipId);
    const relSnap = await relRef.get();
    if (!relSnap.exists) {
      throw new HttpsError('not-found', 'Caregiver relationship not found.');
    }

    await db.runTransaction(async (transaction) => {
      transaction.update(relRef, {
        status: 'revoked',
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
        revokedBy: uid,
      });

      transaction.set(
        db.collection('users').doc(patientId),
        {
          caregiverIds: admin.firestore.FieldValue.arrayRemove(caregiverId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );

      transaction.set(
        db.collection('users').doc(caregiverId),
        {
          dependentIds: admin.firestore.FieldValue.arrayRemove(patientId),
          updatedAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true }
      );
    });

    return { success: true, message: 'Caregiver relationship successfully revoked.' };
  }
);

/**
 * Helper to check if current time falls within caregiver's quiet hours (e.g. 22:00 to 07:00).
 * When [timezoneOffsetMinutes] is supplied (e.g. 480 for Asia/Manila UTC+8),
 * evaluates wall-clock time in that offset rather than the host container's timezone.
 */
export function isWithinQuietHours(
  now: Date,
  quietStart?: string,
  quietEnd?: string,
  timezoneOffsetMinutes?: number
): boolean {
  if (!quietStart || !quietEnd) return false;
  const [startH, startM] = quietStart.split(':').map(Number);
  const [endH, endM] = quietEnd.split(':').map(Number);
  if (
    !Number.isFinite(startH) ||
    !Number.isFinite(startM) ||
    !Number.isFinite(endH) ||
    !Number.isFinite(endM)
  ) {
    return false;
  }

  let curMinutes: number;
  if (typeof timezoneOffsetMinutes === 'number' && Number.isFinite(timezoneOffsetMinutes)) {
    const shifted = new Date(now.getTime() + timezoneOffsetMinutes * 60 * 1000);
    curMinutes = shifted.getUTCHours() * 60 + shifted.getUTCMinutes();
  } else {
    curMinutes = now.getHours() * 60 + now.getMinutes();
  }

  const startMinutes = startH * 60 + startM;
  const endMinutes = endH * 60 + endM;

  if (startMinutes > endMinutes) {
    // Crosses midnight, e.g. 22:00 (1320) to 07:00 (420)
    return curMinutes >= startMinutes || curMinutes < endMinutes;
  }
  return curMinutes >= startMinutes && curMinutes < endMinutes;
}

const DEFAULT_PH_TZ_OFFSET_MINUTES = 480; // Asia/Manila UTC+8

function collectUserFcmTokens(userData: admin.firestore.DocumentData | undefined, extraToken?: string): string[] {
  const tokens: string[] = [];
  if (extraToken && typeof extraToken === 'string' && extraToken.trim().length > 0) {
    tokens.push(extraToken.trim());
  }
  if (userData?.fcmToken && typeof userData.fcmToken === 'string' && userData.fcmToken.trim().length > 0) {
    tokens.push(userData.fcmToken.trim());
  }
  if (Array.isArray(userData?.fcmTokens)) {
    for (const token of userData.fcmTokens) {
      if (typeof token === 'string' && token.trim().length > 0) {
        tokens.push(token.trim());
      }
    }
  }
  return [...new Set(tokens)];
}

async function cleanupInvalidFcmTokens(
  userRef: admin.firestore.DocumentReference,
  userData: admin.firestore.DocumentData | undefined,
  tokens: string[],
  response: admin.messaging.BatchResponse
): Promise<void> {
  const tokensToRemove: string[] = [];
  response.responses.forEach((resp, idx) => {
    if (!resp.success) {
      const code = resp.error?.code;
      if (
        code === 'messaging/registration-token-not-registered' ||
        code === 'messaging/invalid-registration-token' ||
        code === 'messaging/invalid-argument'
      ) {
        tokensToRemove.push(tokens[idx]);
      }
    }
  });

  if (tokensToRemove.length > 0) {
    await userRef.update({
      fcmTokens: admin.firestore.FieldValue.arrayRemove(...tokensToRemove),
      ...(tokensToRemove.includes(userData?.fcmToken) ? { fcmToken: admin.firestore.FieldValue.delete() } : {}),
    });
  }
}

/**
 * Dispatches FCM alerts for unconfirmed doses past escalation window (default 15 mins).
 * Respects quiet hours, patient privacy preferences (no medication name by default),
 * and automatically purges dead/invalid tokens.
 */
export const checkMissedDosesAndAlertCaregivers = onCall(
  {
    enforceAppCheck: false,
    region: 'asia-southeast1',
  },
  async (request: CallableRequest) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const callerUid = request.auth.uid;
    const now = new Date();
    const escalationThresholdMs = 15 * 60 * 1000; // 15 minutes
    const cutoffIso = new Date(now.getTime() - escalationThresholdMs).toISOString();

    // Scope strictly to active relationships where the caller is the patient or caregiver
    const [asCaregiverSnap, asPatientSnap] = await Promise.all([
      db
        .collection('caregivers')
        .where('caregiverId', '==', callerUid)
        .where('status', '==', 'active')
        .get(),
      db
        .collection('caregivers')
        .where('patientId', '==', callerUid)
        .where('status', '==', 'active')
        .get(),
    ]);

    const relDocsById = new Map<string, admin.firestore.QueryDocumentSnapshot>();
    for (const d of asCaregiverSnap.docs) relDocsById.set(d.id, d);
    for (const d of asPatientSnap.docs) relDocsById.set(d.id, d);

    if (relDocsById.size === 0) {
      return { alertsSent: 0, message: 'No active caregiver relationships found.' };
    }

    let alertsSent = 0;

    for (const relDoc of relDocsById.values()) {
      const rel = relDoc.data();
      const patientId = rel.patientId;
      const caregiverId = rel.caregiverId;
      const allowedMedicationIds: string[] = rel.allowedMedicationIds || [];

      // Check caregiver profile for notification settings, quiet hours, and tokens
      const caregiverUserDoc = await db.collection('users').doc(caregiverId).get();
      if (!caregiverUserDoc.exists) continue;
      const caregiverData = caregiverUserDoc.data()!;
      if (caregiverData.caregiverNotificationEnabled === false) continue;

      const tzOffset =
        typeof caregiverData.timezoneOffsetMinutes === 'number'
          ? caregiverData.timezoneOffsetMinutes
          : DEFAULT_PH_TZ_OFFSET_MINUTES;
      if (isWithinQuietHours(now, caregiverData.quietHoursStart, caregiverData.quietHoursEnd, tzOffset)) {
        continue; // Suppress during caregiver quiet hours
      }

      const uniqueTokens = collectUserFcmTokens(caregiverData);
      if (uniqueTokens.length === 0) continue;

      // Check patient's active medications
      const medSnap = await db
        .collection('medications')
        .where('userId', '==', patientId)
        .where('isActive', '==', true)
        .get();

      for (const medDoc of medSnap.docs) {
        const med = medDoc.data();
        if (allowedMedicationIds.length > 0 && !allowedMedicationIds.includes(medDoc.id)) {
          continue; // Medication not shared with caregiver
        }

        // IntakeLog stores scheduledTime as UTC ISO-8601 string
        const logSnap = await db
          .collection('intake_logs')
          .where('userId', '==', patientId)
          .where('medicationId', '==', medDoc.id)
          .where('scheduledTime', '<=', cutoffIso)
          .orderBy('scheduledTime', 'desc')
          .limit(5)
          .get();

        for (const logDoc of logSnap.docs) {
          const log = logDoc.data();
          if (log.isPrn || log.status === 'taken' || log.status === 'late' || log.status === 'skipped' || log.caregiverAlertSent) {
            continue;
          }

          // Build privacy-conscious payload (NO medication name by default under RA 10173)
          const shareMedName = caregiverData.shareMedicationNamesWithCaregivers === true;
          const patientName = rel.patientName || 'Your patient';
          const notificationTitle = 'RemedyTrack Dosage Alert';
          const notificationBody = shareMedName
            ? `${patientName} has an unconfirmed dose of ${med.name}.`
            : `${patientName} has not confirmed a scheduled dose.`;

          const response = await admin.messaging().sendEachForMulticast({
            tokens: uniqueTokens,
            notification: {
              title: notificationTitle,
              body: notificationBody,
            },
            data: {
              patientId: String(patientId),
              logId: logDoc.id,
              type: 'MISSED_DOSE_ESCALATION',
            },
          });

          await logDoc.ref.update({
            status: 'missed',
            caregiverAlertSent: true,
            alertSentAt: admin.firestore.FieldValue.serverTimestamp(),
          });
          alertsSent += response.successCount;

          await cleanupInvalidFcmTokens(caregiverUserDoc.ref, caregiverData, uniqueTokens, response);
        }
      }
    }

    return {
      alertsSent,
      timestamp: now.toISOString(),
      message: `Processed missed dose alerts. Sent ${alertsSent} notifications.`,
    };
  }
);

/**
 * Firestore Trigger: onCaregiverAlertCreated
 * Dispatches queued caregiver alert documents created by mobile clients when an escalation triggers.
 */
export const onCaregiverAlertCreated = onDocumentCreated(
  {
    document: 'caregiver_alerts/{alertId}',
    region: 'asia-southeast1',
  },
  async (event) => {
    const snap = event.data;
    if (!snap) return;
    const alert = snap.data();
    if (!alert || alert.status !== 'pending') return;

    const patientId = typeof alert.patientId === 'string' ? alert.patientId : '';
    const caregiverId = typeof alert.caregiverId === 'string' ? alert.caregiverId : '';
    if (!patientId || !caregiverId) {
      await snap.ref.update({ status: 'skipped', reason: 'missing_participants' });
      return;
    }

    const relSnap = await db.collection('caregivers').doc(`${patientId}_${caregiverId}`).get();
    if (!relSnap.exists || relSnap.data()?.status !== 'active') {
      await snap.ref.update({ status: 'skipped', reason: 'inactive_relationship' });
      return;
    }

    const cgUserDoc = await db.collection('users').doc(caregiverId).get();
    const cgData = cgUserDoc.exists ? cgUserDoc.data() : undefined;
    if (cgData?.caregiverNotificationEnabled === false) {
      await snap.ref.update({ status: 'suppressed', reason: 'notifications_disabled' });
      return;
    }

    const now = new Date();
    const tzOffset =
      typeof cgData?.timezoneOffsetMinutes === 'number'
        ? cgData.timezoneOffsetMinutes
        : DEFAULT_PH_TZ_OFFSET_MINUTES;
    if (isWithinQuietHours(now, cgData?.quietHoursStart, cgData?.quietHoursEnd, tzOffset)) {
      await snap.ref.update({ status: 'suppressed', reason: 'quiet_hours' });
      return;
    }

    const tokens = collectUserFcmTokens(
      cgData,
      typeof alert.caregiverToken === 'string' ? alert.caregiverToken : undefined
    );
    if (tokens.length === 0) {
      await snap.ref.update({ status: 'skipped', reason: 'no_tokens' });
      return;
    }

    const shareMedName = cgData?.shareMedicationNamesWithCaregivers === true;
    const patientName = (typeof alert.dependentName === 'string' && alert.dependentName.trim())
      ? alert.dependentName.trim()
      : relSnap.data()?.patientName || 'Your patient';
    const medName = typeof alert.medicationName === 'string' ? alert.medicationName.trim() : '';
    const body = shareMedName && medName
      ? `${patientName} missed a scheduled dose of ${medName}.`
      : `${patientName} has an unconfirmed medication dose past due. Please check in.`;

    const response = await admin.messaging().sendEachForMulticast({
      tokens,
      notification: {
        title: 'Missed Dose Alert',
        body,
      },
      data: {
        type: 'MISSED_DOSE_ALERT',
        patientId,
        alertId: snap.id,
      },
    });

    if (cgUserDoc.exists) {
      await cleanupInvalidFcmTokens(cgUserDoc.ref, cgData, tokens, response);
    }

    await snap.ref.update({
      status: response.successCount > 0 ? 'sent' : 'failed',
      sentCount: response.successCount,
      processedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
  }
);

/**
 * Scheduled Cloud Function: scheduledMissedDoseReconciliation
 * Runs periodically every 15 minutes in Philippine Standard Time (UTC+8).
 * Scans for unacknowledged doses >60 minutes past schedule, marks them as 'missed',
 * and alerts linked caregivers while honoring notification settings & quiet hours.
 */
/**
 * Evaluates whether a medication schedule is active on a given local calendar date (UTC-anchored).
 * Mirrors lib/core/scheduling/schedule_expander.dart for all 5 frequencies.
 */
function isScheduledOnLocalDay(
  schedule: Record<string, unknown>,
  localDayUtc: Date,
  tzShiftMs: number
): boolean {
  const startDate = parseFirestoreDate(schedule.startDate);
  const endDate = parseFirestoreDate(schedule.endDate);

  const dayMidnightMs = localDayUtc.getTime();
  if (startDate) {
    const localStart = new Date(startDate.getTime() + tzShiftMs);
    const startMidnightMs = Date.UTC(
      localStart.getUTCFullYear(),
      localStart.getUTCMonth(),
      localStart.getUTCDate()
    );
    if (dayMidnightMs < startMidnightMs) return false;
  }
  if (endDate) {
    const localEnd = new Date(endDate.getTime() + tzShiftMs);
    const endMidnightMs = Date.UTC(
      localEnd.getUTCFullYear(),
      localEnd.getUTCMonth(),
      localEnd.getUTCDate()
    );
    if (dayMidnightMs > endMidnightMs) return false;
  }

  const frequency = typeof schedule.frequency === 'string' ? schedule.frequency : 'daily';
  if (frequency === 'daily' || frequency === 'everyXHours') {
    return true;
  }
  if (frequency === 'specificWeekdays') {
    const isoWeekday = localDayUtc.getUTCDay() === 0 ? 7 : localDayUtc.getUTCDay();
    return Array.isArray(schedule.weekdays) && schedule.weekdays.includes(isoWeekday);
  }
  if (frequency === 'everyXDays') {
    const interval = Math.max(1, Number(schedule.intervalValue) || 1);
    if (!startDate) return true;
    const localStart = new Date(startDate.getTime() + tzShiftMs);
    const startMidnightMs = Date.UTC(
      localStart.getUTCFullYear(),
      localStart.getUTCMonth(),
      localStart.getUTCDate()
    );
    const diffDays = Math.floor((dayMidnightMs - startMidnightMs) / (24 * 60 * 60 * 1000));
    return diffDays >= 0 && diffDays % interval === 0;
  }
  if (frequency === 'cycleBased') {
    const activeDays = Math.max(1, Number(schedule.cycleActiveDays) || 21);
    const restDays = Math.max(0, Number(schedule.cycleRestDays) || 7);
    const totalCycle = activeDays + restDays;
    if (!startDate || totalCycle <= 0) return true;
    const localStart = new Date(startDate.getTime() + tzShiftMs);
    const startMidnightMs = Date.UTC(
      localStart.getUTCFullYear(),
      localStart.getUTCMonth(),
      localStart.getUTCDate()
    );
    const diffDays = Math.floor((dayMidnightMs - startMidnightMs) / (24 * 60 * 60 * 1000));
    if (diffDays < 0) return false;
    return diffDays % totalCycle < activeDays;
  }
  return true;
}

export const scheduledMissedDoseReconciliation = onSchedule(
  {
    schedule: 'every 15 minutes',
    region: 'asia-southeast1',
    timeZone: 'Asia/Manila',
  },
  async () => {
    console.log('[Scheduler] Executing scheduled missed dose reconciliation pass...');
    const now = new Date();
    const cutoffIso = new Date(now.getTime() - 60 * 60 * 1000).toISOString();

    const pendingLogsSnap = await db
      .collection('intake_logs')
      .where('status', 'in', ['pending', 'snoozed'])
      .where('scheduledTime', '<=', cutoffIso)
      .limit(200)
      .get();

    // Synthesize overdue scheduled occurrences for active medications when the patient's
    // phone is offline or powered off. Paginates across ALL active medications, uses each
    // user's timezoneOffsetMinutes, and generates deterministic epoch-MINUTE IDs identical
    // to DoseStateMachine.generateLogId on the client.
    const lookbackStartMs = now.getTime() - 24 * 60 * 60 * 1000;
    const cutoffMs = now.getTime() - 60 * 60 * 1000;
    const userTzCache = new Map<string, number>();

    try {
      const PAGE_SIZE = 200;
      let lastDoc: admin.firestore.QueryDocumentSnapshot | null = null;
      let hasMore = true;

      while (hasMore) {
        let medQuery = db
          .collection('medications')
          .where('isActive', '==', true)
          .orderBy(admin.firestore.FieldPath.documentId())
          .limit(PAGE_SIZE);
        if (lastDoc) {
          medQuery = medQuery.startAfter(lastDoc);
        }

        const activeMedsSnap = await medQuery.get();
        if (activeMedsSnap.empty) {
          break;
        }
        lastDoc = activeMedsSnap.docs[activeMedsSnap.docs.length - 1];
        hasMore = activeMedsSnap.size === PAGE_SIZE;

        for (const medDoc of activeMedsSnap.docs) {
          const med = medDoc.data();
          if (!med || med.isPrn || !med.isActive || !med.schedule || !med.userId) continue;
          const schedule = med.schedule as Record<string, unknown>;
          const rawTimes: string[] = Array.isArray(schedule.timesOfDay) ? schedule.timesOfDay : [];
          let effectiveTimes = rawTimes;
          if (schedule.frequency === 'everyXHours' && rawTimes.length <= 1) {
            const anchorStr = rawTimes.length === 1 ? rawTimes[0] : '08:00';
            const parts = anchorStr.split(':').map(Number);
            const anchorH = Number.isFinite(parts[0]) ? parts[0] : 8;
            const anchorM = Number.isFinite(parts[1]) ? parts[1] : 0;
            const interval = Math.max(1, Math.min(24, Number(schedule.intervalValue) || 4));
            const anchorMins = anchorH * 60 + anchorM;
            const generated = new Set<string>();
            for (let step = 0; step * interval < 24; step++) {
              const totalMins = (anchorMins + step * interval * 60) % 1440;
              const hh = String(Math.floor(totalMins / 60)).padStart(2, '0');
              const mm = String(totalMins % 60).padStart(2, '0');
              generated.add(`${hh}:${mm}`);
            }
            effectiveTimes = Array.from(generated).sort();
          }

          let tzOffsetMinutes = userTzCache.get(med.userId);
          if (tzOffsetMinutes === undefined) {
            const userDoc = await db.collection('users').doc(med.userId).get();
            const rawOffset = userDoc.data()?.timezoneOffsetMinutes;
            tzOffsetMinutes =
              typeof rawOffset === 'number' && rawOffset >= -720 && rawOffset <= 840
                ? rawOffset
                : DEFAULT_PH_TZ_OFFSET_MINUTES;
            userTzCache.set(med.userId, tzOffsetMinutes);
          }

          const createdAtDate = parseFirestoreDate(med.createdAt);
          const scheduleUpdatedAtDate = parseFirestoreDate(schedule.updatedAt);
          const effectiveAnchorMs =
            scheduleUpdatedAtDate && (!createdAtDate || scheduleUpdatedAtDate.getTime() > createdAtDate.getTime())
              ? scheduleUpdatedAtDate.getTime()
              : createdAtDate?.getTime();
          const endDate = parseFirestoreDate(schedule.endDate);

          const tzShiftMs = tzOffsetMinutes * 60 * 1000;
          const localNow = new Date(now.getTime() + tzShiftMs);

          for (let dayDelta = -1; dayDelta <= 0; dayDelta++) {
            const localDay = new Date(
              Date.UTC(localNow.getUTCFullYear(), localNow.getUTCMonth(), localNow.getUTCDate() + dayDelta)
            );
            if (!isScheduledOnLocalDay(schedule, localDay, tzShiftMs)) {
              continue;
            }

            for (const tStr of effectiveTimes) {
              if (typeof tStr !== 'string') continue;
              const [hh, mm] = tStr.split(':').map(Number);
              if (!Number.isFinite(hh) || !Number.isFinite(mm)) continue;
              const occUtcMs =
                Date.UTC(localDay.getUTCFullYear(), localDay.getUTCMonth(), localDay.getUTCDate(), hh, mm) -
                tzShiftMs;
              if (occUtcMs < lookbackStartMs || occUtcMs > cutoffMs) continue;
              if (effectiveAnchorMs && occUtcMs < effectiveAnchorMs) continue;
              if (endDate && occUtcMs > endDate.getTime()) continue;

              // Match client deterministic ID format: ${medicationId}_${epochMinutes}
              const occEpochMinutes = Math.floor(occUtcMs / 60000);
              const logId = `${medDoc.id}_${occEpochMinutes}`;
              const schedIso = new Date(occUtcMs).toISOString();

              const logRef = db.collection('intake_logs').doc(logId);
              const existingSnap = await logRef.get();
              if (existingSnap.exists) continue;

              // Guard against any existing log (e.g., legacy ms-keyed or differently keyed) for this exact slot
              const existingBySlotSnap = await db
                .collection('intake_logs')
                .where('userId', '==', med.userId)
                .where('medicationId', '==', medDoc.id)
                .where('scheduledTime', '==', schedIso)
                .limit(1)
                .get();
              if (!existingBySlotSnap.empty) continue;

              await logRef.set({
                id: logId,
                userId: med.userId,
                medicationId: medDoc.id,
                medicationName: med.name || 'Medication',
                doseAmount: typeof med.doseAmount === 'number' ? med.doseAmount : 1,
                scheduledTime: schedIso,
                recordedTime: now.toISOString(),
                status: 'pending',
                snoozeCount: 0,
                isPrn: false,
              });
            }
          }
        }
      }
    } catch (synthErr) {
      console.warn('[Scheduler] Schedule synthesis notice:', synthErr);
    }

    const refreshedPendingSnap =
      pendingLogsSnap.empty
        ? await db
            .collection('intake_logs')
            .where('status', 'in', ['pending', 'snoozed'])
            .where('scheduledTime', '<=', cutoffIso)
            .limit(200)
            .get()
        : pendingLogsSnap;

    if (refreshedPendingSnap.empty) {
      console.log('[Scheduler] No unacknowledged overdue doses found.');
      return;
    }

    const batch = db.batch();
    for (const doc of refreshedPendingSnap.docs) {
      const log = doc.data();
      const patientId = log.userId;
      let alertSent = Boolean(log.caregiverAlertSent);

      if (patientId && !alertSent && !log.isPrn) {
        try {
          const caregiversSnap = await db
            .collection('caregivers')
            .where('patientId', '==', patientId)
            .where('status', '==', 'active')
            .get();

          if (!caregiversSnap.empty) {
            const patientDoc = await db.collection('users').doc(patientId).get();
            const patientData = patientDoc.data();
            const patientName = patientData?.displayName || patientData?.name || 'Your patient';

            for (const cgDoc of caregiversSnap.docs) {
              const rel = cgDoc.data();
              const cgUserId = rel.caregiverId;
              if (!cgUserId) continue;

              const allowedIds: string[] = Array.isArray(rel.allowedMedicationIds)
                ? rel.allowedMedicationIds
                : [];
              if (allowedIds.length > 0 && log.medicationId && !allowedIds.includes(log.medicationId)) {
                continue;
              }

              const cgUserDoc = await db.collection('users').doc(cgUserId).get();
              if (!cgUserDoc.exists) continue;
              const cgData = cgUserDoc.data();
              if (cgData?.caregiverNotificationEnabled === false) continue;

              const tzOffset =
                typeof cgData?.timezoneOffsetMinutes === 'number'
                  ? cgData.timezoneOffsetMinutes
                  : DEFAULT_PH_TZ_OFFSET_MINUTES;
              if (isWithinQuietHours(now, cgData?.quietHoursStart, cgData?.quietHoursEnd, tzOffset)) {
                continue;
              }

              const tokens = collectUserFcmTokens(cgData);
              if (tokens.length === 0) continue;

              const shareMedName = cgData?.shareMedicationNamesWithCaregivers === true;
              const medLabel = typeof log.medicationName === 'string' ? log.medicationName : '';
              const body = shareMedName && medLabel
                ? `${patientName} missed a scheduled dose of ${medLabel} for over 1 hour. Please check in.`
                : `${patientName} missed a scheduled dose for over 1 hour. Please check in.`;

              const response = await admin.messaging().sendEachForMulticast({
                tokens,
                notification: {
                  title: 'Missed Dose Alert',
                  body,
                },
                data: {
                  type: 'MISSED_DOSE_ALERT',
                  patientId: String(patientId),
                  logId: doc.id,
                },
              });

              await cleanupInvalidFcmTokens(cgUserDoc.ref, cgData, tokens, response);
              if (response.successCount > 0) {
                alertSent = true;
              }
            }
          }
        } catch (err) {
          console.error(`[Scheduler] Failed sending caregiver alert for log ${doc.id}:`, err);
        }
      }

      batch.update(doc.ref, {
        status: 'missed',
        reconciledAt: admin.firestore.FieldValue.serverTimestamp(),
        reconciledBy: 'server_scheduler',
        ...(alertSent && !log.caregiverAlertSent
          ? {
              caregiverAlertSent: true,
              alertSentAt: admin.firestore.FieldValue.serverTimestamp(),
            }
          : {}),
      });
    }

    await batch.commit();
    console.log(`[Scheduler] Successfully reconciled ${refreshedPendingSnap.size} doses to 'missed'.`);
  }
);

/**
 * Callable Cloud Function: cleanupDuplicateMissedDoseLogs
 * One-time / on-demand cleanup for the signed-in user that deletes legacy server-synthesized
 * duplicate intake_logs (reconciledBy === 'server_scheduler' or status missed/pending) whenever
 * an authoritative client log (status taken/late/skipped) exists for the same medicationId +
 * scheduledTime minute, and removes any false caregiver_alerts linked to those duplicates.
 */
export const cleanupDuplicateMissedDoseLogs = onCall(
  {
    region: 'asia-southeast1',
    cors: true,
  },
  async (request: CallableRequest<Record<string, never>>) => {
    if (!request.auth) {
      throw new HttpsError('unauthenticated', 'User must be authenticated.');
    }

    const uid = request.auth.uid;
    const logsSnap = await db
      .collection('intake_logs')
      .where('userId', '==', uid)
      .get();

    const authoritativeSlots = new Set<string>();
    for (const doc of logsSnap.docs) {
      const data = doc.data();
      if (data.isPrn) continue;
      if (data.status === 'taken' || data.status === 'late' || data.status === 'skipped') {
        const sched = parseFirestoreDate(data.scheduledTime);
        if (sched && data.medicationId) {
          const minuteKey = `${data.medicationId}_${Math.floor(sched.getTime() / 60000)}`;
          authoritativeSlots.add(minuteKey);
        }
      }
    }

    const duplicateLogRefs: admin.firestore.DocumentReference[] = [];
    const duplicateMedSchedPairs: Array<{ medicationName: string; scheduledTime: string }> = [];

    for (const doc of logsSnap.docs) {
      const data = doc.data();
      if (data.isPrn) continue;
      const isCandidateDup =
        data.reconciledBy === 'server_scheduler' ||
        data.status === 'missed' ||
        data.status === 'pending';
      if (!isCandidateDup) continue;

      const sched = parseFirestoreDate(data.scheduledTime);
      if (!sched || !data.medicationId) continue;
      const minuteKey = `${data.medicationId}_${Math.floor(sched.getTime() / 60000)}`;
      if (authoritativeSlots.has(minuteKey)) {
        duplicateLogRefs.push(doc.ref);
        if (typeof data.medicationName === 'string' && typeof data.scheduledTime === 'string') {
          duplicateMedSchedPairs.push({
            medicationName: data.medicationName,
            scheduledTime: data.scheduledTime,
          });
        }
      }
    }

    let deletedLogs = 0;
    for (let i = 0; i < duplicateLogRefs.length; i += 400) {
      const chunk = duplicateLogRefs.slice(i, i + 400);
      const batch = db.batch();
      for (const ref of chunk) {
        batch.delete(ref);
      }
      await batch.commit();
      deletedLogs += chunk.length;
    }

    let deletedAlerts = 0;
    if (duplicateMedSchedPairs.length > 0) {
      const alertsSnap = await db
        .collection('caregiver_alerts')
        .where('patientId', '==', uid)
        .get();
      const alertRefsToDelete: admin.firestore.DocumentReference[] = [];
      for (const alertDoc of alertsSnap.docs) {
        const alert = alertDoc.data();
        const matchesDup = duplicateMedSchedPairs.some(
          (p) =>
            p.medicationName === alert.medicationName &&
            p.scheduledTime === alert.scheduledTime
        );
        if (matchesDup) {
          alertRefsToDelete.push(alertDoc.ref);
        }
      }
      for (let i = 0; i < alertRefsToDelete.length; i += 400) {
        const chunk = alertRefsToDelete.slice(i, i + 400);
        const batch = db.batch();
        for (const ref of chunk) {
          batch.delete(ref);
        }
        await batch.commit();
        deletedAlerts += chunk.length;
      }
    }

    return {
      deletedLogs,
      deletedAlerts,
    };
  }
);




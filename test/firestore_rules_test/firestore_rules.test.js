const {
  initializeTestEnvironment,
  assertFails,
  assertSucceeds,
} = require("@firebase/rules-unit-testing");
const firebase = require("firebase/compat/app");
require("firebase/compat/firestore");
const assert = require("assert");
const fs = require("fs");
const path = require("path");

const { Timestamp } = firebase.firestore;

const PROJECT_ID = "remedy-track-test";

describe("RemedyTrack Cloud Firestore Security Rules Test Suite", () => {
  let testEnv;

  before(async () => {
    const rulesPath = path.resolve(__dirname, "../../firestore.rules");
    const rulesContent = fs.readFileSync(rulesPath, "utf8");

    testEnv = await initializeTestEnvironment({
      projectId: PROJECT_ID,
      firestore: {
        rules: rulesContent,
        host: process.env.FIRESTORE_EMULATOR_HOST ? process.env.FIRESTORE_EMULATOR_HOST.split(":")[0] : "127.0.0.1",
        port: process.env.FIRESTORE_EMULATOR_HOST ? parseInt(process.env.FIRESTORE_EMULATOR_HOST.split(":")[1], 10) : 8080,
      },
    });
  });

  after(async () => {
    if (testEnv) {
      await testEnv.cleanup();
    }
  });

  beforeEach(async () => {
    if (testEnv) {
      await testEnv.clearFirestore();
    }
  });

  // =========================================================================
  // 1. Authenticated User - Own Data Access (Happy Paths)
  // =========================================================================
  describe("1. Authenticated User - Own Data Access", () => {
    it("should allow a user to create, read, update, and delete their own profile", async () => {
      const alice = testEnv.authenticatedContext("alice");
      const userRef = alice.firestore().doc("users/alice");

      // Create
      await assertSucceeds(
        userRef.set({
          id: "alice",
          email: "alice@example.com",
          displayName: "Alice Reyes",
          createdAt: new Date().toISOString(),
          isCaregiver: false,
          dependentIds: [],
        })
      );

      // Read
      await assertSucceeds(userRef.get());

      // Update
      await assertSucceeds(
        userRef.update({
          displayName: "Alice R. Updated",
        })
      );

      // Delete (Right to Erasure under RA 10173)
      await assertSucceeds(userRef.delete());
    });

    it("should allow a user to manage their own emergency card", async () => {
      const alice = testEnv.authenticatedContext("alice");
      const cardRef = alice.firestore().doc("users/alice/emergency/card");

      await assertSucceeds(
        cardRef.set({
          id: "card",
          userId: "alice",
          bloodType: "O+",
          allergies: ["Penicillin"],
          chronicConditions: ["Hypertension"],
          emergencyContactName: "Bob Reyes",
          emergencyContactPhone: "+639171234567",
          emergencyContactRelationship: "Spouse",
        })
      );

      await assertSucceeds(cardRef.get());

      await assertSucceeds(
        cardRef.update({
          emergencyContactPhone: "+639189876543",
        })
      );

      await assertSucceeds(cardRef.delete());
    });

    it("should allow a user to create, read, update, and delete their own medications within bounds", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const medRef = alice.firestore().doc("medications/med_123");

      const now = new Date().toISOString();
      await assertSucceeds(
        medRef.set({
          id: "med_123",
          userId: "alice",
          name: "Amlodipine",
          genericName: "Norvasc",
          strength: "5mg",
          form: "tablet",
          doseAmount: 1.0,
          instructions: "Take once daily in morning",
          colorTag: 0xff1e66f5,
          createdAt: now,
          isActive: true,
        })
      );

      await assertSucceeds(medRef.get());

      await assertSucceeds(
        medRef.update({
          instructions: "Take after meals",
          updatedAt: new Date().toISOString(),
        })
      );

      await assertSucceeds(medRef.delete());
    });

    it("should allow a user to create, read, update, and delete their own intake logs", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const logRef = alice.firestore().doc("intake_logs/log_123");

      const scheduled = new Date().toISOString();
      await assertSucceeds(
        logRef.set({
          id: "log_123",
          userId: "alice",
          medicationId: "med_123",
          medicationName: "Amlodipine",
          doseAmount: 1.0,
          scheduledTime: scheduled,
          status: "pending",
        })
      );

      await assertSucceeds(logRef.get());

      await assertSucceeds(
        logRef.update({
          status: "taken",
          recordedTime: new Date().toISOString(),
        })
      );

      await assertSucceeds(logRef.delete());
    });

    it("should allow a user to manage their own inventory items within 0..9999 bounds", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const invRef = alice.firestore().doc("inventory/inv_123");

      await assertSucceeds(
        invRef.set({
          id: "inv_123",
          userId: "alice",
          medicationId: "med_123",
          currentStock: 30.0,
          unit: "tablets",
          lowStockThreshold: 10.0,
          refillQuantity: 30.0,
        })
      );

      await assertSucceeds(invRef.get());

      await assertSucceeds(
        invRef.update({
          currentStock: 29.0,
        })
      );

      await assertSucceeds(invRef.delete());
    });

    it("should allow a verified patient to perform partial inventory stock updates with serverTimestamp", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const db = alice.firestore();
      const invRef = db.doc("inventory/inv_partial_1");

      await assertSucceeds(
        invRef.set({
          id: "inv_partial_1",
          userId: "alice",
          medicationId: "med_123",
          currentStock: 30.0,
          unit: "tablets",
          lowStockThreshold: 10.0,
          refillQuantity: 30.0,
          createdAt: new Date().toISOString(),
        })
      );

      // Direct partial .update() with serverTimestamp (used in transaction.update / batch.update)
      await assertSucceeds(
        invRef.update({
          currentStock: 29.0,
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );

      // Transaction partial .update()
      await assertSucceeds(
        db.runTransaction(async (tx) => {
          const snap = await tx.get(invRef);
          const nextStock = snap.data().currentStock - 1;
          tx.update(invRef, {
            currentStock: nextStock,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          });
        })
      );

      // Batch partial .update()
      const batch = db.batch();
      batch.update(invRef, {
        currentStock: 27.0,
        updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
      });
      await assertSucceeds(batch.commit());

      const updatedSnap = await assertSucceeds(invRef.get());
      assert.strictEqual(updatedSnap.data().currentStock, 27.0);
      assert.strictEqual(updatedSnap.data().medicationId, "med_123");

      // Partial update still rejects out-of-bounds stock and immutable field tampering
      await assertFails(
        invRef.update({
          currentStock: -1,
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
      await assertFails(
        invRef.update({
          medicationId: "med_tampered",
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );
    });

    it("should allow patient or caregiver to read, revoke, and delete their caregiver link, while blocking uninvited create", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("caregivers/alice_caregiver1").set({
          id: "alice_caregiver1",
          patientId: "alice",
          patientName: "Alice Reyes",
          caregiverId: "caregiver1",
          caregiverName: "Caregiver One",
          status: "active",
          permissions: ["view_adherence", "receive_alerts"],
          inviteCode: "ABC234",
          createdAt: new Date().toISOString(),
        });
      });

      const aliceDb = testEnv.authenticatedContext("alice").firestore();
      const caregiverDb = testEnv.authenticatedContext("caregiver1").firestore();

      await assertSucceeds(aliceDb.doc("caregivers/alice_caregiver1").get());
      await assertSucceeds(caregiverDb.doc("caregivers/alice_caregiver1").get());

      // Direct create without an atomic redeemed invite fails
      await assertFails(
        aliceDb.doc("caregivers/alice_caregiver2").set({
          id: "alice_caregiver2",
          patientId: "alice",
          patientName: "Alice Reyes",
          caregiverId: "caregiver2",
          status: "active",
          inviteCode: "XYZ999",
          createdAt: new Date().toISOString(),
        })
      );

      // Patient or caregiver can revoke (status: 'revoked') and delete
      await assertSucceeds(
        aliceDb.doc("caregivers/alice_caregiver1").update({
          status: "revoked",
          updatedAt: new Date().toISOString(),
        })
      );
      await assertSucceeds(
        caregiverDb.doc("caregivers/alice_caregiver1").delete()
      );
    });
  });

  // =========================================================================
  // 2. Unauthenticated Access Denial
  // =========================================================================
  describe("2. Unauthenticated Access Denial", () => {
    it("should deny unauthenticated read and write across all collections", async () => {
      const unauthed = testEnv.unauthenticatedContext();
      const db = unauthed.firestore();

      // Users
      await assertFails(db.doc("users/alice").get());
      await assertFails(
        db.doc("users/alice").set({
          id: "alice",
          email: "anon@example.com",
          displayName: "Anonymous",
          createdAt: new Date().toISOString(),
        })
      );

      // Emergency Card
      await assertFails(db.doc("users/alice/emergency/card").get());
      await assertFails(
        db.doc("users/alice/emergency/card").set({
          id: "card",
          userId: "alice",
          emergencyContactName: "Stranger",
          emergencyContactPhone: "123",
        })
      );

      // Medications
      await assertFails(db.doc("medications/med_1").get());
      await assertFails(
        db.doc("medications/med_1").set({
          id: "med_1",
          userId: "alice",
          name: "Test",
          strength: "10mg",
          doseAmount: 1,
          createdAt: new Date().toISOString(),
        })
      );

      // Intake Logs
      await assertFails(db.doc("intake_logs/log_1").get());
      await assertFails(
        db.doc("intake_logs/log_1").set({
          id: "log_1",
          userId: "alice",
          medicationId: "med_1",
          medicationName: "Test",
          doseAmount: 1,
          scheduledTime: new Date().toISOString(),
          status: "pending",
        })
      );

      // Inventory
      await assertFails(db.doc("inventory/inv_1").get());
      await assertFails(
        db.doc("inventory/inv_1").set({
          id: "inv_1",
          userId: "alice",
          medicationId: "med_1",
          currentStock: 10,
        })
      );

      // Appointments
      await assertFails(db.doc("appointments/app_1").get());
      await assertFails(
        db.doc("appointments/app_1").set({
          id: "app_1",
          userId: "alice",
          doctorName: "Dr. Smith",
          dateTime: new Date().toISOString(),
        })
      );

      // Caregivers
      await assertFails(db.doc("caregivers/cg_1").get());
      await assertFails(
        db.doc("caregivers/cg_1").set({
          id: "cg_1",
          patientId: "alice",
          patientName: "Alice Reyes",
          caregiverId: "bob",
          status: "active",
          inviteCode: "ABC234",
          createdAt: new Date().toISOString(),
        })
      );

      // Caregiver Invites
      await assertFails(db.doc("caregiver_invites/ABC234").get());
      await assertFails(db.collection("caregiver_invites").get());
      await assertFails(
        db.doc("caregiver_invites/ABC234").set({
          code: "ABC234",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: new Date().toISOString(),
          expiresAt: new Date(Date.now() + 3600000).toISOString(),
        })
      );

      // OTP Challenges
      await assertFails(db.doc("otp_challenges/alice").get());
      await assertFails(db.doc("otp_challenges/alice").set({ code: "123456" }));
    });
  });

  // =========================================================================
  // 3. User B Cannot Access or Tamper with User A's Data
  // =========================================================================
  describe("3. Cross-User Privacy & Isolation (User B -> User A)", () => {
    beforeEach(async () => {
      // Seed Alice's documents as admin
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        const now = new Date().toISOString();

        await adminDb.doc("users/alice").set({
          id: "alice",
          email: "alice@example.com",
          displayName: "Alice Reyes",
          createdAt: now,
          caregiverIds: [],
        });

        await adminDb.doc("users/alice/emergency/card").set({
          id: "card",
          userId: "alice",
          emergencyContactName: "Charlie",
          emergencyContactPhone: "09170000000",
        });

        await adminDb.doc("medications/alice_med").set({
          id: "alice_med",
          userId: "alice",
          name: "Metformin",
          strength: "500mg",
          doseAmount: 1,
          createdAt: now,
        });

        await adminDb.doc("intake_logs/alice_log").set({
          id: "alice_log",
          userId: "alice",
          medicationId: "alice_med",
          medicationName: "Metformin",
          doseAmount: 1,
          scheduledTime: now,
          status: "pending",
        });

        await adminDb.doc("inventory/alice_inv").set({
          id: "alice_inv",
          userId: "alice",
          medicationId: "alice_med",
          currentStock: 60,
        });
      });
    });

    it("should prevent User B (Bob) from reading or updating Alice's profile", async () => {
      const bob = testEnv.authenticatedContext("bob");
      const userRef = bob.firestore().doc("users/alice");

      await assertFails(userRef.get());
      await assertFails(userRef.update({ displayName: "Hacked" }));
      await assertFails(userRef.delete());
    });

    it("should prevent User B from reading or modifying Alice's emergency card", async () => {
      const bob = testEnv.authenticatedContext("bob");
      const cardRef = bob.firestore().doc("users/alice/emergency/card");

      await assertFails(cardRef.get());
      await assertFails(cardRef.update({ emergencyContactName: "Bob" }));
      await assertFails(cardRef.delete());
    });

    it("should prevent User B from reading, modifying, or deleting Alice's medications", async () => {
      const bob = testEnv.authenticatedContext("bob", { email_verified: true });
      const medRef = bob.firestore().doc("medications/alice_med");

      await assertFails(medRef.get());
      await assertFails(medRef.update({ name: "Poison" }));
      await assertFails(medRef.delete());
    });

    it("should prevent User B from reading, modifying, or deleting Alice's intake logs", async () => {
      const bob = testEnv.authenticatedContext("bob", { email_verified: true });
      const logRef = bob.firestore().doc("intake_logs/alice_log");

      await assertFails(logRef.get());
      await assertFails(logRef.update({ status: "taken" }));
      await assertFails(logRef.delete());
    });

    it("should prevent User B from reading, modifying, or deleting Alice's inventory", async () => {
      const bob = testEnv.authenticatedContext("bob", { email_verified: true });
      const invRef = bob.firestore().doc("inventory/alice_inv");

      await assertFails(invRef.get());
      await assertFails(invRef.update({ currentStock: 0 }));
      await assertFails(invRef.delete());
    });
  });

  // =========================================================================
  // 4. Caregiver Access Control
  // =========================================================================
  describe("4. Caregiver Authorized vs Unauthorized Access", () => {
    beforeEach(async () => {
      const now = new Date().toISOString();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();

        // Alice registers Carol as an authorized caregiver
        await adminDb.doc("users/alice").set({
          id: "alice",
          email: "alice@example.com",
          displayName: "Alice Reyes",
          createdAt: now,
          caregiverIds: ["carol"],
        });

        await adminDb.doc("users/alice/emergency/card").set({
          id: "card",
          userId: "alice",
          emergencyContactName: "Carol",
          emergencyContactPhone: "09171112222",
        });

        await adminDb.doc("medications/alice_med").set({
          id: "alice_med",
          userId: "alice",
          name: "Metformin",
          strength: "500mg",
          doseAmount: 1,
          createdAt: now,
        });

        await adminDb.doc("intake_logs/alice_log").set({
          id: "alice_log",
          userId: "alice",
          medicationId: "alice_med",
          medicationName: "Metformin",
          doseAmount: 1,
          scheduledTime: now,
          status: "pending",
        });

        await adminDb.doc("inventory/alice_inv").set({
          id: "alice_inv",
          userId: "alice",
          medicationId: "alice_med",
          currentStock: 50,
        });

        await adminDb.doc("caregivers/alice_pending").set({
          id: "alice_pending",
          patientId: "alice",
          caregiverId: "",
          status: "pending",
          createdAt: now,
        });

        await adminDb.doc("caregiver_invites/ABC234").set({
          code: "ABC234",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: Timestamp.fromMillis(Date.now() - 60000),
          expiresAt: Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000),
        });

        await adminDb.doc("users/dave").set({
          id: "dave",
          email: "dave@example.com",
          displayName: "Dave Cruz",
          createdAt: now,
          caregiverIds: [],
        });

        await adminDb.doc("medications/dave_med").set({
          id: "dave_med",
          userId: "dave",
          name: "Atorvastatin",
          strength: "20mg",
          doseAmount: 1,
          createdAt: now,
        });
      });
    });

    it("should allow an authorized caregiver (Carol) to read Alice's data", async () => {
      const carol = testEnv.authenticatedContext("carol");
      const db = carol.firestore();

      await assertSucceeds(db.doc("users/alice").get());
      await assertSucceeds(db.doc("users/alice/emergency/card").get());
      await assertSucceeds(db.doc("medications/alice_med").get());
      await assertSucceeds(db.doc("intake_logs/alice_log").get());
      await assertSucceeds(db.doc("inventory/alice_inv").get());
    });

    it("should deny strangers from reading pending caregiver relationships", async () => {
      const stranger = testEnv.authenticatedContext("stranger");
      const db = stranger.firestore();

      await assertFails(db.doc("caregivers/alice_pending").get());
    });

    it("should allow patient to create, list, expire, and delete valid 6-char invites while blocking spoofing and forgery", async () => {
      const aliceDb = testEnv.authenticatedContext("alice", { email_verified: true }).firestore();
      const bobDb = testEnv.authenticatedContext("bob", { email_verified: true }).firestore();
      const futureTs = Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000);
      const nowTs = Timestamp.now();

      // Patient creates valid 6-char invite
      await assertSucceeds(
        aliceDb.doc("caregiver_invites/XYZ789").set({
          code: "XYZ789",
          patientId: "alice",
          patientName: "Alice Reyes",
          allowedMedicationIds: ["alice_med"],
          status: "pending",
          createdAt: nowTs,
          expiresAt: futureTs,
        })
      );

      // Patient can get and list their own invites
      await assertSucceeds(aliceDb.doc("caregiver_invites/XYZ789").get());
      await assertSucceeds(
        aliceDb
          .collection("caregiver_invites")
          .where("patientId", "==", "alice")
          .where("status", "==", "pending")
          .get()
      );

      // Cannot spoof another patient's patientId
      await assertFails(
        bobDb.doc("caregiver_invites/SPOOF1").set({
          code: "SPOOF1",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: nowTs,
          expiresAt: futureTs,
        })
      );

      // Cannot forge status: 'accepted' on create
      await assertFails(
        aliceDb.doc("caregiver_invites/FORGE1").set({
          code: "FORGE1",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "accepted",
          usedBy: "bob",
          createdAt: nowTs,
          expiresAt: futureTs,
        })
      );

      // Cannot create invalid code format or mismatching code field
      await assertFails(
        aliceDb.doc("caregiver_invites/bad1").set({
          code: "bad1",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: nowTs,
          expiresAt: futureTs,
        })
      );
      await assertFails(
        aliceDb.doc("caregiver_invites/CODE12").set({
          code: "OTHER9",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: nowTs,
          expiresAt: futureTs,
        })
      );

      // Cannot create invite with expiresAt in the past or > 25h in the future
      await assertFails(
        aliceDb.doc("caregiver_invites/PAST12").set({
          code: "PAST12",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: nowTs,
          expiresAt: Timestamp.fromMillis(Date.now() - 60000),
        })
      );
      await assertFails(
        aliceDb.doc("caregiver_invites/LONG12").set({
          code: "LONG12",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: nowTs,
          expiresAt: Timestamp.fromMillis(Date.now() + 26 * 60 * 60 * 1000),
        })
      );

      // Patient can expire and delete their own invite, while stranger cannot
      await assertFails(
        bobDb.doc("caregiver_invites/XYZ789").update({ status: "expired" })
      );
      await assertFails(bobDb.doc("caregiver_invites/XYZ789").delete());
      await assertSucceeds(
        aliceDb.doc("caregiver_invites/XYZ789").update({
          status: "expired",
          updatedAt: Timestamp.now(),
        })
      );
      await assertSucceeds(aliceDb.doc("caregiver_invites/XYZ789").delete());
    });

    it("should restrict caregiver_invites list and accepted-invite reads while allowing exact get on missing or pending codes", async () => {
      const aliceDb = testEnv.authenticatedContext("alice").firestore();
      const strangerDb = testEnv.authenticatedContext("stranger").firestore();

      // Lookup of a non-existent 6-char code resolves cleanly as non-existent (resource == null)
      const missingSnap = await assertSucceeds(
        strangerDb.doc("caregiver_invites/NOPE99").get()
      );
      assert.strictEqual(missingSnap.exists, false);

      // Authenticated user knowing exact pending 6-char code can get it
      const pendingSnap = await assertSucceeds(
        strangerDb.doc("caregiver_invites/ABC234").get()
      );
      assert.strictEqual(pendingSnap.exists, true);

      // Strangers CANNOT enumerate/list another patient's invites
      await assertFails(strangerDb.collection("caregiver_invites").get());
      await assertFails(
        strangerDb
          .collection("caregiver_invites")
          .where("status", "==", "pending")
          .get()
      );
      await assertFails(
        strangerDb
          .collection("caregiver_invites")
          .where("patientId", "==", "alice")
          .get()
      );

      // Seed an already-accepted invite and an expired invite
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        await adminDb.doc("caregiver_invites/USED12").set({
          code: "USED12",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "accepted",
          usedBy: "carol",
          createdAt: Timestamp.now(),
          expiresAt: Timestamp.fromMillis(Date.now() + 3600000),
        });
        await adminDb.doc("caregiver_invites/EXP123").set({
          code: "EXP123",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "expired",
          createdAt: Timestamp.now(),
          expiresAt: Timestamp.fromMillis(Date.now() + 3600000),
        });
      });

      // Owning patient can still read accepted/expired invites, strangers cannot
      await assertSucceeds(aliceDb.doc("caregiver_invites/USED12").get());
      await assertSucceeds(aliceDb.doc("caregiver_invites/EXP123").get());
      await assertFails(strangerDb.doc("caregiver_invites/USED12").get());
      await assertFails(strangerDb.doc("caregiver_invites/EXP123").get());
    });

    it("should block caregiver hijacking, self-linking, and expired invite redemption", async () => {
      const aliceDb = testEnv.authenticatedContext("alice", { email_verified: true }).firestore();
      const daveDb = testEnv.authenticatedContext("dave", { email_verified: true }).firestore();
      const strangerDb = testEnv.authenticatedContext("stranger", { email_verified: true }).firestore();
      const nowIso = new Date().toISOString();

      // Stranger cannot create caregivers/{relationshipId} directly without atomic WriteBatch
      await assertFails(
        strangerDb.doc("caregivers/alice_stranger").set({
          id: "alice_stranger",
          patientId: "alice",
          patientName: "Alice Reyes",
          caregiverId: "stranger",
          status: "active",
          permissions: ["view_adherence", "receive_alerts"],
          inviteCode: "ABC234",
          createdAt: nowIso,
        })
      );

      // Stranger cannot hijack another caregiver's relationshipId even in a WriteBatch
      const hijackBatch = strangerDb.batch();
      hijackBatch.update(strangerDb.doc("caregiver_invites/ABC234"), {
        status: "accepted",
        usedBy: "stranger",
        usedAt: nowIso,
      });
      hijackBatch.set(strangerDb.doc("caregivers/alice_dave"), {
        id: "alice_dave",
        patientId: "alice",
        patientName: "Alice Reyes",
        caregiverId: "dave",
        status: "active",
        permissions: ["view_adherence", "receive_alerts"],
        inviteCode: "ABC234",
        createdAt: nowIso,
      });
      await assertFails(hijackBatch.commit());

      // Stranger cannot redeem an invite while spoofing usedBy or tampering with immutable fields
      const spoofUsedByBatch = strangerDb.batch();
      spoofUsedByBatch.update(strangerDb.doc("caregiver_invites/ABC234"), {
        status: "accepted",
        usedBy: "dave",
      });
      spoofUsedByBatch.set(strangerDb.doc("caregivers/alice_stranger"), {
        id: "alice_stranger",
        patientId: "alice",
        patientName: "Alice Reyes",
        caregiverId: "stranger",
        status: "active",
        inviteCode: "ABC234",
        createdAt: nowIso,
      });
      await assertFails(spoofUsedByBatch.commit());

      // Patient cannot self-link (patientId == caregiverId)
      const selfBatch = aliceDb.batch();
      selfBatch.update(aliceDb.doc("caregiver_invites/ABC234"), {
        status: "accepted",
        usedBy: "alice",
      });
      selfBatch.set(aliceDb.doc("caregivers/alice_alice"), {
        id: "alice_alice",
        patientId: "alice",
        patientName: "Alice Reyes",
        caregiverId: "alice",
        status: "active",
        inviteCode: "ABC234",
        createdAt: nowIso,
      });
      await assertFails(selfBatch.commit());

      // Expired invite (Timestamp in the past) cannot be redeemed in a WriteBatch
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("caregiver_invites/OLD999").set({
          code: "OLD999",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: Timestamp.fromMillis(Date.now() - 25 * 60 * 60 * 1000),
          expiresAt: Timestamp.fromMillis(Date.now() - 60 * 1000),
        });
      });

      const expiredBatch = daveDb.batch();
      expiredBatch.update(daveDb.doc("caregiver_invites/OLD999"), {
        status: "accepted",
        usedBy: "dave",
        usedAt: Timestamp.now(),
      });
      expiredBatch.set(daveDb.doc("caregivers/alice_dave"), {
        id: "alice_dave",
        patientId: "alice",
        patientName: "Alice Reyes",
        caregiverId: "dave",
        caregiverName: "Dave Cruz",
        status: "active",
        permissions: ["view_adherence", "receive_alerts"],
        inviteCode: "OLD999",
        createdAt: Timestamp.now(),
      });
      await assertFails(expiredBatch.commit());
    });

    it("should allow valid caregiver WriteBatch pairing, enforce strict read-only access, prevent replay, and support revocation", async () => {
      const aliceDb = testEnv.authenticatedContext("alice", { email_verified: true }).firestore();
      const daveDb = testEnv.authenticatedContext("dave", { email_verified: true }).firestore();
      const eveDb = testEnv.authenticatedContext("eve", { email_verified: true }).firestore();
      const nowTs = Timestamp.now();

      // Before pairing, Dave cannot read Alice's data
      await assertFails(daveDb.doc("users/alice").get());
      await assertFails(daveDb.doc("medications/alice_med").get());

      // Valid atomic WriteBatch: redeem invite ABC234 + create caregivers/alice_dave
      const pairBatch = daveDb.batch();
      pairBatch.update(daveDb.doc("caregiver_invites/ABC234"), {
        status: "accepted",
        usedBy: "dave",
        usedAt: nowTs,
        updatedAt: nowTs,
      });
      pairBatch.set(daveDb.doc("caregivers/alice_dave"), {
        id: "alice_dave",
        patientId: "alice",
        patientName: "Alice Reyes",
        caregiverId: "dave",
        caregiverName: "Dave Cruz",
        status: "active",
        permissions: ["view_adherence", "receive_alerts"],
        inviteCode: "ABC234",
        createdAt: nowTs,
        updatedAt: nowTs,
      });
      await assertSucceeds(pairBatch.commit());

      // Dave can now read Alice's health & emergency records (including filtered queries)
      await assertSucceeds(daveDb.doc("users/alice").get());
      await assertSucceeds(daveDb.doc("users/alice/emergency/card").get());
      await assertSucceeds(daveDb.doc("medications/alice_med").get());
      await assertSucceeds(daveDb.doc("intake_logs/alice_log").get());
      await assertSucceeds(daveDb.doc("inventory/alice_inv").get());
      await assertSucceeds(
        daveDb.collection("medications").where("userId", "==", "alice").get()
      );

      // Dave STILL remains strictly read-only on users, medications, intake_logs, inventory, emergency
      await assertFails(
        daveDb.doc("users/alice").update({ displayName: "Tampered" })
      );
      await assertFails(
        daveDb.doc("medications/alice_med").update({ name: "Tampered" })
      );
      await assertFails(daveDb.doc("medications/alice_med").delete());
      await assertFails(
        daveDb.doc("intake_logs/alice_log").update({ status: "taken" })
      );
      await assertFails(
        daveDb.doc("inventory/alice_inv").update({ currentStock: 0 })
      );
      await assertFails(
        daveDb
          .doc("users/alice/emergency/card")
          .update({ emergencyContactPhone: "000" })
      );

      // Reverse-direction leak prevention: Patient (Alice) cannot read Caregiver (Dave)'s private data
      await assertFails(aliceDb.doc("users/dave").get());
      await assertFails(aliceDb.doc("medications/dave_med").get());

      // Single-use guarantee: Eve cannot read or replay the already-accepted invite ABC234
      await assertFails(eveDb.doc("caregiver_invites/ABC234").get());
      const replayBatch = eveDb.batch();
      replayBatch.update(eveDb.doc("caregiver_invites/ABC234"), {
        status: "accepted",
        usedBy: "eve",
      });
      replayBatch.set(eveDb.doc("caregivers/alice_eve"), {
        id: "alice_eve",
        patientId: "alice",
        patientName: "Alice Reyes",
        caregiverId: "eve",
        status: "active",
        inviteCode: "ABC234",
        createdAt: nowTs,
      });
      await assertFails(replayBatch.commit());

      // Stranger cannot revoke or delete caregivers/alice_dave
      await assertFails(
        eveDb.doc("caregivers/alice_dave").update({ status: "revoked" })
      );
      await assertFails(eveDb.doc("caregivers/alice_dave").delete());

      // Caregiver cannot escalate permissions or alter immutable fields on update
      await assertFails(
        daveDb.doc("caregivers/alice_dave").update({
          status: "revoked",
          permissions: ["view_adherence"],
        })
      );

      // Either patient or caregiver can revoke (status: 'revoked')
      await assertSucceeds(
        aliceDb.doc("caregivers/alice_dave").update({
          status: "revoked",
          updatedAt: Timestamp.now(),
        })
      );

      // Cannot reactivate a revoked link via standalone update without a valid redeemed invite
      await assertFails(
        daveDb.doc("caregivers/alice_dave").update({
          status: "active",
        })
      );

      // Once revoked, Dave immediately loses read access to Alice's private data
      await assertFails(daveDb.doc("users/alice").get());
      await assertFails(daveDb.doc("users/alice/emergency/card").get());
      await assertFails(daveDb.doc("medications/alice_med").get());
      await assertFails(daveDb.doc("intake_logs/alice_log").get());
      await assertFails(daveDb.doc("inventory/alice_inv").get());

      // Re-linking a previously revoked caregiver via a new pending invite in an atomic WriteBatch succeeds
      const futureTs = Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000);
      await assertSucceeds(
        aliceDb.doc("caregiver_invites/RELNK1").set({
          code: "RELNK1",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: nowTs,
          expiresAt: futureTs,
        })
      );
      const relinkBatch = daveDb.batch();
      relinkBatch.update(daveDb.doc("caregiver_invites/RELNK1"), {
        status: "accepted",
        usedBy: "dave",
        usedAt: nowTs,
        updatedAt: nowTs,
      });
      relinkBatch.set(daveDb.doc("caregivers/alice_dave"), {
        id: "alice_dave",
        patientId: "alice",
        patientName: "Alice Reyes",
        caregiverId: "dave",
        caregiverName: "Dave Cruz",
        status: "active",
        permissions: ["view_adherence", "receive_alerts"],
        inviteCode: "RELNK1",
        createdAt: nowTs,
        updatedAt: nowTs,
      });
      await assertSucceeds(relinkBatch.commit());
      await assertSucceeds(daveDb.doc("users/alice").get());

      // Caregiver can also revoke an active relationship (and either party can delete)
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("caregivers/alice_eve").set({
          id: "alice_eve",
          patientId: "alice",
          patientName: "Alice Reyes",
          caregiverId: "eve",
          status: "active",
          permissions: ["view_adherence", "receive_alerts"],
          inviteCode: "EVE123",
          createdAt: nowTs,
        });
      });
      await assertSucceeds(
        eveDb.doc("caregivers/alice_eve").update({
          status: "revoked",
          updatedAt: Timestamp.now(),
        })
      );
      await assertSucceeds(daveDb.doc("caregivers/alice_dave").delete());
      await assertSucceeds(aliceDb.doc("caregivers/alice_eve").delete());
    });

    it("should deny an unauthorized caregiver (Dave) from reading Alice's private data", async () => {
      const dave = testEnv.authenticatedContext("dave");
      const db = dave.firestore();

      await assertFails(db.doc("users/alice").get());
      await assertFails(db.doc("users/alice/emergency/card").get());
      await assertFails(db.doc("medications/alice_med").get());
      await assertFails(db.doc("intake_logs/alice_log").get());
    });

    it("should not allow caregiver (Carol) to modify or delete Alice's medication, profile, logs, inventory, or emergency card (least privilege)", async () => {
      const carol = testEnv.authenticatedContext("carol", { email_verified: true });
      const db = carol.firestore();

      await assertFails(db.doc("users/alice").update({ displayName: "Tampered" }));
      await assertFails(db.doc("users/alice/emergency/card").update({ bloodType: "AB-" }));
      await assertFails(db.doc("medications/alice_med").update({ name: "Tampered" }));
      await assertFails(db.doc("medications/alice_med").delete());
      await assertFails(db.doc("intake_logs/alice_log").update({ status: "taken" }));
      await assertFails(db.doc("inventory/alice_inv").update({ currentStock: 1 }));
    });

    it("should allow patient or authorized caregiver to create caregiver_alerts while blocking spoofed or unlinked alerts", async () => {
      const aliceDb = testEnv.authenticatedContext("alice", { email_verified: true }).firestore();
      const carolDb = testEnv.authenticatedContext("carol", { email_verified: true }).firestore();
      const daveDb = testEnv.authenticatedContext("dave", { email_verified: true }).firestore();
      const strangerDb = testEnv.authenticatedContext("stranger", { email_verified: true }).firestore();
      const nowIso = new Date().toISOString();

      // Blocking caregiver_alerts creation when no active caregivers/{patientId}_{caregiverId} relationship exists
      await assertFails(
        aliceDb.doc("caregiver_alerts/alert_no_rel").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "alice",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        })
      );
      await assertFails(
        aliceDb.doc("caregiver_alerts/alert_unlinked_dave").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_dave",
          patientId: "alice",
          caregiverId: "dave",
          status: "pending",
          createdAt: nowIso,
        })
      );

      // Seed active caregiver relationship caregivers/alice_carol
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("caregivers/alice_carol").set({
          id: "alice_carol",
          patientId: "alice",
          patientName: "Alice Reyes",
          caregiverId: "carol",
          caregiverName: "Carol Santos",
          status: "active",
          permissions: ["view_adherence", "receive_alerts"],
          inviteCode: "CAROL1",
          createdAt: nowIso,
        });
      });

      // Patient can create alert when active relationship exists
      await assertSucceeds(
        aliceDb.doc("caregiver_alerts/alert_patient").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "alice",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        })
      );

      // Authorized caregiver (Carol) can create alert for Alice when active relationship exists
      await assertSucceeds(
        carolDb.doc("caregiver_alerts/alert_carol").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "alice",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        })
      );

      // Unlinked stranger cannot create spoofed alert targeting Alice
      await assertFails(
        strangerDb.doc("caregiver_alerts/alert_spoof").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_stranger",
          patientId: "alice",
          caregiverId: "stranger",
          status: "pending",
          createdAt: nowIso,
        })
      );

      // Revoked relationship blocks further caregiver_alerts creation
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("caregivers/alice_carol").update({
          status: "revoked",
        });
      });
      await assertFails(
        aliceDb.doc("caregiver_alerts/alert_after_revoke").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "alice",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        })
      );
      await assertFails(
        carolDb.doc("caregiver_alerts/alert_carol_revoked").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "alice",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        })
      );
      // Restore dave Db unused check
      await assertFails(daveDb.doc("caregiver_alerts/alert_patient").get());
    });

    it("should enforce allowedMedicationIds scope on medications/{medId} caregiver reads", async () => {
      const nowIso = new Date().toISOString();
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        await adminDb.doc("medications/alice_med_secret").set({
          id: "alice_med_secret",
          userId: "alice",
          name: "Sertraline",
          strength: "50mg",
          doseAmount: 1,
          createdAt: nowIso,
        });

        // Caregiver Carol is restricted to only ['alice_med']
        await adminDb.doc("caregivers/alice_carol").set({
          id: "alice_carol",
          patientId: "alice",
          patientName: "Alice Reyes",
          caregiverId: "carol",
          caregiverName: "Carol Santos",
          status: "active",
          allowedMedicationIds: ["alice_med"],
          permissions: ["view_adherence", "receive_alerts"],
          inviteCode: "CAROL1",
          createdAt: nowIso,
        });
      });

      const aliceDb = testEnv.authenticatedContext("alice").firestore();
      const carolDb = testEnv.authenticatedContext("carol").firestore();

      // Patient Alice can read both of her own medications
      await assertSucceeds(aliceDb.doc("medications/alice_med").get());
      await assertSucceeds(aliceDb.doc("medications/alice_med_secret").get());

      // Caregiver Carol CAN read the allowed medication ('alice_med')
      await assertSucceeds(carolDb.doc("medications/alice_med").get());

      // Caregiver Carol CANNOT read the non-allowed medication ('alice_med_secret')
      await assertFails(carolDb.doc("medications/alice_med_secret").get());

      // Unfiltered collection query across all Alice medications fails when Carol is scoped to only ['alice_med']
      await assertFails(
        carolDb.collection("medications").where("userId", "==", "alice").get()
      );

      // Scoped collection query constrained to allowed medication IDs succeeds
      const scopedQuerySnap = await assertSucceeds(
        carolDb
            .collection("medications")
            .where("userId", "==", "alice")
            .where(firebase.firestore.FieldPath.documentId(), "in", ["alice_med"])
            .get()
      );
      assert.strictEqual(scopedQuerySnap.docs.length, 1);
      assert.strictEqual(scopedQuerySnap.docs[0].id, "alice_med");

      // When allowedMedicationIds is empty ([]), caregiver can read all of patient's medications via doc get AND collection query
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("caregivers/alice_carol").update({
          allowedMedicationIds: [],
        });
      });
      await assertSucceeds(carolDb.doc("medications/alice_med").get());
      await assertSucceeds(carolDb.doc("medications/alice_med_secret").get());
      const unscopedQuerySnap = await assertSucceeds(
        carolDb.collection("medications").where("userId", "==", "alice").get()
      );
      assert.strictEqual(unscopedQuerySnap.docs.length, 2);
    });

    it("should deny client self-certification of emailOtpVerified on users/{uid} create and update", async () => {
      const nowIso = new Date().toISOString();
      const bobDb = testEnv.authenticatedContext("bob").firestore();
      const carolDb = testEnv.authenticatedContext("carol").firestore();

      // Client CANNOT create users/{uid} with emailOtpVerified: true
      await assertFails(
        bobDb.doc("users/bob").set({
          id: "bob",
          email: "bob@example.com",
          displayName: "Bob Cruz",
          emailOtpVerified: true,
          createdAt: nowIso,
        })
      );

      // Client CAN create users/{uid} with emailOtpVerified: false
      await assertSucceeds(
        bobDb.doc("users/bob").set({
          id: "bob",
          email: "bob@example.com",
          displayName: "Bob Cruz",
          emailOtpVerified: false,
          createdAt: nowIso,
        })
      );

      // Client CANNOT update users/{uid} to flip emailOtpVerified from false -> true
      await assertFails(
        bobDb.doc("users/bob").update({
          emailOtpVerified: true,
          updatedAt: nowIso,
        })
      );

      // Client CAN create users/{uid} omitting emailOtpVerified, and CANNOT later add emailOtpVerified: true
      await assertSucceeds(
        carolDb.doc("users/carol").set({
          id: "carol",
          email: "carol@example.com",
          displayName: "Carol Santos",
          createdAt: nowIso,
        })
      );
      await assertFails(
        carolDb.doc("users/carol").update({
          emailOtpVerified: true,
        })
      );

      // Once Admin SDK sets emailOtpVerified: true, client CANNOT downgrade or delete it
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("users/bob").update({
          emailOtpVerified: true,
          emailVerifiedAt: Timestamp.now(),
        });
      });

      await assertFails(
        bobDb.doc("users/bob").update({
          emailOtpVerified: false,
        })
      );
      await assertFails(
        bobDb.doc("users/bob").update({
          emailOtpVerified: firebase.firestore.FieldValue.delete(),
        })
      );

      // Non-privileged profile updates still succeed when emailOtpVerified is untouched
      await assertSucceeds(
        bobDb.doc("users/bob").update({
          displayName: "Bob C. Updated",
          updatedAt: nowIso,
        })
      );
    });

    it("should deny unverified users (missing user doc or emailOtpVerified: false) from creating, updating, or deleting OTP-gated collections", async () => {
      const nowIso = new Date().toISOString();
      const futureTs = Timestamp.fromMillis(Date.now() + 24 * 60 * 60 * 1000);
      const nowTs = Timestamp.now();

      // Seed Alice with emailOtpVerified: false, an active caregiver link, and existing docs to test update/delete denials
      await testEnv.withSecurityRulesDisabled(async (context) => {
        const adminDb = context.firestore();
        await adminDb.doc("users/alice").set({
          id: "alice",
          email: "alice@example.com",
          displayName: "Alice Reyes",
          emailOtpVerified: false,
          createdAt: nowIso,
          caregiverIds: ["carol"],
        });
        await adminDb.doc("caregivers/alice_carol").set({
          id: "alice_carol",
          patientId: "alice",
          patientName: "Alice Reyes",
          caregiverId: "carol",
          status: "active",
          inviteCode: "CAROL1",
          createdAt: nowIso,
        });
        await adminDb.doc("caregiver_alerts/alice_existing_alert").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "alice",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        });
        // Seed a brand-new user "ghost" with NO users/ghost document at all, plus existing owned docs
        await adminDb.doc("medications/ghost_med").set({
          id: "ghost_med",
          userId: "ghost",
          name: "Aspirin",
          strength: "81mg",
          doseAmount: 1,
          createdAt: nowIso,
        });
        await adminDb.doc("inventory/ghost_inv").set({
          id: "ghost_inv",
          userId: "ghost",
          medicationId: "ghost_med",
          currentStock: 10,
        });
        await adminDb.doc("intake_logs/ghost_log").set({
          id: "ghost_log",
          userId: "ghost",
          medicationId: "ghost_med",
          medicationName: "Aspirin",
          doseAmount: 1,
          scheduledTime: nowIso,
          status: "pending",
        });
        await adminDb.doc("caregivers/ghost_carol").set({
          id: "ghost_carol",
          patientId: "ghost",
          patientName: "Ghost User",
          caregiverId: "carol",
          status: "active",
          inviteCode: "GHOST1",
          createdAt: nowIso,
        });
        await adminDb.doc("caregiver_alerts/ghost_alert").set({
          dependentName: "Ghost User",
          medicationName: "Aspirin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "ghost",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        });
        await adminDb.doc("caregiver_invites/GHST12").set({
          code: "GHST12",
          patientId: "ghost",
          patientName: "Ghost User",
          status: "pending",
          createdAt: nowTs,
          expiresAt: futureTs,
        });
      });

      // Case A: Unverified user with users/alice.emailOtpVerified == false (no email_verified or emailOtpVerified token claim)
      const unverifiedAliceDb = testEnv.authenticatedContext("alice").firestore();

      // medications: create, update, delete all DENIED
      await assertFails(
        unverifiedAliceDb.doc("medications/unver_med").set({
          id: "unver_med",
          userId: "alice",
          name: "Lisinopril",
          strength: "10mg",
          doseAmount: 1,
          createdAt: nowIso,
        })
      );
      await assertFails(
        unverifiedAliceDb.doc("medications/alice_med").update({ name: "Updated" })
      );
      await assertFails(unverifiedAliceDb.doc("medications/alice_med").delete());

      // inventory: create, update, delete all DENIED
      await assertFails(
        unverifiedAliceDb.doc("inventory/unver_inv").set({
          id: "unver_inv",
          userId: "alice",
          medicationId: "alice_med",
          currentStock: 30,
        })
      );
      await assertFails(
        unverifiedAliceDb.doc("inventory/alice_inv").update({ currentStock: 40 })
      );
      await assertFails(unverifiedAliceDb.doc("inventory/alice_inv").delete());

      // intake_logs: create, update, delete all DENIED
      await assertFails(
        unverifiedAliceDb.doc("intake_logs/unver_log").set({
          id: "unver_log",
          userId: "alice",
          medicationId: "alice_med",
          medicationName: "Metformin",
          doseAmount: 1,
          scheduledTime: nowIso,
          status: "pending",
        })
      );
      await assertFails(
        unverifiedAliceDb.doc("intake_logs/alice_log").update({ status: "taken" })
      );
      await assertFails(unverifiedAliceDb.doc("intake_logs/alice_log").delete());

      // caregiver_alerts: create, update, delete all DENIED
      await assertFails(
        unverifiedAliceDb.doc("caregiver_alerts/alert_unver").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "alice",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        })
      );
      await assertFails(
        unverifiedAliceDb
          .doc("caregiver_alerts/alice_existing_alert")
          .update({ status: "sent" })
      );
      await assertFails(
        unverifiedAliceDb.doc("caregiver_alerts/alice_existing_alert").delete()
      );

      // caregiver_invites: create, update, delete all DENIED
      await assertFails(
        unverifiedAliceDb.doc("caregiver_invites/UNVER1").set({
          code: "UNVER1",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: nowTs,
          expiresAt: futureTs,
        })
      );
      await assertFails(
        unverifiedAliceDb
          .doc("caregiver_invites/ABC234")
          .update({ status: "expired" })
      );
      await assertFails(
        unverifiedAliceDb.doc("caregiver_invites/ABC234").delete()
      );

      // Case B: Unverified user with NO users/{uid} document (proves !exists bypass is removed)
      const ghostDb = testEnv.authenticatedContext("ghost").firestore();

      await assertFails(
        ghostDb.doc("medications/ghost_new_med").set({
          id: "ghost_new_med",
          userId: "ghost",
          name: "Aspirin",
          strength: "81mg",
          doseAmount: 1,
          createdAt: nowIso,
        })
      );
      await assertFails(
        ghostDb.doc("medications/ghost_med").update({ name: "Updated" })
      );
      await assertFails(ghostDb.doc("medications/ghost_med").delete());

      await assertFails(
        ghostDb.doc("inventory/ghost_new_inv").set({
          id: "ghost_new_inv",
          userId: "ghost",
          medicationId: "ghost_med",
          currentStock: 20,
        })
      );
      await assertFails(
        ghostDb.doc("inventory/ghost_inv").update({ currentStock: 5 })
      );
      await assertFails(ghostDb.doc("inventory/ghost_inv").delete());

      await assertFails(
        ghostDb.doc("intake_logs/ghost_new_log").set({
          id: "ghost_new_log",
          userId: "ghost",
          medicationId: "ghost_med",
          medicationName: "Aspirin",
          doseAmount: 1,
          scheduledTime: nowIso,
          status: "pending",
        })
      );
      await assertFails(
        ghostDb.doc("intake_logs/ghost_log").update({ status: "taken" })
      );
      await assertFails(ghostDb.doc("intake_logs/ghost_log").delete());

      await assertFails(
        ghostDb.doc("caregiver_alerts/ghost_new_alert").set({
          dependentName: "Ghost User",
          medicationName: "Aspirin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "ghost",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        })
      );
      await assertFails(
        ghostDb.doc("caregiver_alerts/ghost_alert").update({ status: "sent" })
      );
      await assertFails(ghostDb.doc("caregiver_alerts/ghost_alert").delete());

      await assertFails(
        ghostDb.doc("caregiver_invites/GHST99").set({
          code: "GHST99",
          patientId: "ghost",
          patientName: "Ghost User",
          status: "pending",
          createdAt: nowTs,
          expiresAt: futureTs,
        })
      );
      await assertFails(
        ghostDb.doc("caregiver_invites/GHST12").update({ status: "expired" })
      );
      await assertFails(ghostDb.doc("caregiver_invites/GHST12").delete());

      // Case C: Once Admin SDK sets users/alice.emailOtpVerified = true, Alice can write even without token claims
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("users/alice").update({
          emailOtpVerified: true,
        });
      });

      await assertSucceeds(
        unverifiedAliceDb.doc("medications/server_ver_med").set({
          id: "server_ver_med",
          userId: "alice",
          name: "Lisinopril",
          strength: "10mg",
          doseAmount: 1,
          createdAt: nowIso,
        })
      );
      await assertSucceeds(
        unverifiedAliceDb.doc("intake_logs/alice_log").update({ status: "taken" })
      );
      await assertSucceeds(
        unverifiedAliceDb.doc("inventory/alice_inv").update({ currentStock: 40 })
      );
      await assertSucceeds(
        unverifiedAliceDb.doc("caregiver_invites/VERFD1").set({
          code: "VERFD1",
          patientId: "alice",
          patientName: "Alice Reyes",
          status: "pending",
          createdAt: nowTs,
          expiresAt: futureTs,
        })
      );
      await assertSucceeds(
        unverifiedAliceDb.doc("caregiver_alerts/alert_ver").set({
          dependentName: "Alice Reyes",
          medicationName: "Metformin",
          scheduledTime: "08:00",
          caregiverToken: "fcm_token_carol",
          patientId: "alice",
          caregiverId: "carol",
          status: "pending",
          createdAt: nowIso,
        })
      );

      // Case D: User with emailOtpVerified: true custom claim can also write without users/{uid} doc
      const claimedGhostDb = testEnv
        .authenticatedContext("ghost", { emailOtpVerified: true })
        .firestore();
      await assertSucceeds(
        claimedGhostDb.doc("medications/ghost_claimed_med").set({
          id: "ghost_claimed_med",
          userId: "ghost",
          name: "Aspirin",
          strength: "81mg",
          doseAmount: 1,
          createdAt: nowIso,
        })
      );
    });
  });

  // =========================================================================
  // 5. Ownership Hijacking & Immutability Protection
  // =========================================================================
  describe("5. Ownership Hijacking & Immutability Protection", () => {
    it("should block User B from creating a medication record spoofing Alice's userId", async () => {
      const bob = testEnv.authenticatedContext("bob", { email_verified: true });
      const medRef = bob.firestore().doc("medications/spoofed_med");

      await assertFails(
        medRef.set({
          id: "spoofed_med",
          userId: "alice", // Spoofed ownership
          name: "Insulin",
          strength: "100IU",
          doseAmount: 1,
          createdAt: new Date().toISOString(),
        })
      );
    });

    it("should block Alice from transferring/hijacking medication userId to Bob on update", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const medRef = alice.firestore().doc("medications/alice_med");

      const now = new Date().toISOString();
      await assertSucceeds(
        medRef.set({
          id: "alice_med",
          userId: "alice",
          name: "Metformin",
          strength: "500mg",
          doseAmount: 1,
          createdAt: now,
        })
      );

      // Attempt to reassign userId to bob
      await assertFails(
        medRef.update({
          userId: "bob",
        })
      );
    });

    it("should block Alice from changing immutable createdAt on medications", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const medRef = alice.firestore().doc("medications/alice_med");

      const originalTime = new Date("2026-01-01T00:00:00Z").toISOString();
      await assertSucceeds(
        medRef.set({
          id: "alice_med",
          userId: "alice",
          name: "Metformin",
          strength: "500mg",
          doseAmount: 1,
          createdAt: originalTime,
        })
      );

      await assertFails(
        medRef.update({
          createdAt: new Date().toISOString(),
        })
      );
    });

    it("should block modifying immutable medicationId or scheduledTime on intake logs", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const logRef = alice.firestore().doc("intake_logs/log_immutable");

      const scheduledTime = new Date().toISOString();
      await assertSucceeds(
        logRef.set({
          id: "log_immutable",
          userId: "alice",
          medicationId: "med_1",
          medicationName: "Aspirin",
          doseAmount: 1,
          scheduledTime: scheduledTime,
          status: "pending",
        })
      );

      // Attempt to tamper with medicationId
      await assertFails(
        logRef.update({
          medicationId: "med_tampered",
        })
      );

      // Attempt to tamper with scheduledTime
      await assertFails(
        logRef.update({
          scheduledTime: new Date("2026-12-31T00:00:00Z").toISOString(),
        })
      );
    });

    it("should block user from pre-populating or modifying immutable email, caregiverIds, or dependentIds on own profile", async () => {
      const alice = testEnv.authenticatedContext("alice");
      const userRef = alice.firestore().doc("users/alice");

      await assertFails(
        userRef.set({
          id: "alice",
          email: "alice@example.com",
          displayName: "Alice Reyes",
          createdAt: new Date().toISOString(),
          caregiverIds: ["carol"],
        })
      );

      await assertFails(
        userRef.set({
          id: "alice",
          email: "alice@example.com",
          displayName: "Alice Reyes",
          createdAt: new Date().toISOString(),
          dependentIds: ["bob"],
        })
      );

      await assertSucceeds(
        userRef.set({
          id: "alice",
          email: "alice@example.com",
          displayName: "Alice Reyes",
          createdAt: new Date().toISOString(),
          caregiverIds: [],
          dependentIds: [],
        })
      );

      await assertFails(userRef.update({ email: "newemail@example.com" }));
      await assertFails(userRef.update({ caregiverIds: ["carol"] }));
      await assertFails(userRef.update({ dependentIds: ["bob"] }));
    });
  });

  // =========================================================================
  // 6. Schema Validation & Production Bounds
  // =========================================================================
  describe("6. Schema Validation & Exact Bounds", () => {
    it("should reject user document with missing required fields (e.g. displayName)", async () => {
      const alice = testEnv.authenticatedContext("alice");
      const userRef = alice.firestore().doc("users/alice");

      await assertFails(
        userRef.set({
          id: "alice",
          email: "alice@example.com",
          // displayName omitted
          createdAt: new Date().toISOString(),
        })
      );
    });

    it("should reject user document with invalid email format", async () => {
      const alice = testEnv.authenticatedContext("alice");
      const userRef = alice.firestore().doc("users/alice");

      await assertFails(
        userRef.set({
          id: "alice",
          email: "not-an-email",
          displayName: "Alice",
          createdAt: new Date().toISOString(),
        })
      );
    });

    it("should reject medication name > 60 chars or strength > 30 chars", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const medRef = alice.firestore().doc("medications/med_bounds");

      // Name > 60 chars
      await assertFails(
        medRef.set({
          id: "med_bounds",
          userId: "alice",
          name: "A".repeat(61),
          strength: "500mg",
          doseAmount: 1,
          createdAt: new Date().toISOString(),
        })
      );

      // Strength > 30 chars
      await assertFails(
        medRef.set({
          id: "med_bounds",
          userId: "alice",
          name: "Metformin",
          strength: "A".repeat(31),
          doseAmount: 1,
          createdAt: new Date().toISOString(),
        })
      );
    });

    it("should reject medication instructions > 200 chars or genericName > 60 chars", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const medRef = alice.firestore().doc("medications/med_bounds_2");

      // Instructions > 200 chars
      await assertFails(
        medRef.set({
          id: "med_bounds_2",
          userId: "alice",
          name: "Metformin",
          strength: "500mg",
          instructions: "I".repeat(201),
          doseAmount: 1,
          createdAt: new Date().toISOString(),
        })
      );

      // Generic name > 60 chars
      await assertFails(
        medRef.set({
          id: "med_bounds_2",
          userId: "alice",
          name: "Metformin",
          strength: "500mg",
          genericName: "G".repeat(61),
          doseAmount: 1,
          createdAt: new Date().toISOString(),
        })
      );
    });

    it("should reject medication doseAmount <= 0 or > 100", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const medRef = alice.firestore().doc("medications/med_dose");

      // 0 dose
      await assertFails(
        medRef.set({
          id: "med_dose",
          userId: "alice",
          name: "Metformin",
          strength: "500mg",
          doseAmount: 0,
          createdAt: new Date().toISOString(),
        })
      );

      // > 100 dose
      await assertFails(
        medRef.set({
          id: "med_dose",
          userId: "alice",
          name: "Metformin",
          strength: "500mg",
          doseAmount: 101,
          createdAt: new Date().toISOString(),
        })
      );
    });

    it("should reject inventory currentStock or lowStockThreshold < 0 or > 9999", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const invRef = alice.firestore().doc("inventory/inv_stock");

      // Negative stock
      await assertFails(
        invRef.set({
          id: "inv_stock",
          userId: "alice",
          medicationId: "med_1",
          currentStock: -1,
        })
      );

      // > 9999 stock
      await assertFails(
        invRef.set({
          id: "inv_stock",
          userId: "alice",
          medicationId: "med_1",
          currentStock: 10000,
        })
      );

      // > 9999 lowStockThreshold
      await assertFails(
        invRef.set({
          id: "inv_stock",
          userId: "alice",
          medicationId: "med_1",
          currentStock: 50,
          lowStockThreshold: 10000,
        })
      );
    });

    it("should reject intake log doseAmount <= 0 or > 100", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const logRef = alice.firestore().doc("intake_logs/log_dose");

      await assertFails(
        logRef.set({
          id: "log_dose",
          userId: "alice",
          medicationId: "med_1",
          medicationName: "Aspirin",
          doseAmount: 0,
          scheduledTime: new Date().toISOString(),
          status: "pending",
        })
      );

      await assertFails(
        logRef.set({
          id: "log_dose",
          userId: "alice",
          medicationId: "med_1",
          medicationName: "Aspirin",
          doseAmount: 101,
          scheduledTime: new Date().toISOString(),
          status: "pending",
        })
      );
    });

    it("should prevent Update Bypass vulnerability (updating valid doc into invalid schema)", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const medRef = alice.firestore().doc("medications/med_bypass");

      // Step 1: Create a valid doc
      await assertSucceeds(
        medRef.set({
          id: "med_bypass",
          userId: "alice",
          name: "Original Name",
          strength: "500mg",
          doseAmount: 1,
          createdAt: new Date().toISOString(),
        })
      );

      // Step 2: Attempt to update with empty/invalid name
      await assertFails(
        medRef.update({
          name: "",
        })
      );

      // Step 3: Attempt to update with invalid doseAmount > 100
      await assertFails(
        medRef.update({
          doseAmount: 150,
        })
      );
    });

    it("should allow medication alarmSoundId, customSoundPath, and vibrationEnabled within bounds and reject invalid types/sizes", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const db = alice.firestore();
      const medRef = db.doc("medications/med_alarm_fields");
      const now = new Date().toISOString();

      // Create with valid alarm fields (including nullable customSoundPath)
      await assertSucceeds(
        medRef.set({
          id: "med_alarm_fields",
          userId: "alice",
          name: "Losartan",
          strength: "50mg",
          doseAmount: 1,
          alarmSoundId: "gentle_chime",
          customSoundPath: null,
          vibrationEnabled: true,
          createdAt: now,
        })
      );

      // Update with valid customSoundPath and toggled vibrationEnabled
      await assertSucceeds(
        medRef.update({
          alarmSoundId: "custom_alarm_1",
          customSoundPath: "/data/user/0/com.remedytrack/files/alarm.mp3",
          vibrationEnabled: false,
          updatedAt: new Date().toISOString(),
        })
      );

      // Reject non-bool vibrationEnabled on update and create
      await assertFails(
        medRef.update({
          vibrationEnabled: "true",
        })
      );
      await assertFails(
        db.doc("medications/med_bad_vib").set({
          id: "med_bad_vib",
          userId: "alice",
          name: "Losartan",
          strength: "50mg",
          doseAmount: 1,
          vibrationEnabled: 1,
          createdAt: now,
        })
      );

      // Reject oversized customSoundPath (> 500 chars) on update and create
      await assertFails(
        medRef.update({
          customSoundPath: "p".repeat(501),
        })
      );
      await assertFails(
        db.doc("medications/med_bad_path").set({
          id: "med_bad_path",
          userId: "alice",
          name: "Losartan",
          strength: "50mg",
          doseAmount: 1,
          customSoundPath: "p".repeat(501),
          createdAt: now,
        })
      );

      // Reject oversized alarmSoundId (> 100 chars)
      await assertFails(
        medRef.update({
          alarmSoundId: "s".repeat(101),
        })
      );
    });

    it("should allow worst-case fully populated medication + schedule and nullable fields on create and update under the 1000-expression limit", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const db = alice.firestore();
      const now = new Date().toISOString();
      const fullSchedule = {
        frequency: "specificWeekdays",
        timesOfDay: Array.from({ length: 12 }, (_, i) => `${String(i + 8).padStart(2, "0")}:00`),
        weekdays: [1, 2, 3, 4, 5, 6, 7],
        intervalValue: 2,
        cycleActiveDays: 21,
        cycleRestDays: 7,
        startDate: now,
        endDate: now,
        updatedAt: now,
        alarmSoundId: "remedy_alarm_classic",
        customSoundPath: "/data/user/0/com.remedytrack/files/custom_alarm.mp3",
        vibrationEnabled: true,
      };
      const fullMedication = {
        id: "med_worst_case",
        userId: "alice",
        name: "Amoxicillin Clavulanate Potassium",
        genericName: "Amoxicillin + Clavulanic Acid",
        strength: "875mg/125mg",
        form: "tablet",
        doseAmount: 1.5,
        instructions: "Take with a full glass of water at the start of a meal.",
        notes: "Finish entire prescribed course even if symptoms improve early.",
        colorTag: 0xff1e66f5,
        iconTag: "pill",
        isPrn: false,
        minIntervalHours: 8,
        dailyMaxDose: 3,
        schedule: fullSchedule,
        alarmSoundId: "remedy_alarm_classic",
        customSoundPath: "/data/user/0/com.remedytrack/files/custom_alarm.mp3",
        vibrationEnabled: true,
        isActive: true,
        createdAt: now,
        updatedAt: now,
      };

      const fullRef = db.doc("medications/med_worst_case");
      await assertSucceeds(fullRef.set(fullMedication));
      await assertSucceeds(
        fullRef.update({
          ...fullMedication,
          name: "Amoxicillin Updated",
          schedule: {
            ...fullSchedule,
            frequency: "cycleBased",
            updatedAt: Timestamp.now(),
          },
          updatedAt: Timestamp.now(),
        })
      );

      // Nullable notes, instructions, and schedule.updatedAt on create and update
      const nullableRef = db.doc("medications/med_nullable_fields");
      await assertSucceeds(
        nullableRef.set({
          id: "med_nullable_fields",
          userId: "alice",
          name: "Metformin",
          strength: "500mg",
          doseAmount: 1,
          notes: null,
          instructions: null,
          colorTag: null,
          schedule: {
            frequency: "daily",
            timesOfDay: ["08:00"],
            weekdays: [],
            intervalValue: null,
            cycleActiveDays: null,
            cycleRestDays: null,
            startDate: now,
            endDate: null,
            updatedAt: null,
            alarmSoundId: null,
            customSoundPath: null,
            vibrationEnabled: null,
          },
          createdAt: now,
          updatedAt: null,
        })
      );
      await assertSucceeds(
        nullableRef.update({
          notes: null,
          instructions: null,
          schedule: {
            frequency: "everyXDays",
            timesOfDay: ["09:00"],
            weekdays: [],
            intervalValue: 2,
            startDate: now,
            endDate: null,
            updatedAt: null,
          },
          updatedAt: now,
        })
      );
    });

    it("should reject invalid medication schedule fields (bad frequency, >12 timesOfDay, invalid keys, invalid weekdays)", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const db = alice.firestore();
      const now = new Date().toISOString();
      const baseSched = {
        frequency: "daily",
        timesOfDay: ["08:00"],
        startDate: now,
      };
      const baseMed = {
        id: "med_sched_guard",
        userId: "alice",
        name: "Atorvastatin",
        strength: "20mg",
        doseAmount: 1,
        schedule: baseSched,
        createdAt: now,
      };

      await assertSucceeds(db.doc("medications/med_sched_guard").set(baseMed));

      // Bad frequency (string and non-string)
      await assertFails(
        db.doc("medications/med_bad_freq").set({
          ...baseMed,
          id: "med_bad_freq",
          schedule: { ...baseSched, frequency: "hourly" },
        })
      );
      await assertFails(
        db.doc("medications/med_sched_guard").update({
          schedule: { ...baseSched, frequency: 123 },
        })
      );

      // > 12 timesOfDay and non-string time entry
      await assertFails(
        db.doc("medications/med_bad_times").set({
          ...baseMed,
          id: "med_bad_times",
          schedule: {
            ...baseSched,
            timesOfDay: Array.from({ length: 13 }, (_, i) => `${String(i + 6).padStart(2, "0")}:00`),
          },
        })
      );
      await assertFails(
        db.doc("medications/med_sched_guard").update({
          schedule: { ...baseSched, timesOfDay: [123] },
        })
      );

      // Unknown schedule key & missing startDate
      await assertFails(
        db.doc("medications/med_sched_extra").set({
          ...baseMed,
          id: "med_sched_extra",
          schedule: { ...baseSched, extraKey: "unexpected" },
        })
      );
      await assertFails(
        db.doc("medications/med_sched_no_start").set({
          ...baseMed,
          id: "med_sched_no_start",
          schedule: { frequency: "daily", timesOfDay: ["08:00"] },
        })
      );

      // Out-of-range weekdays & > 7 entries
      await assertFails(
        db.doc("medications/med_sched_guard").update({
          schedule: { ...baseSched, weekdays: [0] },
        })
      );
      await assertFails(
        db.doc("medications/med_sched_guard").update({
          schedule: { ...baseSched, weekdays: [1, 2, 3, 4, 5, 6, 7, 1] },
        })
      );
    });

    it("should allow intake log snoozeCount in 0..10 and reject negative, >10, or non-numeric values", async () => {
      const alice = testEnv.authenticatedContext("alice", { email_verified: true });
      const db = alice.firestore();
      const logRef = db.doc("intake_logs/log_snooze");
      const scheduled = new Date().toISOString();

      // Create with snoozeCount: 0
      await assertSucceeds(
        logRef.set({
          id: "log_snooze",
          userId: "alice",
          medicationId: "med_1",
          medicationName: "Losartan",
          doseAmount: 1,
          scheduledTime: scheduled,
          status: "snoozed",
          snoozeCount: 0,
        })
      );

      // Update with snoozeCount: 10 (upper bound)
      await assertSucceeds(
        logRef.update({
          snoozeCount: 10,
          snoozeUntil: new Date().toISOString(),
        })
      );

      // Reject negative snoozeCount on create and update
      await assertFails(
        logRef.update({
          snoozeCount: -1,
        })
      );
      await assertFails(
        db.doc("intake_logs/log_snooze_neg").set({
          id: "log_snooze_neg",
          userId: "alice",
          medicationId: "med_1",
          medicationName: "Losartan",
          doseAmount: 1,
          scheduledTime: scheduled,
          status: "snoozed",
          snoozeCount: -1,
        })
      );

      // Reject snoozeCount > 10 on create and update
      await assertFails(
        logRef.update({
          snoozeCount: 11,
        })
      );
      await assertFails(
        db.doc("intake_logs/log_snooze_over").set({
          id: "log_snooze_over",
          userId: "alice",
          medicationId: "med_1",
          medicationName: "Losartan",
          doseAmount: 1,
          scheduledTime: scheduled,
          status: "snoozed",
          snoozeCount: 11,
        })
      );

      // Reject non-numeric snoozeCount
      await assertFails(
        logRef.update({
          snoozeCount: "2",
        })
      );
    });
  });

  // =========================================================================
  // 7. Root Default Deny & Server-Only Collections
  // =========================================================================
  describe("7. Root Default Deny & Server-Only Collections", () => {
    it("should deny client access to otp_challenges", async () => {
      const alice = testEnv.authenticatedContext("alice");
      const db = alice.firestore();

      await assertFails(db.doc("otp_challenges/alice").get());
      await assertFails(
        db.doc("otp_challenges/alice").set({
          email: "alice@example.com",
          code: "123456",
        })
      );
    });

    it("should deny client access to removed appointments collection via default-deny", async () => {
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("appointments/alice_app").set({
          id: "alice_app",
          userId: "alice",
          doctorName: "Dr. Gomez",
          dateTime: new Date().toISOString(),
        });
      });

      const aliceDb = testEnv.authenticatedContext("alice").firestore();
      const appRef = aliceDb.doc("appointments/alice_app");

      await assertFails(appRef.get());
      await assertFails(
        aliceDb.doc("appointments/new_app").set({
          id: "new_app",
          userId: "alice",
          doctorName: "Dr. Santos",
          dateTime: new Date().toISOString(),
        })
      );
      await assertFails(appRef.update({ doctorName: "Dr. Updated" }));
      await assertFails(appRef.delete());
    });

    it("should block reads and writes to arbitrary undefined collections", async () => {
      const alice = testEnv.authenticatedContext("alice");
      const db = alice.firestore();

      await assertFails(db.doc("arbitrary_collection/random_doc").get());
      await assertFails(
        db.doc("arbitrary_collection/random_doc").set({ data: "payload" })
      );

      await assertFails(db.doc("system_config/secrets").get());
      await assertFails(db.doc("admin/users").get());
    });
  });

  // =========================================================================
  // 8. Cloud Function Server-Written Fields & Client Sync Hardening
  // =========================================================================
  describe("8. Cloud Function Server-Written Fields & Client Sync Hardening", () => {
    it("should allow patient to merge-update intake_logs that already contain server-written escalation and reconciliation fields", async () => {
      const nowIso = new Date().toISOString();
      const serverAlertTs = Timestamp.fromMillis(Date.now() - 120000);
      const serverReconcileTs = Timestamp.fromMillis(Date.now() - 60000);

      // Seed intake log with fields written by checkMissedDosesAndAlertCaregivers / scheduledMissedDoseReconciliation
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("intake_logs/log_server_reconciled").set({
          id: "log_server_reconciled",
          userId: "alice",
          medicationId: "med_123",
          medicationName: "Amlodipine",
          doseAmount: 1,
          scheduledTime: nowIso,
          recordedTime: nowIso,
          status: "missed",
          snoozeCount: 0,
          isPrn: false,
          caregiverAlertSent: true,
          alertSentAt: serverAlertTs,
          reconciledAt: serverReconcileTs,
          reconciledBy: "server_scheduler",
        });
      });

      const aliceDb = testEnv.authenticatedContext("alice", { email_verified: true }).firestore();
      const logRef = aliceDb.doc("intake_logs/log_server_reconciled");

      // Late correction / offline sync via SetOptions(merge: true) without touching server fields
      await assertSucceeds(
        logRef.set(
          {
            id: "log_server_reconciled",
            userId: "alice",
            medicationId: "med_123",
            medicationName: "Amlodipine",
            doseAmount: 1,
            scheduledTime: nowIso,
            recordedTime: new Date().toISOString(),
            status: "late",
            snoozeUntil: null,
            snoozeCount: 0,
            notes: "Late correction: Confirmed as taken after missing alarm",
            isPrn: false,
            updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
          },
          { merge: true }
        )
      );

      // Direct partial .update() on client-owned status/notes also succeeds
      await assertSucceeds(
        logRef.update({
          notes: "Updated note after sync",
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );

      const updatedSnap = await assertSucceeds(logRef.get());
      assert.strictEqual(updatedSnap.data().status, "late");
      assert.strictEqual(updatedSnap.data().caregiverAlertSent, true);
      assert.strictEqual(updatedSnap.data().reconciledBy, "server_scheduler");
    });

    it("should block patient from forging or tampering with server-written intake_logs fields on create and update", async () => {
      const aliceDb = testEnv.authenticatedContext("alice", { email_verified: true }).firestore();
      const nowIso = new Date().toISOString();
      const nowTs = Timestamp.now();

      // Cannot forge caregiverAlertSent: true on create
      await assertFails(
        aliceDb.doc("intake_logs/log_forge_alert").set({
          id: "log_forge_alert",
          userId: "alice",
          medicationId: "med_123",
          medicationName: "Amlodipine",
          doseAmount: 1,
          scheduledTime: nowIso,
          status: "pending",
          caregiverAlertSent: true,
        })
      );

      // Cannot forge caregiverAlertSent: false or alertSentAt on create
      await assertFails(
        aliceDb.doc("intake_logs/log_forge_alert_false").set({
          id: "log_forge_alert_false",
          userId: "alice",
          medicationId: "med_123",
          medicationName: "Amlodipine",
          doseAmount: 1,
          scheduledTime: nowIso,
          status: "pending",
          caregiverAlertSent: false,
          alertSentAt: nowTs,
        })
      );

      // Cannot spoof reconciledBy or reconciledAt on create
      await assertFails(
        aliceDb.doc("intake_logs/log_spoof_reconcile").set({
          id: "log_spoof_reconcile",
          userId: "alice",
          medicationId: "med_123",
          medicationName: "Amlodipine",
          doseAmount: 1,
          scheduledTime: nowIso,
          status: "missed",
          reconciledBy: "server_scheduler",
          reconciledAt: nowTs,
        })
      );

      // Create a normal client log first, then attempt update tampering
      const clientLogRef = aliceDb.doc("intake_logs/log_client_normal");
      await assertSucceeds(
        clientLogRef.set({
          id: "log_client_normal",
          userId: "alice",
          medicationId: "med_123",
          medicationName: "Amlodipine",
          doseAmount: 1,
          scheduledTime: nowIso,
          status: "pending",
        })
      );

      await assertFails(clientLogRef.update({ caregiverAlertSent: true }));
      await assertFails(clientLogRef.update({ reconciledBy: "server_scheduler" }));
      await assertFails(clientLogRef.update({ alertSentAt: nowTs }));
      await assertFails(clientLogRef.update({ reconciledAt: nowTs }));

      // Also seed a server-reconciled doc and verify patient cannot alter or delete server fields
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("intake_logs/log_tamper_server").set({
          id: "log_tamper_server",
          userId: "alice",
          medicationId: "med_123",
          medicationName: "Amlodipine",
          doseAmount: 1,
          scheduledTime: nowIso,
          status: "missed",
          caregiverAlertSent: true,
          alertSentAt: nowTs,
          reconciledAt: nowTs,
          reconciledBy: "server_scheduler",
        });
      });

      const serverLogRef = aliceDb.doc("intake_logs/log_tamper_server");
      await assertFails(serverLogRef.update({ caregiverAlertSent: false }));
      await assertFails(serverLogRef.update({ reconciledBy: "patient_override" }));
      await assertFails(
        serverLogRef.update({
          reconciledBy: firebase.firestore.FieldValue.delete(),
        })
      );
    });

    it("should allow user to update own users/{uid} when fcmTokens, timezoneOffsetMinutes, quietHours, and privacy flags are present while blocking tampering with server-managed fields", async () => {
      const nowIso = new Date().toISOString();
      const verifiedTs = Timestamp.fromMillis(Date.now() - 60000);

      // Seed user profile containing Cloud-Function-managed and notification preference fields
      await testEnv.withSecurityRulesDisabled(async (context) => {
        await context.firestore().doc("users/alice").set({
          id: "alice",
          email: "alice@example.com",
          displayName: "Alice Reyes",
          createdAt: nowIso,
          emailOtpVerified: true,
          emailVerifiedAt: verifiedTs,
          caregiverIds: ["carol"],
          dependentIds: [],
          fcmToken: "token_primary_1",
          fcmTokens: ["token_primary_1", "token_tablet_2"],
          caregiverNotificationEnabled: true,
          timezoneOffsetMinutes: 480,
          quietHoursStart: "22:00",
          quietHoursEnd: "07:00",
          shareMedicationNamesWithCaregivers: false,
        });
      });

      const aliceDb = testEnv.authenticatedContext("alice").firestore();
      const userRef = aliceDb.doc("users/alice");

      // FcmService token refresh update succeeds while fcmTokens & emailVerifiedAt remain intact
      await assertSucceeds(
        userRef.update({
          fcmToken: "token_refreshed_3",
          updatedAt: firebase.firestore.FieldValue.serverTimestamp(),
        })
      );

      // User preference merge update succeeds
      await assertSucceeds(
        userRef.set(
          {
            displayName: "Alice Reyes-Santos",
            timezoneOffsetMinutes: -480,
            quietHoursStart: "23:00",
            quietHoursEnd: "06:30",
            shareMedicationNamesWithCaregivers: true,
            updatedAt: new Date().toISOString(),
          },
          { merge: true }
        )
      );

      // Owner CANNOT tamper with server-managed fcmTokens or emailVerifiedAt
      await assertFails(userRef.update({ fcmTokens: ["spoofed_token"] }));
      await assertFails(userRef.update({ fcmTokens: [] }));
      await assertFails(userRef.update({ emailVerifiedAt: Timestamp.now() }));

      // Owner CANNOT write out-of-bounds or invalid types for new preference fields
      await assertFails(userRef.update({ timezoneOffsetMinutes: 1000 }));
      await assertFails(userRef.update({ timezoneOffsetMinutes: -900 }));
      await assertFails(userRef.update({ quietHoursStart: "25:99" }));
      await assertFails(userRef.update({ quietHoursEnd: "a".repeat(20) }));
      await assertFails(
        userRef.update({ shareMedicationNamesWithCaregivers: "yes" })
      );

      // New user CANNOT pre-populate fcmTokens or emailVerifiedAt on create
      const bobDb = testEnv.authenticatedContext("bob").firestore();
      await assertFails(
        bobDb.doc("users/bob").set({
          id: "bob",
          email: "bob@example.com",
          displayName: "Bob Cruz",
          createdAt: nowIso,
          fcmTokens: ["forged_token"],
        })
      );
      await assertFails(
        bobDb.doc("users/bob").set({
          id: "bob",
          email: "bob@example.com",
          displayName: "Bob Cruz",
          createdAt: nowIso,
          emailVerifiedAt: Timestamp.now(),
        })
      );
    });
  });
});

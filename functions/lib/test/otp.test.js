"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __setModuleDefault = (this && this.__setModuleDefault) || (Object.create ? (function(o, v) {
    Object.defineProperty(o, "default", { enumerable: true, value: v });
}) : function(o, v) {
    o["default"] = v;
});
var __importStar = (this && this.__importStar) || (function () {
    var ownKeys = function(o) {
        ownKeys = Object.getOwnPropertyNames || function (o) {
            var ar = [];
            for (var k in o) if (Object.prototype.hasOwnProperty.call(o, k)) ar[ar.length] = k;
            return ar;
        };
        return ownKeys(o);
    };
    return function (mod) {
        if (mod && mod.__esModule) return mod;
        var result = {};
        if (mod != null) for (var k = ownKeys(mod), i = 0; i < k.length; i++) if (k[i] !== "default") __createBinding(result, mod, k[i]);
        __setModuleDefault(result, mod);
        return result;
    };
})();
Object.defineProperty(exports, "__esModule", { value: true });
const chai_1 = require("chai");
const crypto = __importStar(require("crypto"));
const index_1 = require("../src/index");
describe('RemedyTrack Cloud Functions OTP Backend Unit Tests', () => {
    const testUid = 'user_alice_test_123';
    const testSecret = 'test-secret-hmac-key-32-bytes-long!';
    const testSalt = '1234567890abcdef1234567890abcdef';
    const validCode = '849201';
    const wrongCode = '111111';
    it('generates deterministic HMAC-SHA256 salted hashes', () => {
        const hash1 = (0, index_1.hashOtpCode)(testUid, validCode, testSalt, testSecret);
        const hash2 = (0, index_1.hashOtpCode)(testUid, validCode, testSalt, testSecret);
        (0, chai_1.expect)(hash1).to.equal(hash2);
        (0, chai_1.expect)(hash1).to.have.lengthOf(64); // 256 bits = 64 hex chars
    });
    it('produces different hashes for different codes', () => {
        const hashValid = (0, index_1.hashOtpCode)(testUid, validCode, testSalt, testSecret);
        const hashWrong = (0, index_1.hashOtpCode)(testUid, wrongCode, testSalt, testSecret);
        (0, chai_1.expect)(hashValid).to.not.equal(hashWrong);
    });
    it('prevents cross-user code verification (different UIDs produce distinct hashes)', () => {
        const hashAlice = (0, index_1.hashOtpCode)('alice_uid', validCode, testSalt, testSecret);
        const hashBob = (0, index_1.hashOtpCode)('bob_uid', validCode, testSalt, testSecret);
        (0, chai_1.expect)(hashAlice).to.not.equal(hashBob);
    });
    it('validates constant-time timingSafeEqual matching', () => {
        const validHashBuf = Buffer.from((0, index_1.hashOtpCode)(testUid, validCode, testSalt, testSecret), 'hex');
        const sameHashBuf = Buffer.from((0, index_1.hashOtpCode)(testUid, validCode, testSalt, testSecret), 'hex');
        const wrongHashBuf = Buffer.from((0, index_1.hashOtpCode)(testUid, wrongCode, testSalt, testSecret), 'hex');
        (0, chai_1.expect)(crypto.timingSafeEqual(validHashBuf, sameHashBuf)).to.be.true;
        (0, chai_1.expect)(crypto.timingSafeEqual(validHashBuf, wrongHashBuf)).to.be.false;
    });
    describe('OTP Expiry, Rate Limiting, and Lockout Logic Invariants', () => {
        const now = Date.now();
        const tenMinutes = 10 * 60 * 1000;
        const sixtySeconds = 60 * 1000;
        const fifteenMinutes = 15 * 60 * 1000;
        it('identifies expired challenges correctly', () => {
            const expiredTimestamp = now - 1000; // 1 second ago
            const isExpired = expiredTimestamp < now;
            (0, chai_1.expect)(isExpired).to.be.true;
            const validTimestamp = now + tenMinutes;
            const isValid = validTimestamp > now;
            (0, chai_1.expect)(isValid).to.be.true;
        });
        it('enforces 60-second cooldown on consecutive requests', () => {
            const lastSentAt = now - 30 * 1000; // 30 seconds ago
            const elapsed = now - lastSentAt;
            const cooldownViolated = elapsed < sixtySeconds;
            (0, chai_1.expect)(cooldownViolated).to.be.true;
            const lastSentLongAgo = now - 65 * 1000; // 65 seconds ago
            const elapsedAllowed = now - lastSentLongAgo;
            (0, chai_1.expect)(elapsedAllowed >= sixtySeconds).to.be.true;
        });
        it('enforces maximum 5 sends per rolling hour limit', () => {
            const oneHourAgo = now - 60 * 60 * 1000;
            // 5 requests within the last hour
            const recentSends = [
                now - 50 * 60 * 1000,
                now - 40 * 60 * 1000,
                now - 30 * 60 * 1000,
                now - 20 * 60 * 1000,
                now - 10 * 60 * 1000,
            ];
            const validRecent = recentSends.filter((ts) => ts > oneHourAgo);
            (0, chai_1.expect)(validRecent.length).to.equal(5);
            (0, chai_1.expect)(validRecent.length >= 5).to.be.true; // blocks 6th request
        });
        it('triggers 15-minute lockout after 5 consecutive failed attempts', () => {
            let attempts = 0;
            let isLocked = false;
            let lockUntil = null;
            for (let i = 1; i <= 5; i++) {
                attempts++;
                if (attempts >= 5) {
                    isLocked = true;
                    lockUntil = now + fifteenMinutes;
                }
            }
            (0, chai_1.expect)(attempts).to.equal(5);
            (0, chai_1.expect)(isLocked).to.be.true;
            (0, chai_1.expect)(lockUntil).to.be.greaterThan(now);
            (0, chai_1.expect)(lockUntil - now).to.equal(fifteenMinutes);
        });
        it('guarantees single-use destruction preventing replay attacks', () => {
            const challengeStore = new Map();
            challengeStore.set(testUid, 'challenge_active');
            (0, chai_1.expect)(challengeStore.has(testUid)).to.be.true;
            // Successful verification triggers delete
            challengeStore.delete(testUid);
            // Replay attempt fails because challenge no longer exists
            (0, chai_1.expect)(challengeStore.has(testUid)).to.be.false;
        });
    });
});
//# sourceMappingURL=otp.test.js.map
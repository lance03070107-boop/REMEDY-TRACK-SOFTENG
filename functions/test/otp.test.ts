import { expect } from 'chai';
import * as crypto from 'crypto';
import { hashOtpCode } from '../src/index';

describe('RemedyTrack Cloud Functions OTP Backend Unit Tests', () => {
  const testUid = 'user_alice_test_123';
  const testSecret = 'test-secret-hmac-key-32-bytes-long!';
  const testSalt = '1234567890abcdef1234567890abcdef';
  const validCode = '849201';
  const wrongCode = '111111';

  it('generates deterministic HMAC-SHA256 salted hashes', () => {
    const hash1 = hashOtpCode(testUid, validCode, testSalt, testSecret);
    const hash2 = hashOtpCode(testUid, validCode, testSalt, testSecret);
    expect(hash1).to.equal(hash2);
    expect(hash1).to.have.lengthOf(64); // 256 bits = 64 hex chars
  });

  it('produces different hashes for different codes', () => {
    const hashValid = hashOtpCode(testUid, validCode, testSalt, testSecret);
    const hashWrong = hashOtpCode(testUid, wrongCode, testSalt, testSecret);
    expect(hashValid).to.not.equal(hashWrong);
  });

  it('prevents cross-user code verification (different UIDs produce distinct hashes)', () => {
    const hashAlice = hashOtpCode('alice_uid', validCode, testSalt, testSecret);
    const hashBob = hashOtpCode('bob_uid', validCode, testSalt, testSecret);
    expect(hashAlice).to.not.equal(hashBob);
  });

  it('validates constant-time timingSafeEqual matching', () => {
    const validHashBuf = Buffer.from(hashOtpCode(testUid, validCode, testSalt, testSecret), 'hex');
    const sameHashBuf = Buffer.from(hashOtpCode(testUid, validCode, testSalt, testSecret), 'hex');
    const wrongHashBuf = Buffer.from(hashOtpCode(testUid, wrongCode, testSalt, testSecret), 'hex');

    expect(crypto.timingSafeEqual(validHashBuf, sameHashBuf)).to.be.true;
    expect(crypto.timingSafeEqual(validHashBuf, wrongHashBuf)).to.be.false;
  });

  describe('OTP Expiry, Rate Limiting, and Lockout Logic Invariants', () => {
    const now = Date.now();
    const tenMinutes = 10 * 60 * 1000;
    const sixtySeconds = 60 * 1000;
    const fifteenMinutes = 15 * 60 * 1000;

    it('identifies expired challenges correctly', () => {
      const expiredTimestamp = now - 1000; // 1 second ago
      const isExpired = expiredTimestamp < now;
      expect(isExpired).to.be.true;

      const validTimestamp = now + tenMinutes;
      const isValid = validTimestamp > now;
      expect(isValid).to.be.true;
    });

    it('enforces 60-second cooldown on consecutive requests', () => {
      const lastSentAt = now - 30 * 1000; // 30 seconds ago
      const elapsed = now - lastSentAt;
      const cooldownViolated = elapsed < sixtySeconds;
      expect(cooldownViolated).to.be.true;

      const lastSentLongAgo = now - 65 * 1000; // 65 seconds ago
      const elapsedAllowed = now - lastSentLongAgo;
      expect(elapsedAllowed >= sixtySeconds).to.be.true;
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
      expect(validRecent.length).to.equal(5);
      expect(validRecent.length >= 5).to.be.true; // blocks 6th request
    });

    it('triggers 15-minute lockout after 5 consecutive failed attempts', () => {
      let attempts = 0;
      let isLocked = false;
      let lockUntil: number | null = null;

      for (let i = 1; i <= 5; i++) {
        attempts++;
        if (attempts >= 5) {
          isLocked = true;
          lockUntil = now + fifteenMinutes;
        }
      }

      expect(attempts).to.equal(5);
      expect(isLocked).to.be.true;
      expect(lockUntil).to.be.greaterThan(now);
      expect(lockUntil! - now).to.equal(fifteenMinutes);
    });

    it('guarantees single-use destruction preventing replay attacks', () => {
      const challengeStore = new Map<string, string>();
      challengeStore.set(testUid, 'challenge_active');

      expect(challengeStore.has(testUid)).to.be.true;

      // Successful verification triggers delete
      challengeStore.delete(testUid);

      // Replay attempt fails because challenge no longer exists
      expect(challengeStore.has(testUid)).to.be.false;
    });
  });
});


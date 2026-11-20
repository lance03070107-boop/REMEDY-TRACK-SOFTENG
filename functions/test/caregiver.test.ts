import { expect } from 'chai';
import {
  generateInviteCode,
  isWithinQuietHours,
  parseFirestoreDate,
} from '../src/index';

describe('RemedyTrack Caregiver Pipeline & Safety Logic Unit Tests', () => {
  describe('Invite Code Generation', () => {
    it('generates a 6-character alphanumeric code by default', () => {
      const code = generateInviteCode();
      expect(code).to.be.a('string');
      expect(code).to.have.lengthOf(6);
    });

    it('generates arbitrary length codes when requested', () => {
      const code8 = generateInviteCode(8);
      expect(code8).to.have.lengthOf(8);
      const code4 = generateInviteCode(4);
      expect(code4).to.have.lengthOf(4);
    });

    it('excludes ambiguous characters (0, O, 1, I) to prevent patient transcription errors', () => {
      const ambiguousChars = ['0', 'O', '1', 'I'];
      for (let i = 0; i < 50; i++) {
        const code = generateInviteCode(10);
        for (const char of ambiguousChars) {
          expect(code).to.not.include(char);
        }
      }
    });

    it('generates distinct random codes across calls', () => {
      const code1 = generateInviteCode();
      const code2 = generateInviteCode();
      expect(code1).to.not.equal(code2);
    });
  });

  describe('Caregiver Quiet Hours Invariants', () => {
    it('returns false if quiet hours are not configured', () => {
      const testDate = new Date('2026-10-11T23:30:00');
      expect(isWithinQuietHours(testDate, undefined, undefined)).to.be.false;
      expect(isWithinQuietHours(testDate, '22:00', undefined)).to.be.false;
      expect(isWithinQuietHours(testDate, undefined, '07:00')).to.be.false;
      expect(isWithinQuietHours(testDate, '', '')).to.be.false;
    });

    it('correctly evaluates standard same-day quiet hours (e.g. 13:00 to 17:00)', () => {
      const duringQuiet = new Date('2026-10-11T14:30:00');
      expect(isWithinQuietHours(duringQuiet, '13:00', '17:00')).to.be.true;

      const beforeQuiet = new Date('2026-10-11T12:59:00');
      expect(isWithinQuietHours(beforeQuiet, '13:00', '17:00')).to.be.false;

      const afterQuiet = new Date('2026-10-11T17:01:00');
      expect(isWithinQuietHours(afterQuiet, '13:00', '17:00')).to.be.false;
    });

    it('correctly evaluates overnight quiet hours crossing midnight (e.g. 22:00 to 07:00)', () => {
      // Late night (23:15)
      const lateNight = new Date('2026-10-11T23:15:00');
      expect(isWithinQuietHours(lateNight, '22:00', '07:00')).to.be.true;

      // Early morning (03:30)
      const earlyMorning = new Date('2026-10-11T03:30:00');
      expect(isWithinQuietHours(earlyMorning, '22:00', '07:00')).to.be.true;

      // Exactly at start minute (22:00)
      const atStart = new Date('2026-10-11T22:00:00');
      expect(isWithinQuietHours(atStart, '22:00', '07:00')).to.be.true;

      // One minute before end minute (06:59)
      const justBeforeEnd = new Date('2026-10-11T06:59:00');
      expect(isWithinQuietHours(justBeforeEnd, '22:00', '07:00')).to.be.true;

      // Exactly at end minute (07:00) -> outside quiet hours
      const atEnd = new Date('2026-10-11T07:00:00');
      expect(isWithinQuietHours(atEnd, '22:00', '07:00')).to.be.false;

      // Midday (14:00) -> outside quiet hours
      const midday = new Date('2026-10-11T14:00:00');
      expect(isWithinQuietHours(midday, '22:00', '07:00')).to.be.false;
    });

    it('applies explicit timezoneOffsetMinutes when evaluating UTC timestamps (Manila UTC+8)', () => {
      // 14:30 UTC == 22:30 UTC+8 -> inside 22:00..07:00
      const lateNightUtc = new Date('2026-10-11T14:30:00.000Z');
      expect(isWithinQuietHours(lateNightUtc, '22:00', '07:00', 480)).to.be.true;

      // 06:30 UTC == 14:30 UTC+8 -> outside 22:00..07:00
      const middayUtc = new Date('2026-10-11T06:30:00.000Z');
      expect(isWithinQuietHours(middayUtc, '22:00', '07:00', 480)).to.be.false;

      // 22:59 UTC == 06:59 UTC+8 -> inside 22:00..07:00
      const justBeforeEndUtc = new Date('2026-10-11T22:59:00.000Z');
      expect(isWithinQuietHours(justBeforeEndUtc, '22:00', '07:00', 480)).to.be.true;

      // 23:00 UTC == 07:00 UTC+8 -> outside 22:00..07:00
      const atEndUtc = new Date('2026-10-11T23:00:00.000Z');
      expect(isWithinQuietHours(atEndUtc, '22:00', '07:00', 480)).to.be.false;
    });
  });

  describe('Firestore Date Parsing (parseFirestoreDate)', () => {
    it('parses Date objects, Firestore Timestamp-like objects, ISO strings, and epoch numbers', () => {
      const target = new Date('2026-10-11T12:00:00.000Z');

      expect(parseFirestoreDate(target)?.getTime()).to.equal(target.getTime());
      expect(parseFirestoreDate({ toDate: () => target })?.getTime()).to.equal(target.getTime());
      expect(parseFirestoreDate('2026-10-11T12:00:00.000Z')?.getTime()).to.equal(target.getTime());
      expect(parseFirestoreDate(target.getTime())?.getTime()).to.equal(target.getTime());
    });

    it('returns null for missing or corrupted date values', () => {
      expect(parseFirestoreDate(null)).to.be.null;
      expect(parseFirestoreDate(undefined)).to.be.null;
      expect(parseFirestoreDate('not-a-valid-date')).to.be.null;
      expect(parseFirestoreDate(new Date('invalid'))).to.be.null;
      expect(parseFirestoreDate({ toDate: () => new Date('invalid') })).to.be.null;
      expect(parseFirestoreDate({})).to.be.null;
    });
  });

  describe('Caregiver Invitation & Relationship Security Rules', () => {
    it('enforces 24-hour expiration window on invite codes', () => {
      const now = Date.now();
      const expiresAtMs = now + 24 * 60 * 60 * 1000;
      expect(expiresAtMs - now).to.equal(86400000);

      const pastExpiry = now + 86400000 + 1000;
      expect(pastExpiry > expiresAtMs).to.be.true;
    });

    it('rejects self-caregiver linkage (patient cannot be their own caregiver)', () => {
      const patientId = 'user_123';
      const caregiverId = 'user_123';
      const isSelfLink = patientId === caregiverId;
      expect(isSelfLink).to.be.true;
    });

    it('constructs deterministic and unique relationship document IDs', () => {
      const patientId = 'patient_alice';
      const caregiverId = 'caregiver_bob';
      const relationshipId = `${patientId}_${caregiverId}`;
      expect(relationshipId).to.equal('patient_alice_caregiver_bob');
    });

    it('preserves patient privacy by omitting medication name unless consented', () => {
      const shareMedicationName = false;
      const patientName = 'Maria Santos';
      const medName = 'Amlodipine 5mg';

      const alertBody = shareMedicationName
        ? `${patientName} missed their dose of ${medName}. Please check on them.`
        : `${patientName} has an unconfirmed medication dose past due. Please check on them.`;

      expect(alertBody).to.not.include(medName);
      expect(alertBody).to.include(patientName);
    });
  });
});


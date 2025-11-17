// backend/src/services/sms.js
// Minimal stub SMS sender. Replace with Twilio/Vonage/etc. later.
module.exports = {
  /**
   * sendInvite({ to, text, joinUrl, inviterId, outingId, code })
   */
  async sendInvite(payload) {
    const { to, text, joinUrl, inviterId, outingId, code } = payload || {};
    // eslint-disable-next-line no-console
    console.log('📱 [SMS STUB] To:', to, '| Text:', text, '| Join:', joinUrl, '| inviter:', inviterId, '| outing:', outingId, '| code:', code);
    return true;
  },
};

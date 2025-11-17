// backend/src/services/mailer.js
// Minimal stub mailer. Replace with nodemailer / provider of choice later.
module.exports = {
  /**
   * sendInvite({ to, subject, text, joinUrl, inviterId, outingId, code })
   */
  async sendInvite(payload) {
    const { to, subject, text, joinUrl, inviterId, outingId, code } = payload || {};
    // eslint-disable-next-line no-console
    console.log('📧 [MAIL STUB] To:', to, '| Subject:', subject, '| Text:', text, '| Join:', joinUrl, '| inviter:', inviterId, '| outing:', outingId, '| code:', code);
    return true;
  },
};

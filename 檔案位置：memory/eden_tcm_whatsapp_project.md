# Eden TCM WhatsApp / Railway Memory

## 2026-03-09

### What worked

- Railway deployment is running Chatwoot self-hosted Community edition, not Chatwoot Cloud.
- The dashboard loads normally and conversations are visible.
- A conversation can be opened and replied to from the inbox UI.
- User confirmed the working state with a live screenshot on 2026-03-09.

### Plain-language summary

- No Chatwoot core code change was needed during this check.
- The successful outcome was confirming that the Railway instance is a self-hosted setup that is working end to end for the current inbox flow.
- This setup is not under Chatwoot Cloud paid-plan fair-use rules.
- It is still Community edition, so Enterprise-only features are not automatically unlocked.

### Important reminder for next time

- "Railway self-hosted" means no Chatwoot Cloud SaaS limits, not "everything is unlocked".
- The remaining limits are mainly:
- Community vs Enterprise feature gating inside Chatwoot
- Railway CPU, RAM, disk, network, and billing limits
- Third-party provider limits such as WhatsApp, SMTP, OpenAI, S3, or Twilio

### Quick checks if a similar issue happens again

- Confirm the app loads and conversations list renders.
- Confirm reply/send works inside an inbox conversation.
- Check Railway logs and service health before assuming a Chatwoot code issue.
- Treat the install as self-hosted Community unless there is an explicit Enterprise subscription and image/license setup.

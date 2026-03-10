# Chatwoot Login Runbook

Use this runbook for self-hosted Chatwoot login issues on Railway. It is intended for production triage of web login, mobile login, password reset, and manually-created users.

## Golden Path

1. Confirm the installation URL is the public Chatwoot root such as `https://instance.up.railway.app`.
2. Reproduce on web first at `/app/login`.
3. Capture the exact response from `POST /auth/sign_in`.
4. Inspect Railway variables and logs before changing user records.
5. Prefer Rails builders over raw SQL.
6. Re-test login with `curl -i` and confirm the HTTP status after each fix.

## Environment Checks

Run:

```bash
railway variables --json -s Chatwoot
```

Check these keys first:

- `FRONTEND_URL`
- `ENABLE_ACCOUNT_SIGNUP`
- `SMTP_ADDRESS`
- `MAILER_SENDER_EMAIL`
- `GOOGLE_OAUTH_CLIENT_ID`
- `GOOGLE_OAUTH_CLIENT_SECRET`

If `SMTP_ADDRESS` is blank, Chatwoot falls back to the mailer logic in `config/initializers/mailer.rb`. On Railway this commonly fails with `No such file or directory - /usr/sbin/sendmail`, which means `Forgot your password?` and invite emails will not work.

## Failure Modes

### Wrong Installation URL

Symptoms:

- mobile app says `invalid credentials`
- user entered `railway.com/project/...`

Fix:

- use only the public Chatwoot root URL
- never use the Railway dashboard URL
- do not append `/app` or `/api` in the mobile installation field

### Invalid Credentials Or 401

Common causes:

- wrong password
- wrong instance
- user not confirmed
- user exists in a different workspace or deployment

Rails console checks:

```ruby
u = User.find_by(email: 'user@example.com')
u&.confirmed?
u&.account_users&.pluck(:account_id, :role, :inviter_id)
```

### Forgot Password Email Never Arrives

Common causes:

- SMTP not configured
- account does not exist

Check Railway logs for:

- `ActionMailer`
- `reset_password`
- `No such file or directory - /usr/sbin/sendmail`

### 500 On `/auth/sign_in`

Treat this as a server-side bug, not a password issue.

Check logs with the request id from the failing response. Two known classes of failure:

1. `BCrypt::Errors::InvalidHash`
   Cause: broken `encrypted_password`
   Fix: reset the password through Rails console and save the user again.

2. `ActionView::Template::Error (undefined method 'token' for nil)`
   Cause: the user was created outside model callbacks and has no `access_token`
   Relevant code:
   - `app/views/api/v1/models/_user.json.jbuilder`
   - `app/models/concerns/access_tokenable.rb`
   Fix:

```ruby
u = User.find_by(email: 'user@example.com')
u.create_access_token unless u.access_token
u.reload.access_token.token
```

## Safe Creation And Repair

### Create First Admin And Account

Use `app/builders/account_builder.rb`:

```ruby
AccountBuilder.new(
  account_name: 'Clinic',
  user_full_name: 'Agent Name',
  email: 'user@example.com',
  user_password: 'NEW_PASSWORD',
  confirmed: true
).perform
```

### Add Agent Or Administrator To Existing Account

Use `app/builders/agent_builder.rb`:

```ruby
account = Account.find(ACCOUNT_ID)
inviter = account.administrators.first

AgentBuilder.new(
  email: 'user@example.com',
  name: 'Agent Name',
  inviter: inviter,
  account: account,
  role: :administrator # or :agent
).perform
```

### Reset Password And Confirm User

```ruby
u = User.find_by(email: 'user@example.com')
u.confirm unless u.confirmed?
u.password = 'NEW_PASSWORD'
u.password_confirmation = 'NEW_PASSWORD'
u.save!
```

### Last-Resort SQL

Avoid direct SQL for user creation. If it is unavoidable, verify all of these after insert:

- `provider = 'email'`
- `uid = email`
- `confirmed_at` is set
- `account_users` row exists
- `access_tokens` row exists

Raw SQL bypasses callbacks, so it can leave users in a half-created state even if the row exists.

## Verification

After every repair, verify with:

```bash
curl -i -s -X POST "https://instance.up.railway.app/auth/sign_in" \
  -H 'Content-Type: application/json' \
  -d '{"email":"user@example.com","password":"PASSWORD"}'
```

Expected result:

- `200` means auth succeeded
- `401` usually means credentials or confirmation state
- `500` means inspect logs again before touching more records

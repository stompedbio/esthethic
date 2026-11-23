# skeed server

Relay for the skeed global chat and cloud configs. No dependencies, Node 18+.

    node server.js

Set `ADMIN_KEY` (on Render: Environment > Add Environment Variable) to enable admin commands.
Without it the admin endpoint refuses everything. Pick a long random key and keep it private.

## Admin commands

Send a POST to `/admin` with JSON. Replace the address and key.

    curl -X POST https://YOUR-SERVER/admin -H "Content-Type: application/json" \
      -d '{"key":"YOUR_KEY","action":"mute","name":"SomeUser","minutes":30}'

| action     | fields             | does                                   |
|------------|--------------------|----------------------------------------|
| mute       | name, minutes      | blocks sending for N minutes (max 1440) |
| unmute     | name               | lifts a mute                           |
| ban        | name               | blocks chat and config uploads         |
| unban      | name               | lifts a ban                            |
| clear      | none               | empties the chat history               |
| motd       | text               | message shown to everyone on connect   |
| announce   | text               | posts a message as SERVER              |

Everything lives in memory, so a restart clears chat, cloud configs, mutes, bans and the MOTD.
Nicknames are not accounts: anyone can use any free nickname, and the names
server, admin, system, skeed, owner, mod and moderator are reserved.

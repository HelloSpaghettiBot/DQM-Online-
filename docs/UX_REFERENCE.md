# Online adventure flow

The owner's reference is PokeMMO's account-based online experience. Its official
[download guide](https://pokemmo.com/en/downloads/) requires an account and local
ROM selection. Its [character support guide](https://support.pokemmo.com/knowledgebase/article/character-stuck)
distinguishes logging into an account from selecting and entering a character.
These primary references inform the DQM flow; no PokeMMO code or artwork is used.

DQM 0.2 follows: select a local ROM → sign in / create an account → choose a
server adventure → enter the shared world. Three account-isolated adventure
slots provide Continue and New adventure choices. An existing adventure resumes
the latest server checkpoint instead of choosing a local save file.

The shipped client never starts the campaign without an authenticated session
and a server load response. It checkpoints every five seconds, and waits for a
durable server acknowledgement before a normal logout, slot change, or quit.
Connection loss or a five-second missing-heartbeat deadline stops the emulator
and returns to login. Reconnection reloads the server's last confirmed state.
A connection loss may roll back progress after the last confirmed checkpoint.

This implements online-only client behavior and server-owned persistence. It
is not the full PokeMMO architecture: the campaign is still simulated in the
client. Checkpoint bounds, account ownership, a per-load token, revisions and
one active session prevent accidental cross-account/stale-session overwrites;
they do not validate monster stats, rewards, combat or trading. A modified
client is not a cheat-resistant MMO. Server-side game/economy validation remains
required before claiming that property.

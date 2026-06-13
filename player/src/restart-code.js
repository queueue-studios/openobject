'use strict';

// Exit code the player uses to ask its supervisor to relaunch it after a self-update
// (HANDOFF §15). Kept in its own tiny module so the supervisor can stay dependency-free —
// it must not need to load the database or the app to know this one number.
//
// 75 = EX_TEMPFAIL (sysexits.h): "temporary failure, the user is invited to retry." A
// fitting, unreserved choice for "stop now, I'm coming right back."
module.exports = 75;

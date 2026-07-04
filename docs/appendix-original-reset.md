# Appendix: Resetting the original software

This is preserved from the original tutorial, as a courtesy, for an owner who wants to return the
frame to the software it shipped with. It is **not part of OpenObject**.

> **Untested and unsupported, at your own risk.** We have never verified any path back to the
> original software. This registration reset only helps while the original software is still
> installed. Once OpenObject is installed it has wiped the drive, so a true return then depends on a
> **full pre-wipe disk image** you made beforehand (see the **[backup appendix](appendix-backup-original.md)**),
> and we have not confirmed a restored image boots and runs. The original software also relied on
> online services that have since wound down, so even a successful restore may not work as it once
> did. Treat everything here as a rough outline, not a guaranteed recipe. You are on your own, and it
> takes real comfort with disk imaging and low-level recovery. If that is not you, bring in a
> technical helper (a technically inclined friend, or an AI coding assistant).

The original software is a standard Android app running in **Waydroid** (a LineageOS Android 11
container) on **Ubuntu Linux**. To reset its account registration (all inside the Android
container's UI):

1. Connect a USB-A **mouse** to the mini PC.
2. Reveal the system menu: **click-and-drag downward from the very top** of the screen (this is the
   Android notification shade, begin the click right at the top edge and drag down; it is a little
   fiddly).
3. Expand the menu and click the **Settings** cog.
4. Go to **Apps & Notifications** → the original app (labeled **White Walls** in the menu) →
   **Storage & Cache** → **Clear Storage** → **OK** to delete the app's data.
5. Click the circular **home** button to exit. The unit can then re-register, if those services are
   still available.

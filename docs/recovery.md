# Recovery

Each section names the problem, then the fix. Commands run on the computer with the tablet plugged in.

## A disabled app broke something

```sh
scripts/rollback.sh --batch <n>            # dry run
scripts/rollback.sh --batch <n> --apply
```

To re-enable one package: `scripts/rollback.sh --package <id> --apply`, or by hand
`adb shell pm enable --user 0 <id>`. Without a computer: **Settings → Apps**, open the filter, show disabled
apps, open the app, tap **Enable**.

## The launcher is broken or Home does nothing

The scripts never disable One UI Home. Make it the default again:
**Settings → Apps → Choose default apps → Home app → One UI Home**.
By ADB: `adb shell cmd role add-role-holder --user 0 android.app.role.HOME com.sec.android.app.launcher`.

## Decaid does not start

1. **Settings → Apps → Decaid**: check it is enabled and that Bluetooth ("Nearby devices") permission is allowed.
2. Check Bluetooth is on.
3. Reinstall from the Decaid APK if needed. Your profiles and settings inside Decaid may be lost.

## Bluetooth problems

Turn Bluetooth off and on. Reboot. If Bluetooth broke after a batch, roll back that batch.
This project never disables Bluetooth packages.

## The Decadent shortcut is gone

With Fossify Launcher as Home, open Chrome and go to `https://decadentcoffee.app/app/`. Tap the install icon in the address bar, then **Install** once.
Drag Decadent to the Home screen if it is not there. A shortcut made while another launcher was Home does not carry over.

## The Decent or Update Decent icon is missing

They are pinned to One UI Home, so another launcher may not show them. They are not deleted. Switch Home back:
`adb shell cmd role add-role-holder --user 0 android.app.role.HOME com.sec.android.app.launcher`

## The bottom buttons are gone

That is Swipe gestures: swipe up from the bottom edge for Home. To get the buttons back: **Settings → Display → Navigation bar → Buttons**.

## ADB stops working

- Check that **Developer options → USB debugging** is still on.
- Replug the cable with the tablet unlocked, and accept the prompt again.
- On the computer: `adb kill-server`, then `adb devices`.
- Everything this project changes can also be undone on the tablet: Settings → Apps (enable apps), Choose default apps.

## Factory reset

Avoid it. A factory reset erases everything and restores **Samsung's** stock setup, not Decent's.
Afterwards you would need to:
- reinstall Decent's apps (AndroWish and the Decent app, Coffee Flow, SE Profiler, File Manager +, AZ Screen Recorder) and Decaid;
- set up the DE1 connection again.
Ask Decent support for their current tablet setup before you reset.

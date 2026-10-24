## Opening Zipboy

Drag Zipboy from the disk image to Applications.

This build isn't notarized by Apple yet, so the first time you open it macOS will say it can't check it
for malicious software. Click **Done**, then open **System Settings › Privacy & Security**, scroll to
**Security**, and click **Open Anyway** next to Zipboy. macOS asks once; after that Zipboy opens normally.

Check the download against the `.sha256` file attached here with `shasum -a 256 -c Zipboy-*.dmg.sha256`.

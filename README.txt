RK ROBOT PRO - NEW SEPARATE iOS APP
===================================

This is a NEW app, not a replacement/update of the old RK ROBOT app.

App name: RK ROBOT PRO
Bundle ID: com.rkrobot.procontrol
Version: 1.0.0

The old RK ROBOT app can remain installed on the same iPhone.

Create a NEW GitHub repo (recommended name: rk-robot-pro-ios), then upload
the CONTENTS of this folder to the repo root.

Workflow path:
.github/workflows/build-ios-ipa.yml

Then:
Actions -> Build RK ROBOT PRO iOS IPA -> Run workflow

Artifact:
RK_ROBOT_PRO_unsigned_IPA

Sign/install that IPA separately.

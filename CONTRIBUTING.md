# Contributing to LeoSync

We welcome any contribution to LeoSync, and there are multiple ways to contribute:

 - [Reporting a bug](#reporting-a-bug)
 - [Localize LeoSync into your language](#localize-leosync)
 - [Developing](#developing)
 - [Submitting a pull request](#submitting-a-pr)
 - [Requesting a new features](#requesting-a-new-feature)

## Reporting a bug
No one likes it if something goes wrong. However, before submitting a bug report, please make sure to check the following links:

- [LeoSync documentation](https://github.com/JLeo0001/LeoSync/)
- [search existing issues](https://github.com/JLeo0001/LeoSync/issues?q=is%3Aissue)

A lot of problems are errors in `engine.conf`. If you have [Termux](https://github.com/termux/termux-app) installed, you can install engine  with `pkg install engine`. Then, export your config from LeoSync and select Termux as target. You can then try to check if the error also occurs in Termux. You can also export and transfer your config to a desktop PC and test it there. 

If you experience the same issue on your PC or in Termux, you can use the engine forum to post your problem. If you are really sure that you have discovered an issue in engine itself, you can also open an issue in the engine repository.

When filing a new bug report, answer all the questions in the template. This includes:
 - App version (e.g. `v1.11.4`)
 - Exact Android version (e.g. `8.1.0`)
 - Your device model and manufacturer
 - An exact list of steps that leads to your issue. Please also enable local logging in Settings > Logging > Log engine errors.
 - Paste or attach your engine log located in `Android/data/com.jleoz.sync/files/logs/log.txt`. Make sure to remove any confidential information such as passwords, tokens or authorization info.
 - If your issue happens when using a remote, please also add a redacted version of your configuration file (passwords and tokens removed).
 - We may also ask you to test your config file on a PC or in Termux.

## Localize LeoSync
 - Download [strings.xml](https://github.com/JLeo0001/LeoSync/blob/main/app/src/main/res/values/strings.xml) file.
 - Open the `string.xml` file with your favorite text editor.
 - Delete all the `strings` with the attribute **translatable="false"**.
 - Translate `string` values from **en-US (English)** to that language you want to localize LeoSync.
   Here is an example of translating into **bn-BD**

   Default string values **en-US**
   ```sh
   <string name="app_name">LeoSync</string>
   <string name="app_description">Engine for Android</string>
   <string name="app_short_name">LeoSync</string>
   ```
   Translated string values into **bn-BD**
   ```sh
   <string name="app_name">রাউন্ড সিঙ্ক</string>
   <string name="app_description">অ্যান্ড্রয়েডের জন্য আরক্লোন</string>
   <string name="app_short_name">রাউন্ড সিঙ্ক</string>
   ```

## Developing
You should first make sure you have:

- Go 1.20+ installed and in your PATH
- Java installed and in your PATH
- Android SDK command-line tools installed OR the NDK version specified in `gradle.properties`
  installed

You can then build the app normally from Android Studio or from CLI by running:

```sh
# Debug build
./gradlew assembleOssDebug

# or release build
./gradlew assembleOssRelease
```

## Submitting a PR
Here are a few tips on getting your PR merged:

1. Keep your PR small. Small PRs are easier to review, easier to test and as a result can be merged quickly. If this is your first PR to LeoSync, keep it very small.
2. Keep your PR focussed. Your PR should have a single, specific purpose. If you discover something else you'd like to improve while working on your PR, only include it if there's a direct link to the purpose of the PR.
3. Use the style of the existing code base. Use idiomatic code whenever possible. If you have performance concerns, use the profiler to test your assumptions.
4. Rebase your branch before creating your PR.

## Requesting a new feature
We also discuss new features on GitHub. You can browse the issue for existing feature requests and join the discussion. Note that commenting generally notifies all participants of your comment. Please avoid '+1', 'me to' or similar comments and use :+1: [reactions](https://github.blog/2016-03-10-add-reactions-to-pull-requests-issues-and-comments/) instead.

When opening a new feature request, **answer all questions in the template**. This includes:
- Searching for existing issues and discussions that already cover your request. We may close your request without comment if you fail to do this.
- For anything related to data transfer or accessing files on your cloud storage, please first check if your idea works in engine. If it does not work there, it will probably also not work in LeoSync.
- Asking yourself what you can do to create this feature.
- The version of LeoSync you are using.

You will also be asked two free-form questions:
> #### What problem are you trying to solve?

Describe what you are trying to achieve. This may include a series of steps if you are using engine as part of a larger workflow, or may just be a single action. **Do not describe possible solutions.** Keep your ideas for the next question. 

You can describe this as a problem ("I cannot find a file"), or as a goal you want to achieve ("I would like to stream a video on my TV").

> #### What should LeoSync be able to do differently to help with this problem?

Describe how you would solve your problem. This may include additional buttons, options, menus, dialogs, etc. 

This two-step approach allows us to to design general solutions, that work not just for your specific situation, but for the broader LeoSync user base. It also makes it easier for other community to join the discussion and suggest different solutions.

Please keep in mind that LeoSync and engine are developed by volunteers.

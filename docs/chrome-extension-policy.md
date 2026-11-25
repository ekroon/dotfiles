# Chrome OpenCode Browse policy

On macOS, chezmoi renders `~/.config/chrome/opencode-browse.mobileconfig`.
The extension list is declared in `root/.chezmoidata.yaml`.
The profile manages only Google Chrome's `ExtensionInstallForcelist`, using
mandatory managed preferences. It does not change other Chrome policies,
install itself, or alter existing management profiles.

The [Chrome Web Store listing](https://chromewebstore.google.com/detail/opencode-browse/mfnicocicmmlkpjnaffgihfjhdgjkdjg)
identifies `mfnicocicmmlkpjnaffgihfjhdgjkdjg` as OpenCode Browse.
Its force-install entry uses the Web Store update endpoint,
`https://clients2.google.com/service/update2/crx`.

## Deployment

Render or apply only this file from the intended source checkout:

```bash
chezmoi --source "$PWD" cat ~/.config/chrome/opencode-browse.mobileconfig
chezmoi --source "$PWD" apply ~/.config/chrome/opencode-browse.mobileconfig
```

Neither command activates the policy. Google documents
[configuration profiles for macOS policy deployment](https://support.google.com/chrome/a/answer/9020077).
Writing `ExtensionInstallForcelist` with `defaults write` into
`~/Library/Preferences/com.google.Chrome.plist` does not make it mandatory:
Chrome loads ordinary preferences as recommended policies, and this policy
does not support recommendation.

On an organization-managed Mac, have IT deploy the setting through the existing
MDM policy configuration, or through Chrome Browser Cloud Management when
Chrome is enrolled (`CloudManagementEnrollmentToken` is set). Before deployment, inspect the effective policies in
`chrome://policy`, including `ExtensionSettings`. If `ExtensionInstallForcelist`
already exists, its administrator must append this entry to the complete
existing list rather than deploy a competing profile. Separate profiles must
not be assumed to merge arrays. Do not replace organizational policies or
copy unrelated managed settings into this profile.

If organization rules permit manual installation and there is no competing
policy, open the rendered `.mobileconfig` and review/install it in System
Settings. Installation can require administrator approval. Do not write
directly to `/Library/Managed Preferences`; those files belong to macOS
management. There is no automatic installation hook.

## Verification and removal

In `chrome://policy`, select **Reload policies** and verify that
`ExtensionInstallForcelist` contains this entry, has **Mandatory** level,
and reports **OK**. In `chrome://extensions`, verify that OpenCode Browse is
installed and policy-managed. Restart Chrome if necessary, then exercise
browse to check whether the debugger banner is absent. A rendered profile
alone proves neither policy recognition nor banner suppression.

[Force-installation](https://chromeenterprise.google/policies/#ExtensionInstallForcelist)
grants extension permissions implicitly and prevents users from disabling or
removing the extension normally. This standalone profile permits removal
through System Settings; an MDM deployment must be changed by its administrator.
Removing the extension from the effective force-install list causes Chrome
to uninstall it. Updating the file with chezmoi does not update an installed
profile: authorized redeployment is required.

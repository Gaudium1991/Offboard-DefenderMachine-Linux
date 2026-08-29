# MDE Offboard Machine

PowerShell script to **offboard a machine from Microsoft Defender for Endpoint (MDE)** using the official [Offboard machine API](https://learn.microsoft.com/en-us/defender-endpoint/api/offboard-machine-api).

The script interactively prompts for `ClientID`, `ClientSecret`, `TenantID` and `MachineID`, obtains an OAuth2 token from Microsoft Entra ID (*client credentials* flow) and sends the offboarding request.

---

## ✅ Linux support

Offboarding of **Linux servers** through the Offboard machine API is **generally available (GA)**, as announced in the August 2026 Microsoft Defender for Endpoint release notes. The capability lets you automate offboarding of Linux devices at scale, simplifying device lifecycle management.

> **Requirement**: the Linux machine must be running **Microsoft Defender for Endpoint on Linux version 101.26062.0007 or later**.

Official reference: [New features in Microsoft Defender for Endpoint — August 2026](https://learn.microsoft.com/en-us/defender-endpoint/whats-new-in-microsoft-defender-endpoint).

In addition to Linux, the API also supports Windows and macOS.

---

## 📋 Prerequisites

- **PowerShell 5.1** or later (also works with PowerShell 7 on Windows/macOS/Linux)
- An **app registered in Microsoft Entra ID** with the `Machine.Offboard` application permission (see below)
- The **Machine ID** of the machine to offboard (40-character hexadecimal string, found in the URL of the device page in the Defender portal)
- For Linux devices: MDE agent version **101.26062.0007 or later**

---

## 🔐 Creating and configuring the app in Microsoft Entra ID

To obtain `ClientID`, `ClientSecret` and `TenantID` you need to register an application in Entra ID and assign it the correct permissions.

### 1. Register the application

1. Sign in to [https://entra.microsoft.com](https://entra.microsoft.com) (or the Azure portal) with an account that has privileges to register apps.
2. Go to **Identity → Applications → App registrations → New registration**.
3. Enter a name, for example `MDE-Offboard-Automation`.
4. Under **Supported account types** select **Accounts in this organizational directory only (Single tenant)**.
5. Leave the **Redirect URI** empty (not needed for the client credentials flow).
6. Click **Register**.

### 2. Retrieve ClientID and TenantID

On the **Overview** page of the newly created app you will find:

- **Application (client) ID** → this is your **`ClientID`**
- **Directory (tenant) ID** → this is your **`TenantID`**

### 3. Create the Client Secret

1. In the app, go to **Certificates & secrets → Client secrets → New client secret**.
2. Enter a description and an expiry (e.g. 6 or 12 months).
3. Click **Add**.
4. **Copy the secret value immediately** (the *Value* column): it will be shown **only once**. This is your **`ClientSecret`**.

> 🔒 Store the secret in a secure place (e.g. a password manager or Azure Key Vault). Never put it in clear text in code or in public repositories.

### 4. Assign the API permissions (the most important step)

The API requires the **application** permission `Machine.Offboard` (display name: *Offboard machine*).

1. In the app, go to **API permissions → Add a permission**.
2. Select the **APIs my organization uses** tab.
3. Search for and select **WindowsDefenderATP**
   *(if it doesn't appear, search for `Microsoft Threat Protection` depending on the tenant configuration).*
4. Choose **Application permissions** (NOT *Delegated*, because the script uses the client credentials flow with no signed-in user).
5. Expand the **Machine** category and select **`Machine.Offboard`**.
6. Click **Add permissions**.

### 5. Grant admin consent

Application permissions require administrator consent:

1. Still on the **API permissions** page, click **Grant admin consent for &lt;tenant name&gt;**.
2. Confirm. A green check mark must appear in the **Status** column next to `Machine.Offboard`.

### Summary of required permissions

| Item                        | Value                                    |
| --------------------------- | ---------------------------------------- |
| API                         | WindowsDefenderATP / Microsoft Threat Protection |
| Permission type             | **Application**                          |
| Permission                  | `Machine.Offboard`                       |
| Display name                | *Offboard machine*                       |
| Admin consent               | **Required** (Grant admin consent)       |

> ℹ️ Beyond the API permissions, actual access to the device may depend on the **device group** settings in Defender. Make sure the app/user has visibility over the device group the machine belongs to.

---

## 🚀 Usage

### Interactive mode (recommended)

The script prompts for all values at runtime; the secret is entered masked:

```powershell
.\Offboard-DefenderMachine.ps1
```

You will be prompted, in order, for:

1. **ClientID** (Application ID)
2. **TenantID** (Directory ID)
3. **MachineID** (40 hexadecimal characters)
4. **ClientSecret** (masked input)
5. **Comment** to associate with the action (optional; default: `Offboard machine by automation`)

### Passing some parameters from the command line

You can pre-fill some values (the secret is still requested securely at runtime):

```powershell
.\Offboard-DefenderMachine.ps1 -ClientId "xxxx" -TenantId "yyyy" -MachineId "xxxxxxxxxxxxx"
```

---

## 🔎 How to find the Machine ID

1. In the Defender portal [https://security.microsoft.com](https://security.microsoft.com) open **Assets → Devices**.
2. Select the desired machine.
3. The **Machine ID** is the 40-character hexadecimal string visible in the URL of the device page.

---

## 🧠 How the script works

1. Collects the parameters interactively (secret handled as a `SecureString`).
2. Requests an OAuth2 token from Entra ID:
   `POST https://login.microsoftonline.com/{TenantId}/oauth2/v2.0/token`
   with `scope = https://api.securitycenter.microsoft.com/.default` and `grant_type = client_credentials`.
3. Sends the offboarding request:
   `POST https://api.security.microsoft.com/api/machines/{MachineId}/offboard`
   with header `Authorization: Bearer <token>` and JSON body `{ "Comment": "..." }`.
4. On success the API returns `200` and a **Machine Action** object; the script prints it to screen.
5. The plain-text secret is cleared at the end (`finally` block).

> The `Comment` field is **required**: without a comment the API returns error `400`.

---

## ⏱️ API limitations

- **Rate limit**: 100 calls per minute and 1,500 calls per hour.
- For Linux devices, agent version **101.26062.0007 or later** is required.
- Running the offboarding API stops the sensor service; on Windows it does not remove the onboarding information from the registry the way a dedicated offboarding script would.

---

## 🛠️ Troubleshooting

| Error | Possible cause / fix |
| ----- | -------------------- |
| `AADSTS7000215` / token failure | Wrong or expired ClientSecret. Regenerate the secret. |
| `401 Unauthorized` | `Machine.Offboard` permission missing or admin consent not granted. |
| `403 Forbidden` | The app has no visibility over the machine's device group. |
| `400 Bad Request` | Missing comment or invalid MachineID. |
| `404 Not Found` | MachineID does not exist or the machine is not present in MDE. |
| Error on Linux | Verify the agent is at version 101.26062.0007 or later. |

---

## 📦 Repository contents

```
MDE-Offboard-Machine/
├── Offboard-DefenderMachine.ps1   # Main script
├── README.md                      # This file
└── LICENSE                        # MIT license
```

---

## 📤 How to publish to GitHub

From the project folder:

```bash
git init
git add .
git commit -m "Initial commit: MDE Offboard Machine script"
git branch -M main
git remote add origin https://github.com/<your-user>/MDE-Offboard-Machine.git
git push -u origin main
```

Alternatively, first create an empty repository on GitHub (with the MIT license already selected) and then upload the files from the web UI via **Add file → Upload files**.

---

## 📄 License

Distributed under the **MIT** license. See the [LICENSE](LICENSE) file for details.

Copyright © 2026 **Guido Imperatore**

---

## 🔗 References

- [Offboard machine API — Microsoft Defender for Endpoint](https://learn.microsoft.com/en-us/defender-endpoint/api/offboard-machine-api)
- [New features in Microsoft Defender for Endpoint (Linux support GA)](https://learn.microsoft.com/en-us/defender-endpoint/whats-new-in-microsoft-defender-endpoint)
- [Use Microsoft Defender for Endpoint APIs](https://learn.microsoft.com/en-us/defender-endpoint/api/apis-intro)
- [Get MachineAction API](https://learn.microsoft.com/en-us/defender-endpoint/api/get-machineaction-object)

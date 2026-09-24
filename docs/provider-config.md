# AI usage provider configs

Lenotch's AI Usage tab can show any service that reports usage over HTTP as JSON.
Add one in **Settings → AI Usage → Add Custom Provider…**, or describe it in a config file.

## Where configs live

```
~/Library/Application Support/Lenotch/Providers/*.json
```

Every `.json` file in that folder becomes a provider. Use **Import Config…** to copy one in,
**Config Folder** to open the folder, and **Reload** after editing a file. A config seen for the
first time is switched on; if you switch it off, it stays off.

## Format

```json
{
  "name": "OpenRouter",
  "url": "https://openrouter.ai/api/v1/auth/key",
  "authHeader": "Authorization",
  "authPrefix": "Bearer ",
  "apiKeyFile": "~/.config/openrouter/key",
  "mode": "usedAndLimit",
  "value": "data.usage",
  "limit": "data.limit",
  "reset": "",
  "label": "Credits",
  "logo": "openrouter.png",
  "tintLogo": true
}
```

| Key | Required | Meaning |
|---|---|---|
| `name` | yes | Shown in Settings and the hover card. |
| `url` | yes | Requested with GET. |
| `value` | yes | Dot path to the number to show, e.g. `data.usage` or `limits.0.used`. |
| `mode` | no | `percent` (value is 0–100, default), `usedAndLimit` or `remainingAndLimit`. |
| `limit` | for the last two modes | Dot path to the limit. |
| `reset` | no | Dot path to when it resets (ISO 8601 date, or Unix seconds/milliseconds). |
| `label` | no | Name of the window, e.g. `Credits` (default `Usage`). |
| `authHeader`, `authPrefix` | no | Defaults `Authorization` and `Bearer `. |
| `apiKeyFile` | no | File holding the API key. Otherwise set the key in Settings (kept in the keychain). |
| `logo` | no | A file next to the config, an absolute path, or a `data:image/png;base64,…` URL. |
| `tintLogo` | no | Tint the logo white like the built-in marks (default `true`). |
| `symbol` | no | SF Symbol used when there's no logo (default `sparkles`). |

Configs never contain your API key when exported: **Export Config…** in the editor writes the
provider with its logo embedded, ready to share.

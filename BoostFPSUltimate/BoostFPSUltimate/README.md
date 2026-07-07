# Boost FPS Ultimate

A modular PowerShell toolkit for Windows gaming performance tuning: hardware/network
diagnostics, CPU/GPU/Memory/Storage/Network/Windows optimization profiles, automatic
restore-point + registry backup before every change, and before/after benchmarking.

## Project structure

```
BoostFPSUltimate/
├── install.ps1                  ← one-line installer entry point
├── BoostFPS.ps1                 ← main app (interactive menu)
├── config.json                  ← file manifest used by install.ps1
├── Modules/
│   ├── Logging.psm1
│   ├── HardwareInfo.psm1
│   ├── NetworkInfo.psm1
│   ├── RestoreBackup.psm1
│   ├── CPUOptimize.psm1
│   ├── GPUOptimize.psm1
│   ├── MemoryStorageOptimize.psm1
│   ├── NetworkOptimize.psm1
│   ├── WindowsOptimize.psm1
│   └── Benchmark.psm1
└── Profiles/
    ├── Esports.json
    ├── Balanced.json
    └── Battery.json
```

## 1. Setting up GitHub hosting (you don't have a repo yet — do this first)

1. Create a free GitHub account at https://github.com if you don't have one.
2. Create a **new public repository** named e.g. `BoostFPSUltimate`.
   - Public is required so `raw.githubusercontent.com` can serve the files
     without authentication (private repos need a token, which complicates
     the one-liner).
3. Upload this entire folder's contents to the repo root (via the GitHub
   web UI "Add file → Upload files", or via git):
   ```bash
   git init
   git add .
   git commit -m "Initial commit"
   git branch -M main
   git remote add origin https://github.com/YOURUSERNAME/BoostFPSUltimate.git
   git push -u origin main
   ```
4. **Update the repo URL in two places** before pushing:
   - `config.json` → `"RepoBaseUrl"`
   - `install.ps1` → `$RepoBase` variable
   Replace `YOURUSERNAME` with your actual GitHub username.
5. Your raw file base URL will be:
   ```
   https://raw.githubusercontent.com/YOURUSERNAME/BoostFPSUltimate/main
   ```
6. Test it works by opening that URL + `/config.json` in a browser — you
   should see the JSON manifest.

### Optional: use GitHub Releases instead of raw main-branch files
For versioned releases (recommended once you're past testing), tag a
release (`v1.0.0`) and point `RepoBaseUrl` at:
```
https://github.com/YOURUSERNAME/BoostFPSUltimate/releases/download/v1.0.0
```
This lets you update `main` without breaking existing installs, and lets
users pin to a known-good version.

## 2. The one-line installer

Once hosted, anyone can install with:
```powershell
irm https://raw.githubusercontent.com/YOURUSERNAME/BoostFPSUltimate/main/install.ps1 | iex
```

What `install.ps1` actually does (all real, no placeholders):
- Re-launches itself elevated if not already Administrator
- Downloads `config.json` to get the file list
- Downloads every file in the manifest, retrying up to 3 times on failure
- Verifies each downloaded file is non-empty
- Installs to `%LocalAppData%\BoostFPSUltimate`
- Creates Desktop + Start Menu shortcuts
- Prints a pass/fail summary

**Not implemented (be aware):** file hash verification against a signed
manifest. To add real integrity checking, generate SHA256 hashes at
release time (`Get-FileHash`) and commit a `manifest.sha256` file, then
have `install.ps1` compare hashes after download — happy to add this if
you want it before going wider than personal/small-group use.

## 3. Running the app

```powershell
powershell -ExecutionPolicy Bypass -File "%LocalAppData%\BoostFPSUltimate\BoostFPS.ps1"
```
or use the Desktop shortcut created by the installer.

Menu options:
1. Hardware + network report
2. Create restore point + backup current settings (do this before anything else)
3. Run benchmark only
4. Apply a profile (Esports / Balanced / Battery)
5. Rollback last registry backup
6. Exit

Unattended mode (e.g. for a scheduled task or scripted deployment):
```powershell
.\BoostFPS.ps1 -Profile Esports -Unattended
```

## 4. Risk levels — read this before using "Advanced"

Every optimize function is tagged Safe or Advanced:

| Risk    | Examples                                              | Trade-off                                  |
|---------|--------------------------------------------------------|---------------------------------------------|
| Safe    | High-performance power plan, HAGS, disable Fullscreen Optimizations, Game Mode, TRIM/defrag | Well-documented, reversible, low downside |
| Advanced| Disable Nagle's Algorithm, limit CPU C-States, disable SysMain | Real latency gains but can increase power draw, packet count, or app-launch time depending on your hardware |

The **Esports** profile uses Advanced settings. **Balanced** and **Battery**
stay Safe. Always run menu option 2 (restore point + backup) before
applying any profile — this is also done automatically inside
`Invoke-BFUProfile`.

## 5. Known limitations (documented honestly, not hidden)

- **Mouse DPI / polling rate**: Windows has no public API exposing this
  for generic HID devices. Use your mouse vendor's software (Logitech G
  Hub, Razer Synapse, etc.) for authoritative values.
- **Monitor G-Sync/FreeSync/VRR status**: not exposed via WMI. Check
  Windows Settings → Display, or NVIDIA Control Panel / AMD Software.
- **Standby memory list clearing**: no documented Windows API exists;
  the module only runs this if you already have Sysinternals RAMMap or
  EmptyStandbyList installed locally — it does not bundle or fabricate
  this capability.
- **"FPS Score"**: this toolkit reports CPU/disk/network micro-benchmarks
  as a system-responsiveness indicator, not a real in-game FPS measurement.
  For real FPS numbers use CapFrameX, MSI Afterburner/RTSS, or 3DMark.

## 6. Updating

Bump `"Version"` in `config.json`, commit/push, and re-run the one-line
installer — it always pulls the latest `main` (or a specific Release tag
if you switch to Releases per section 1).

# Sidekick - KOReader Sync Plugin

<p align="center" style="margin-top:2rem; margin-bottom: 2rem; display:flex; justify-content: center; gap: 0.5rem;">
  <img src="https://img.shields.io/github/v/release/gustjose/sidekick.koplugin?style=for-the-badge&logo=github&color=E37D42" alt="Latest Release">
  <img src="https://img.shields.io/github/downloads/gustjose/sidekick.koplugin/total?style=for-the-badge&logo=obsidian&color=E37D42" alt="Total Downloads">
  <img src="https://img.shields.io/github/last-commit/gustjose/sidekick.koplugin?style=for-the-badge&color=E37D42" alt="Last Commit">
  <img src="https://img.shields.io/github/license/gustjose/sidekick.koplugin?style=for-the-badge&logo=opensourceinitiative&logoColor=fff&color=E37D42" alt="License">
</p>

**Sidekick** is a decentralized, offline-first reading progress synchronization plugin for [KOReader](https://github.com/koreader/koreader).

Unlike the built-in KOReader sync (which relies on a central Progress Sync server), Sidekick saves your progress into a local JSON file right next to your book. This allows you to use general-purpose file synchronization tools like **Syncthing**, **Nextcloud**, or **Dropbox** to keep your reading position in sync across all your devices.

## Key Features

- **Serverless Sync:** No need to host a KOReader sync server or create an account. If you can sync files, you can sync progress.
- **Precision Positioning (XPath):** Uses XPath (XPointer) instead of just page numbers. This ensures you land on the **exact paragraph** where you left off, even when switching between a 6" Kindle and a 10" Android tablet with different font sizes.
- **Smart Conflict Resolution:**
  - Uses a "Vector Clock" style revision system to determine the latest progress.
  - Automatically resolves conflicts if two devices were used offline simultaneously (furthest read point wins).
- **Syncthing Integration:** Can optionally trigger a Syncthing scan immediately after saving progress to ensure near-instant syncing (requires API configuration).
- **Battery Aware:** On E-ink devices (Kindle/Kobo), it respects Wi-Fi status to save battery. On Android, it works seamlessly with mobile data/Wi-Fi.

## Installation

1.  Download the latest `sidekick.koplugin.zip` from the [Releases](https://github.com/YOUR_USERNAME/sidekick.koplugin/releases) page.
2.  Connect your device to your computer.
3.  Extract the zip file into the KOReader plugins directory: `/koreader/plugins/`
4.  The final structure should look like: `.../plugins/sidekick.koplugin/main.lua`.
5.  Restart KOReader.

## ⚙️ How to Setup (The Syncthing Way)

Sidekick generates a `.sidekick.json` file inside the `.sdr` metadata folder of your books. To sync your progress, you simply need to sync your books folder.

1.  **Install Sidekick** on all your devices.
2.  **Install Syncthing** (or use Mobius/SyncTrayzor) on your devices.
3.  **Sync your Books:** Configure Syncthing to synchronize your library folder (e.g., `/mnt/sdcard/Books`).
    - _Note:_ Ensure that the `.sdr` folders (where KOReader saves metadata) are included in the synchronization.
4.  **Read!** Sidekick automatically saves your progress when you close a book, suspend the device, or turn a page (configurable).

### Optional: Instant Sync Trigger

If you want Sidekick to force Syncthing to scan immediately after you close a book (for faster sync):

1.  Open the `sidekick.koplugin` folder on your device.
2.  Edit `settings.json`.
3.  Fill in your Syncthing API details:

    ```json
    {
      "url": "[http://127.0.0.1:8384](http://127.0.0.1:8384)",
      "api_key": "YOUR_SYNCTHING_API_KEY_HERE",
      "folder_id": "default"
    }
    ```

    - _`folder_id` is the ID of the folder in Syncthing that contains your books._

## 🛠️ Usage

The plugin works mostly in the background, but adds a **SideKick Sync** menu to the main menu (usually under the "Search" or "Tools" tab).

- **Check Status:** Shows your current local revision and page vs. the remote file.
- **Force Save:** Manually writes your current position to the sync file.
- **Check for Updates:** Checks GitHub for new versions of the plugin and installs them automatically.

## 🔧 Development

If you want to contribute or build from source:

### Prerequisites

- Python 3.x (for build scripts)
- `adb` (if deploying to Android)

### Scripts

- **`scripts/deploy.py`**: Pushes the current code to a connected Android device via ADB and monitors logs.
- **`scripts/release.py`**: Automates version bumping, tagging, and creating GitHub releases with AI-generated notes.
- **`tests/mock_server/`**: Contains a local server to test the OTA (Over-The-Air) update functionality without pushing to GitHub.

## 📄 License

This project is licensed under the [MIT License](LICENSE).  
Copyright © 2025 Gustavo Carreiro.

---

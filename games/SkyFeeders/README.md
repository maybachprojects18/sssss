# Sky Feeders (v0.1)

Throw food **up into the sky**. The higher it flies, the rarer the creature that swoops in and catches it.
Caught creatures live on your floating sky island and earn coins, even while you're offline.

**Thumbnail line:** *"Throw food to the SKY. The higher it goes, the rarer the creature that catches it!"*

## What's in v0.1

| Feature | How it works |
|---|---|
| Hold to throw | Hold the big button (or **F** on PC). The power meter goes up and down; release to throw. |
| 🎯 Perfect Release | Release in the green zone for **x1.35 height** and a "PERFECT!" callout. |
| Sky layers | Treetops (0 m), Clouds (100 m), Storm (500 m), Aurora (2,000 m), Space (10,000 m). Higher layers have more luck and rarer creatures. |
| 17 original creatures | Common → Uncommon → Rare → Epic → Legendary → Mythic → **Secret**. |
| 🍀 100x Luck Throw | Free: a meter fills by 1 per throw (40 to fill). The next throw gets **100x luck** and is caught as if it flew **one layer higher**. |
| 🌪️ Mega Updraft | Server-wide event every 6-10 min (45-75 s in Studio): all throws fly **x2.5** for 45 s. |
| 🍎 Food shop | 6 foods; better food flies higher. Paid with coins only. |
| 💪 Train | Hold TRAIN to gain Power: height x (1 + Power/100). |
| 🐾 Pets | Up to 12 on your island earn coins/sec. Equip Best, equip or unequip, sell (Epic+ need a second tap), and "Sell unequipped" (Rare and below only). |
| 📖 Index + 🎲 Odds | Silhouettes until found. The odds screen shows the exact per-creature chance for every layer, normal vs 100x, computed by the same function the server rolls with. |
| 💾 Saving | Session-locked DataStore saves, autosave every 30 s, saves on leave and on shutdown, offline income (50%, up to 8 h). |

Everything is placeholder art made of simple parts; real models, sounds and VFX come in v0.3.
There are **no Robux purchases** in v0.1.

## Install: copy-paste into Roblox Studio

1. Open Roblox Studio and create a new **Baseplate** place. Publish it once (**File → Publish to Roblox**) so it can use DataStores.
2. **Home → Game Settings → Security →** turn on **Enable Studio Access to API Services**, then save.
   (Studio saves go to a separate `_STUDIO` test store, so testing can never touch live player data.)
3. Create these objects in the **Explorer** and paste the matching file's contents into each:

| In Studio, create… | Name it exactly | Inside | Paste from |
|---|---|---|---|
| ModuleScript | `SkyConfig` | ReplicatedStorage | `src/ReplicatedStorage/SkyConfig.luau` |
| ModuleScript | `SkyMath` | ReplicatedStorage | `src/ReplicatedStorage/SkyMath.luau` |
| ModuleScript | `CreatureBuilder` | ReplicatedStorage | `src/ReplicatedStorage/CreatureBuilder.luau` |
| ModuleScript | `PlayerData` | ServerScriptService | `src/ServerScriptService/PlayerData.luau` |
| **Script** | `SkyServer` | ServerScriptService | `src/ServerScriptService/SkyServer.server.luau` |
| **LocalScript** | `SkyClient` | StarterPlayer → StarterPlayerScripts | `src/StarterPlayerScripts/SkyClient.client.luau` |

   Delete the default `print("Hello world!")` line in each new script before pasting.
4. Set **Game Settings → Places → Max Players** to **12** or fewer (one island per player; change `MaxIslands` in SkyConfig if you want more).
5. Press **Play**. You'll be moved onto your own sky island.

### Or with Rojo

```bash
rojo serve games/SkyFeeders/default.project.json
```

## How to test it in Studio

- **Throw:** hold the orange button and release in the green. Watch the camera follow the food up and the creature swoop in.
- **Updraft:** in Studio it triggers every 45-75 s. The banner shows at the top.
- **Luck throw:** throw 40 times (or temporarily set `SkyConfig.LuckThrow.ThrowsToFill = 3`).
- **Saving:** play, earn coins, Stop, Play again. Coins should come back, plus an offline-income message.
- **Two players:** **Test → Clients and Servers → 2 players**. Each gets their own island; Legendary+ catches are announced to everyone.
- **Output window:** check for red errors. Please send me any you see.

## Tuning

Every number is in `SkyConfig`: food heights and prices, rarity weights and income, layer heights and luck, meter speed and the perfect window, luck-meter size, updraft timing. They are first-pass guesses; tune them after real playtests.

Current odds, worked out from the config (normal → 100x Luck Throw):

| Throw reaches | Best possible normally | With 100x Luck Throw |
|---|---|---|
| Treetops | Rare 3.7% | Epic 5.7% |
| Clouds | Epic 0.94% | Legendary 6.0% |
| Storm | Legendary 1.2% | Mythic 5.2% |
| Aurora | Mythic 0.95% | **Secret 6.5%** |
| Space | **Secret 1.2%** | **Secret 6.5%** |

## Security notes

- The client only sends intent: start charging, release, buy food X, equip Y. The server times the power meter itself and only accepts the client's reading if it's within 0.12 of the server's, which smooths lag but can't fake a perfect throw from nowhere.
- Every remote is rate-limited by player and type-checked. Prices, heights, rolls and coins never come from the client.
- All remotes are created by `SkyServer` in one folder (`ReplicatedStorage.SkyRemotes`).

## Roadmap

- **v0.2:** Robux shop (paid 100x Luck Throw with the full odds screen and PolicyService gating), game passes, rebirths, Index completion rewards, a physical training station.
- **v0.3:** Real creature models, sounds, VFX, thumbnail and icon.
- **v0.4+:** Weekly events, new sky layers, trading (gated by PolicyService).

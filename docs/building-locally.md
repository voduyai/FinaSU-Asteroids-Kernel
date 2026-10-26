# Building on your own machine (Linux or WSL)

[`scripts/build.sh`](../scripts/build.sh) is the same script [GitHub Actions](../.github/workflows/build.yml) runs, so a local build gives the same kernel. On a fast PC it is usually quicker than Actions: about 10 minutes on 16 threads, against about 25 minutes on a GitHub runner.

## What you need

| | Minimum | Better |
|---|---|---|
| CPU | 4 threads | 16 threads or more |
| RAM | 8 GB for the build | 16 GB |
| Free disk | 20 GB | 30 GB |
| OS | Ubuntu / Debian x86_64, or Windows 10/11 with WSL 2 | |
| Network | about 3 GB on the first build (kernel source and clang), about 1 GB after that | |

## 1. Windows only: set up WSL

Microsoft's guide: [Install WSL](https://learn.microsoft.com/windows/wsl/install). In short, in PowerShell **as Administrator**:

```powershell
wsl --install -d Ubuntu
```

Reboot if asked, then open **Ubuntu** from the Start menu and create a user.

WSL gets only half of the PC's RAM by default. To give it more, create a [`.wslconfig`](https://learn.microsoft.com/windows/wsl/wsl-config#wslconfig) file at `C:\Users\<you>\.wslconfig` (adjust to your PC, and leave about 4 GB for Windows):

```ini
[wsl2]
memory=24GB
processors=16
swap=8GB
```

Then restart WSL from PowerShell:

```powershell
wsl --shutdown
```

Run every command below **inside Ubuntu**.

## 2. Install the build tools

```bash
git clone https://github.com/voduyai/FinaSU-Asteroids-Kernel.git ~/FinaSU-Asteroids-Kernel
cd ~/FinaSU-Asteroids-Kernel
sudo bash scripts/install-deps.sh
```

On WSL, keep the repo in the Linux file system (`~`), not under `/mnt/c` or `/mnt/d`. Building through the Windows drives is many times slower.

## 3. Build

Everything on (SUSFS, Baseband Guard, networking, Unicode fix, BBRv3):

```bash
bash scripts/build.sh
```

Turn features off, or pin a FinaSU release, with environment variables:

| Variable | Default | Meaning |
|---|---|---|
| `FINASU_TAG` | latest release | e.g. `v1.2.0`; see [FinaSU releases](https://github.com/LyraVoid/FinaSU/releases) |
| `SUSFS` | `1` | SUSFS built into the kernel |
| `BBG` | `1` | Baseband Guard |
| `NETWORKING` | `1` | IP set, NAT/TTL, CAKE, BBR default, WireGuard, CIFS... |
| `UNICODE_FIX` | `1` | Unicode path bypass fix |
| `BBRV3` | `1` | BBRv3 congestion control |
| `JOBS` | all CPU threads | parallel compile jobs; lower it if you run out of memory |
| `WORK` | `./work` | where sources, the build and the output go |
| `GITHUB_TOKEN` | empty | optional; avoids GitHub API rate limits ([create a token](https://github.com/settings/personal-access-tokens), no permissions needed) |

Examples:

```bash
SUSFS=0 BBRV3=0 bash scripts/build.sh
FINASU_TAG=v1.2.0 JOBS=8 bash scripts/build.sh
```

`bash scripts/build.sh --help` prints the same list.

## 4. Get the result

Everything ends up in `work/dist/`:

| File | What it is |
|---|---|
| `Image` | the kernel |
| `*-AnyKernel3.zip` | flashable zip |
| `FinaSU_*.apk` | the manager app the kernel trusts |
| `.config` | the real kernel config |

On WSL, copy them to Windows:

```bash
mkdir -p /mnt/c/Users/Public/finasu-build
cp work/dist/* work/dist/.config /mnt/c/Users/Public/finasu-build/
```

Then open `C:\Users\Public\finasu-build` in File Explorer. Install it as described in the [README](../README.md#install).

## 5. Next builds

Update the repo and build again:

```bash
cd ~/FinaSU-Asteroids-Kernel
git pull
bash scripts/build.sh
```

Each build starts from fresh sources and a clean output folder. Only clang (`work/clang`, about 2 GB) is kept, so it is not downloaded again.

To free space but keep clang:

```bash
find work -mindepth 1 -maxdepth 1 ! -name clang -exec rm -rf {} +
```

To remove everything (clang is downloaded again next time):

```bash
rm -rf work
```

## Troubleshooting

| Problem | What to do |
|---|---|
| `missing: ...` right at the start | Run `sudo bash scripts/install-deps.sh` |
| Fails at the `==== FinaSU` step with an HTTP 403 | GitHub's API limit for anonymous use. Set `FINASU_TAG=v1.2.0`, or export a `GITHUB_TOKEN` |
| `Killed` or the PC freezes during `==== Build` | Out of memory. Lower `JOBS` (e.g. `JOBS=4`), or give WSL more memory in `.wslconfig` |
| `No space left on device` | Free at least 20 GB, or clean `work/` as shown above |
| A download fails | The script retries five times. If it still fails, run it again |
| `WARNING (SUSFS check): FinaSU's 10-patch hunk list is out of date` | Expected. FinaSU's own check list is stale since v1.0.10; every interface check passed |
| `Hunk #... FAILED` lines in the SUSFS step | Expected. They are FinaSU's dry-run probe of a patch that is never applied |

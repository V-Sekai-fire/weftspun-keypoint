```
curl -fsSL https://raw.githubusercontent.com/V-Sekai-fire/weftspun-keypoint/main/bootstrap.sh | sh
```

One step from a bare machine to a synced, tooled workspace: it installs the
pinned `repo` launcher, runs `repo init`, installs the pinned `pixi`, syncs, and
resolves the tool environments. On Windows,
`irm https://raw.githubusercontent.com/V-Sekai-fire/weftspun-keypoint/main/bootstrap.ps1 | iex`.

`repo` comes first and `pixi` second, because the pins for both live in this
repository and only `repo init` puts it on disk. That leaves one fetch nothing
can vouch for — the pins themselves, over the CDN — so the script re-reads them
from git afterwards and stops if the two differ. `check_bootstrap.py` fails if a
pin ever stops matching what its source serves.

`pixi.toml` declares the tools the gates and the engine builds need, so
`pixi run -e gate` and `pixi run -e build` reach them without anything being
fetched by hand.

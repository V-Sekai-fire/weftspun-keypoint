```
curl -fsSLo ~/.local/bin/repo https://raw.githubusercontent.com/GerritCodeReview/git-repo/v2.65/repo && chmod +x ~/.local/bin/repo
repo init -u https://github.com/v-sekai-fabric/weftspun-keypoint.git -b main
sh .repo/manifests/install.sh
repo sync
```

`repo` comes first and `pixi` second, because the pins that install them both
live in the manifest repository and only `repo init` puts that on disk. The
first launcher is therefore fetched unpinned; `install.sh` re-fetches it at the
pinned version, checks it, and installs pixi behind it.
`check_bootstrap.py` fails if the pinned launcher ever stops matching what its
source serves. On Windows use
`powershell -ExecutionPolicy Bypass -File .repo\manifests\install.ps1`.

`pixi.toml` beside them declares the tools the gates and the engine builds need,
so `pixi run -e gate` and `pixi run -e build` reach them without anything being
fetched by hand.

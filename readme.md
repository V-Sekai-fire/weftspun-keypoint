```
repo init -u https://github.com/v-sekai-fabric/weftspun-keypoint.git -b main
sh .repo/manifests/install.sh
repo sync
```

On Windows, `powershell -ExecutionPolicy Bypass -File .repo\manifests\install.ps1`
instead of the middle line. It puts the pinned pixi in `~/.pixi/bin`; add that to
PATH. The tools the gates and the engine builds need are declared in `pixi.toml`
beside it, so `pixi run -e gate` and `pixi run -e build` reach them without
anything being fetched by hand.

```
# POSIX Shell
curl -fsSL https://raw.githubusercontent.com/V-Sekai-fire/manifest-weftspun/main/main/bootstrap.sh | sh
# Windows Powershell
irm https://raw.githubusercontent.com/V-Sekai-fire/manifest-weftspun/main/main/bootstrap.ps1 | iex
```

Run on a bare machine to get a synced, tooled workspace.

The heavy Hugging Face projects are git-lfs, and the sync leaves their content as
pointer files: the workspace lands in minutes rather than hours, and nothing that
builds needs the blobs. To pull them as well, at a cost of tens of gigabytes:

```
# POSIX Shell
WEFTSPUN_GIT_LFS=1 sh bootstrap.sh
# Windows Powershell
$env:WEFTSPUN_GIT_LFS = '1'; ./bootstrap.ps1
```

An existing client picks them up with `repo init --git-lfs && repo sync`, or one
project at a time with `git lfs pull` inside it.

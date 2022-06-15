# sgit

Super git! A powershell wrapper around git for performing common operations.

## How to use

1. Clone the repo
1. Add `sgit.ps1` to your PATH
1. Run `sgit` commands

**Note:** I'll integrate help at some point, but right now, I just look at the file if I forget the commands or inputs.

## Branching

sgit commands follow my [branch-strategy](https://aka.ms/davidknise/branch-strategy).

# Commands

## checkout

Checks out a feature and dev branch (see [branch-strategy](https://aka.ms/davidknise/branch-strategy)) from the default branch (`main`).

`main` => `feature` => `dev`

* **Type** - (Mandatory) The type of work item. Example: userstory|bug|task|issue|feature
* **WorkItemNumber** - (Mandatory) The number of the work item. Example: 12345
* **Title** - (Mandatory) The title of the work. Example: my-feature
* **SourceBranch** - (Optional) The base branch to derive the feature branch from. Defaults to `main`.
* **SourceName** - (Optional) The name of the remote source to push the branch to. Defaults to `origin`.
* **Username** - (Optional) An override for the dev branch's username. Defaults to `[Environment]::Username.ToLower()`.

Example command:
```
sgit checkout -Type 'bug' -WorkItemNumber '12345' -Title 'fix-checkout'
```

The above would:
1. Create and push to the remote a branch off main called `bug/12345/fix-checkout`
1. Create and push to the remote a branch off of `bug/12345/fix-checkout` called `dev/<your username>/12345/fix-checkout`

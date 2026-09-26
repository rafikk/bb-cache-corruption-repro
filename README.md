# BuildBuddy executor file cache corruption reproducer

An action that writes to one of its **input** files on a BuildBuddy executor
modifies the executor's file cache entry for that digest. Every later action on
the same executor that consumes the same digest receives the modified bytes,
while Bazel and the CAS still consider the file pristine.

The cache entry is hardlinked into the action's workspace
(`enterprise/server/remote_execution/filecache/filecache.go`, default
`--executor.local_cache_always_clone=false`), so a write through the hardlink
lands in the cache.

## Layout

- `input.txt` – the pristine input.
- `//:corrupt_direct` – appends to `input.txt`, one of its own inputs.
- `//:corrupt_via_symlink` – same, but writes through a symlink created in
  scratch space (how our lint patcher triggered this in production).
- `//:observe_NN` – 24 read-only consumers of `input.txt`, ordered after the
  corrupting actions. They should all see the pristine content.
- `check.sh` – compares each observer's output with `input.txt`.

## Run

    cp user.bazelrc.example user.bazelrc   # add the API key
    bazel build --config=remote //:all
    ./check.sh

`--noremote_accept_cached` is set so every run re-executes all actions.
To start from a digest no executor has seen yet, change a character in
`input.txt` between runs.

## Expected vs. actual

Expected: both `corrupt_*.log` files report `write ... failed`, and `check.sh`
prints `ok` for every observer.

Actual (2026-09-26, BuildBuddy Cloud, EU region, first attempt, fresh digest):
both writes succeed, and 12 of the 24 observers print the `CORRUPTED ...` line appended by
one of the corrupting actions:

    before: 4227905353 links=2 mode=755 size=105
    write to input SUCCEEDED
    after:  4227905353 links=2 mode=755 size=170
    ...
    12 observer(s) received modified bytes for a pristine digest.

`links=2` shows the input is a hardlink shared with the file cache, and the
inode does not change across the write. The `hostname` printed by each action is
the per-action container ID, so it does not identify the executor; use the
`worker` field in the invocation's execution metadata to correlate observers
with the executor a corrupting action ran on. Observers on other executors are
fine, which is why this looks random from the client's point of view.

Note: a local (sandboxed) run of the corrupting actions fails the write, as it
should. This only reproduces with remote execution.

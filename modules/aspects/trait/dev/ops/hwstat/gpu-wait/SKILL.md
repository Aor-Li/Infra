---
name: gpu-wait
description: Wait for specific GPUs to become free before launching a GPU job. Use whenever a task cannot start because the GPUs it needs are occupied (by processes, leftover memory, or another arena claim), instead of writing your own nvidia-smi / sleep polling loop.
---

# gpu-wait

Command: `@GPU_WAIT@` (also on PATH as `gpu-wait` on hosts that have the nix profile).

It blocks until every requested card is free, then exits 0. While it waits, it marks
your terminal as **blocked** (OSC 7501), so the user can see in Rex that you are stuck
on GPUs rather than working. A hand-written polling loop shows up as plain "working".

## Usage

```sh
gpu-wait dgx0011:0-7                  # cards 0-7 on dgx0011
gpu-wait dgx0028 dgx0030:0-3          # all cards on dgx0028 + 4 on dgx0030
gpu-wait --max-wait 3600 dgx0011:0,1  # give up after an hour (exit 2)
```

A card counts as free when it has no compute process, uses little memory, and has
no unexpired arena claim. Probes go over ssh every 30 s (`-i SEC` to change). Progress
lines go to stderr.

## Rules

- Wait first, then `arena claim`, then launch. If you claim before waiting, your own
  claim keeps the cards busy and the wait never ends. If a claim already covers
  the cards and it is yours, pass `--ignore-arena`.
- Chain the launch so it starts as soon as the cards free up:
  `gpu-wait dgx0011:0-7 && arena claim … && torchrun …`.
- For long waits, run the whole chain as a background command. It still marks the
  terminal as blocked.
- Exit codes: 0 means free, 2 means `--max-wait` expired, 130 or higher means interrupted.
  Don't launch the job on a nonzero exit.
- Only wait on cards you are allowed to use (see the GPU rules in AGENTS.md).

# PSBBN Mixed Sorter

Lists the PSBBN Game Collection in **one alphabetical order across consoles** instead of one
block per console.

The [PSBBN Definitive Project](https://github.com/CosmicScale/PSBBN-Definitive-Project) groups
the collection by media type: every PS2 game first, then every PS1 game. This patch interleaves
them, so a series split across consoles reads in order:

```
before                          after
------                          -----
Ace Combat 04    (PS2)          Ace Combat 3     (PS1)
Ace Combat 5     (PS2)          Ace Combat 04    (PS2)
Ace Combat Zero  (PS2)          Ace Combat 5     (PS2)
...                             Ace Combat Zero  (PS2)
Ace Combat 3     (PS1)          Akumajou Dracula X (PS1)
Akumajou Dracula X (PS1)        Alone in the Dark  (PS2)
```

Launchers (Open PS2 Loader, POPSLoader, BB Navigator, HOSDMenu) stay pinned at the top and
apps stay at the bottom — only games are interleaved.

## Install

Run inside the WSL/Linux environment where the toolkit lives:

```bash
git clone https://github.com/SalustianCreativeLabs/PSBBNMixedSorter.git
cd PSBBNMixedSorter
./install.sh
```

Then run the PSBBN menu → **4** (Install Games and Apps) → **2** (Add). The collection is
rebuilt with the new order.

If the toolkit is not auto-detected:

```bash
./install.sh --toolkit ~/PSBBN-Definitive-Project
```

Other commands:

```bash
./install.sh --status   # is the patch applied?
./install.sh --revert   # restore the pristine Game-Installer.sh
```

## Reapplying after a toolkit update

The PSBBN launcher runs `git pull --ff-only` on the toolkit every time it starts, which
discards the patch. Reapply it **after** the launcher has updated the toolkit and **before**
installing games:

1. Start the launcher, let it update, then quit at the main menu.
2. `./install.sh`
3. Start the launcher again → menu 4 → type 2.

`install.sh` is idempotent, so running it when already patched is a no-op.

## How it works

Display order in the Game Collection is the order of `scripts/tmp/selected.list`. The console
performs **no sorting at runtime** — `info.sys` carries no index field (`release_date` and
`genre` are written empty), and the `.NN.` in `PP.<SERIAL>.NN.<NAME>` is a per-serial duplicate
counter, not a sort key.

The chain:

```
ps1.list / ps2.list / smb-pops.list / app.list   each sorted by list-sorter.py
   -> cat                                        titles.list
   -> game-selector.py                           re-buckets by media type (field 4)
   -> selected.list                              order = section order x in-section order
   -> create_game_partitions()  tac              reversed
   -> mkpart, 8 MB each                          physical APA table order
   -> console renders reverse-APA                back to selected.list order
```

The grouping originates in `game-selector.py`, which buckets entries into fixed sections
(`ps2`, `ps1`, `smb`, `launchers`, `apps`). `#SECTION_ORDER=` in `exclude.list` can reorder
those sections but never merge them.

So the patch inserts one block right after the selector runs: split `selected.list` by media
type, sort **only** the games with the toolkit's own `list-sorter.py`, concatenate back. That
reuses upstream's title normalisation, roman numerals and series grouping (`overrides`,
`truncate_prefixes`) rather than reimplementing a sorter.

What it deliberately leaves alone:

- **the `tac`** in `create_game_partitions()` — load-bearing for the console's reverse render
- **`ps1.list` / `ps2.list`** — still read afterwards for PS2 VMC creation and POPS handling
- **the `cat`** that builds `titles.list` — inert, since the selector re-buckets regardless of
  input order

### Failing safe

`install.sh` anchors on the `game-selector.py` invocation and asserts the `fi` that follows it.
If upstream restructures that code, the patch is **not** applied: it warns and exits 2. The
collection reverts to console grouping — nothing breaks. The patched file is also validated
with `bash -n` before replacing the original, and a `.pristine` copy is kept for `--revert`.

## Requirements

The toolkit's own dependencies — `python3` with `natsort` (the PSBBN venv provides it), plus
`awk` and `bash`. No additional packages.

## Credits

Built on the [PSBBN Definitive Project](https://github.com/CosmicScale/PSBBN-Definitive-Project)
by **CosmicScale**. The sorting itself is upstream's `list-sorter.py`; this repository only
changes *which list* gets sorted. All credit for the toolkit and the sorter belongs there.

## License

GPL-3.0-or-later, matching the upstream project this patch derives from. See [LICENSE](LICENSE).

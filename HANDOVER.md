# Handover: NixCon 2026 talk — "Advanced NixOS Integration Test Scenarios"

Status as of 2026-09-26: content fully migrated from `story.md`, all diagrams built,
closing slide done. Remaining work is mostly polish + 3 screenshots.

## Getting started in a fresh session

```
cd slides
nix develop ..              # devShell with nodejs, pnpm, d2 (defined in ../flake.nix)
pnpm install                 # first time only, deps already in pnpm-lock.yaml
pnpm exec slidev --port 3030 # dev server with live reload
```

Open http://localhost:3030. `slides/slides.md` is the deck; edits hot-reload.

If the dev server ever shows stale content that a file edit should have fixed
(this happened a few times this session — a duplicate-looking slide, unchanged
CSS), it's almost always a Vite/Slidev cache issue, **not** a bug in the file.
Fix:
```
pkill -f "slidev --port 3030"          # or however you started it
rm -rf slides/node_modules/.slidev slides/node_modules/.vite
nix develop .. --command pnpm exec slidev --port 3030 --force
```
To get ground truth on what Slidev actually parsed (bypassing the browser
entirely), run this from `slides/`:
```
nix develop .. --command node -e "
const fs = require('fs');
const { parseSync } = require('@slidev/parser');
const parsed = parseSync(fs.readFileSync('slides.md','utf-8'), '.');
parsed.slides.forEach((s,i) => console.log(i+1, JSON.stringify(s.frontmatter||{}), '->', (s.content.match(/^#+\s+(.*)$/m)||[,'(no heading)'])[1]));
"
```

## Repo layout

- `flake.nix` — devShell: `nodejs`, `pnpm`, `d2`. Everything below assumes you're
  inside it (`nix develop` from repo root, or `nix develop ..` from `slides/`).
- `story.md` — the original content/figure spec this deck was built from. Now
  mostly historical; `slides/slides.md` is the source of truth going forward.
- `slides/` — the Slidev project.
  - `slides.md` — the deck, one `story.md` section per slide (mostly).
  - `style.css` — **global** CSS overrides (see "Slidev gotchas" below for why
    this file exists instead of `<style>` in slides.md).
  - `diagrams/*.d2` — D2 sources for every figure (see next section).
  - `public/diagrams/*.svg` — rendered output of the above, embedded via plain
    `<img src="/diagrams/xxx.svg" class="mx-auto max-h-NN" />` in slides.md.
  - `public/img/` — real screenshots (`secunet_edge.png`, `usbvfiod_repo.png`).
    Three more are still needed — see "Outstanding TODOs".
- Repo-root `*.nix` files (`chv.nix`, `minimal.nix`, `xen_minimal.nix`, etc.) —
  the user's own working examples, referenced by some slides' narrative but not
  read/managed by me during this session. Leave alone unless asked.

## Diagram workflow (the part you asked me to emphasize)

All figures are **D2** (https://d2lang.com), not hand-drawn images, so they're
plain text and easy to tweak.

### Shared style: `diagrams/style.d2`

Every figure file starts with `...@style` (D2's import/spread syntax — pulls in
`style.d2`'s `vars` and `classes` blocks as if pasted inline). This is what
keeps every figure visually consistent. The classes:

| class | meaning | look |
|---|---|---|
| `host` | outermost physical/VM boundary | gray box |
| `vm` | a VM (can nest inside another `vm`) | white box, blue border |
| `service` | a service/daemon/virtual device inside a VM | light-blue box |
| `process` | an active process/actor (test driver, usbvfiod, ssh) | oval |
| `socket` | a connection point (unix socket, NIC, device file) | orange diamond |
| `device` | **real physical hardware** (keyboard, USB stick actually plugged in) | dashed box |
| `control` | solid command/data edge | gray line |
| `network` | a network link | dashed blue line |
| `problem` | broken/incorrect connection, used once (Xen console mixup) | red bold line |

**Important distinction already got mixed up once this session:** `device`
means *real* hardware; anything QEMU-*emulates* (an emulated USB stick, a
virtio console) should be `service`, not `device`, even though it's not a
real service daemon. Check this if you add a new figure with emulated
hardware.

`vars.d2-config` in `style.d2` sets `layout-engine: elk` (handles nested
containers better than the default dagre) and `theme-id: 0`.

### Rendering

From `slides/`:
```
nix develop .. --command d2 diagrams/<name>.d2 public/diagrams/<name>.svg
```
No build step needed beyond that — Slidev just serves the SVG as a static
asset. There's no "render all" script yet; if you're touching `style.d2` and
need to re-render everything, a one-liner is:
```
for f in diagrams/*.d2; do
  [ "$(basename "$f")" = style.d2 ] && continue
  nix develop .. --command d2 "$f" "public/diagrams/$(basename "$f" .d2).svg"
done
```
(Worth turning into a real script/justfile if you end up doing this often.)

### The 6 figure families

Figures that build up across several slides were **built fullest-version
first, then trimmed down** for the earlier/simpler slides in that sequence
(the user's call, and it worked well — trimming a complete diagram is much
easier than growing one incrementally while keeping layout stable).

1. **VM basics**: `single-vm.d2` → `multi-vm.d2` (adds a second VM + network)
2. **usbvfiod core**: `usbvfiod-basic.d2` → `usbvfiod-chv.d2` (adds the CHV VM on the far end of the socket)
3. **QEMU native USB** (standalone): `qemu-usb-native.d2`
4. **secunet edge** (standalone): `secunet-edge.d2`
5. **Nested CHV chain** (the big one, 4 steps): `nested-chv-1-boot.d2` →
   `nested-chv-2-ssh.d2` → `nested-chv-3-usbvfiod.d2` → `nested-chv-4-full.d2`
   (full version built first, others are `full` with things removed)
6. **Test-driver console setup**: `test-driver-console-noxen.d2` (working
   case) and `test-driver-console-xen.d2` (the `/dev/hvc0` vs `/dev/hvc1`
   mixup, built as its own thing rather than derived, since it's a rename/
   remap, not a strict subset)

Plus one standalone: `fdo-protocol.d2` (4-actor DI/TO0/TO1/TO2 flow — this is
a diagram instead of a screenshot, deliberately, since it's a protocol flow
not a UI).

### D2 gotchas learned this session

- **Don't connect a container to its own descendant.** E.g. `machine <->
  machine.chv.sshd` (where `chv` is nested inside `machine`) renders as an
  ugly self-loop that exits and re-enters the box. Fix: add a small sibling
  "connection point" node instead (see `net0` in `nested-chv-4-full.d2`) and
  connect *that* to the descendant — same visual result, clean routing.
- `direction: right` (set per-file, right after `...@style`) makes figures
  wide instead of tall, which fits a 16:9 slide much better than D2's default
  top-down layout.

## Slidev gotchas learned this session

- **The leading frontmatter block IS slide 1's frontmatter.** Don't put
  `theme:`/`title:`/etc. in one `---...---` block and then a separate
  `---\nlayout: cover\n---` block right after for the title slide — that
  makes an invisible empty slide 1 and pushes your real cover to slide 2.
  Merge `layout: cover` into the same top frontmatter block instead (already
  fixed, just don't reintroduce it).
- **`<style>` tags inside slides.md are scoped to that one slide only**, not
  global. Global CSS goes in `slides/style.css` (auto-loaded by Slidev's
  `styles/index.{css,ts,js}` / `style.{css,ts,js}` convention — no config
  needed, just having the file there is enough). Current contents:
  extra `h2` bottom margin (with a `.compact` override class for
  code-heavy slides — see `class: compact` in slides.md frontmatter), and
  `ul + :where(:not(ul, ol, li))` for a little breathing room between a
  bullet list and whatever follows it (image/code), *without* adding space
  between bullets themselves (the naive `ul + *` version did affect bullets
  in some configurations — stay with the `:not()` form).
- **Icon syntax uses hyphens, not colons.** `<simple-icons-nixos />` works;
  `<simple-icons:nixos />` silently renders as literal text (colons aren't
  valid in custom-element names, so Slidev's markdown parser doesn't
  recognize it as a component — and it does NOT error, it just prints the
  tag as text, which is easy to miss). Always sanity-check new icons with a
  real `pnpm exec slidev build` (errors clearly if the icon name is wrong)
  rather than trusting the dev server, which won't complain either way until
  you actually navigate to that slide.
- **Icon sets must be an explicit devDependency**, e.g. `pnpm add -D
  @iconify-json/simple-icons`. There's no automatic fetch-on-demand; an
  unresolved icon fails the build with `Icon 'collection/name' not found`.
  Use https://icones.js.org or `curl -s "https://api.iconify.design/search?query=X"`
  to find the right collection/name before wiring it up.
- The built-in `layout: image` (full-bleed background image) defaults to
  `backgroundSize: cover`, which crops. We ended up not using this layout at
  all — every screenshot is a normal `<img>` under a heading instead, for
  visual consistency with the rest of the deck (see the usbvfiod repo slide).

## Outstanding TODOs

Three screenshots still need to be captured and dropped in
`slides/public/img/`, replacing the dashed placeholder boxes already in
slides.md:

| Slide (search `slides.md` for) | Save as |
|---|---|
| "xenmux repository" | `public/img/xenmux_repo.png` |
| "go-fdo-server repository" | `public/img/go-fdo-server_repo.png` |
| "quick-start guide" | `public/img/go-fdo_quickstart.png` |

Once dropped in, replace the `<div class="border-2 border-dashed ...">TODO...</div>`
block on that slide with `<img src="/img/<name>.png" class="mx-auto max-h-NN" />`
(match the sizing convention used elsewhere — `max-h-70` to `max-h-85` depending
on whether there's bullet text above it too).

## Content notes (context for future edits)

- Repeated identical headings across consecutive slides (e.g. three slides
  titled "cloud-hypervisor Guest" in a row) are intentional — it's the
  standard "keep the title stable while content advances" pattern, not a
  mistake.
- `pkgs.linux.target` in the "cloud-hypervisor Guest" service snippet is
  correct as of nixpkgs PR #530133 (kernel config moved from
  `stdenv.hostPlatform.linux-kernel.target` into the kernel package itself).
  Looked wrong at first glance — it isn't, verified against the PR.
- Backticks were deliberately removed from `cloud-hypervisor`, `usbvfiod`,
  `xenmux`, `go-fdo-server`, `go-fdo-client` everywhere they appeared as
  inline code spans in prose/headings (kept on the small set of things that
  are genuinely device paths / log strings: `` `backdoor.service` ``,
  `` `/dev/hvc0` ``, `` `vm_host` ``, `` `system.build.vm` ``, etc.). If you
  add new prose mentioning the stripped terms, match that convention (no
  backticks) for consistency.

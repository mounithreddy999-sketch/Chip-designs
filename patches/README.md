# Vendored-library patches

`rtl/axi` is an embedded checkout of [alexforencich/verilog-axi](https://github.com/alexforencich/verilog-axi)
(at commit `516bd5d`). We don't own that remote, so local modifications to it can't be
pushed upstream and aren't captured by this repo's gitlink pointer. We record them here
as patches instead, so they survive a fresh clone.

## `axi_ram_init_file.patch`
Adds an `INIT_FILE` parameter to `axi_ram.v`. When non-empty, the RAM is preloaded with
`$readmemh(INIT_FILE, mem)` in the `initial` block — lets us boot a program/data hex image
into the AXI RAM for SoC simulation without external bus writes.

Apply (from repo root) after checking out the submodule:

```sh
git -C rtl/axi apply ../../patches/axi_ram_init_file.patch
```

Verify it's already applied: `git -C rtl/axi diff rtl/axi_ram.v` should match this patch.

# Custom Diagnostic Testers



## Building

### Build All Tests
```bash
make
```

### Clean Build Artifacts
```bash
make clean
```
Removes all compiled binaries and intermediate files.


### Build System
- `Merlin32_v1.2_b2/` - Complete Merlin32 cross-assembler toolchain
- `cp2_1.1.0_linux-x64_sc/` - CiderPress2 disk utility for ProDOS images

## Development

The build system uses:
- **Merlin32** v1.2 beta 2 for 65816 assembly  https://brutaldeluxe.fr/products/crossdevtools/merlin/
- **CiderPress2** for disk image management https://github.com/fadden/CiderPress2/blob/main/Install.md


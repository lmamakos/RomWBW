# RomWBW port for the MiSTer FPGA system

This project is a port of RomWBW to add support for the MiSTer FPGA
game system.  The MiSTer system is Z80 based, has 128 MB of SDRAM and
64 KB of Block RAM, along with an MMU that's compatible with the MM_Z2
support (though on different ports).  That project is called **MrZ80**
and is developed in a seperate git repo.


## Port status

- Platform ID: `PLT_MRZ80` (29) in `Source/HBIOS/hbios.inc`
- Config files: `Source/HBIOS/cfg_MRZ80.asm` and
  `Source/HBIOS/Config/MRZ80_std.asm`
- Build: `cd Source/HBIOS && ROM_PLATFORM=MRZ80 ROM_CONFIG=std bash Build.sh`
  produces `Binary/MRZ80_std.rom` (plus `.upd` and `.com`).
- The 512K `MRZ80_std.rom` **is** the .BIN file the MrZ80 FPGA loads:
  4 x 32K HBIOS banks (HBIOS, loader/OS, apps, utils) followed by the
  384K ROM disk.  Rename it to `.bin` if the MiSTer tooling requires
  that extension.
- CP/M apps ship on the hard disk images, not in the ROM: `Binary/Apps/*.com`
  are packed by `make -C Source/Images` into the per-distro slices
  (`hd1k_cpm22.img`, `hd1k_cpm3.img`, ...) and then concatenated into the
  aggregates `hd1k_combo.img` and `hd1k_all.img`, which is what gets copied to
  the SD card.  Rebuild both levels after changing an app, and copy the results
  to `Binary/`.  Since 7017ab05 the aggregates depend on the slices they
  contain; before that an app change refreshed the slices and left stale
  aggregates behind, so a freshly built image could still hold the old program.
  To replace a mounted image cleanly, move the old file aside and write a new
  one (the core keeps the renamed inode open).


## Design decisions

- 512K "ROM" = the .BIN image the FPGA loads into SDRAM at physical
  address 0 (16K pages 0-31).  2048K "RAM" = the SDRAM immediately
  above it (pages 32 and up).  This is the standard Z2 layout with a
  larger RAM, so the standard `MM_Z2` memory manager is reused
  unmodified:
  - Frame registers `MPGSEL_0..3` = I/O ports 0xB0-0xB3
  - `ROMSIZE=512` / `RAMSIZE=2048` make all of the standard bank math
    work: `HBX_BNKSEL` adds `ROMSIZE/32` (16 banks) for RAM, and the
    common top-32K maps to the last two pages of RAM.
- MMU initialization (the MM_Z2 section of `Source/HBIOS/hbios.asm`)
  runs the standard setup (ROMBOOT low-page writes + common-area
  frame 2/3 setup), except the `OUT (MPGENA),A` enable write is
  skipped for `PLT_MRZ80` because the MrZ80 MMU is always enabled.
  `MPGENA` is additionally pointed at 0xBD, a reserved write-ignored
  port in the MMU window, as belt-and-suspenders.
- The FPGA preloads the .BIN into SDRAM and starts the Z80 at logical
  0x0000 with the boot ROM already disabled, so no write to the 0x38
  ROM-disable port is needed.
- Consoles = the stock ACIA (6850) driver, two units (`ACIACNT=2`):
  unit 0 = the serial port (bufferedUART, base 0x82, the boot console)
  and unit 1 = the video terminal + keyboard (SBCTextDisplayRGB, base
  0x80).  Both devices emulate the 6850 master reset that `ACIA_DETECT`
  relies on (MrZ80 R44: control bits 1:0 = 11 -> status 00 until the
  next control write).  `AUTOCON` lets a key pressed on either at the
  loader prompt take the console.  The video terminal sends VT100/xterm
  sequences for the arrow, Home/End, Ins, Page and function keys and 1B
  for Esc.  (Before MrZ80 R44 the console was the SSER simple serial
  driver on 0x82/0x83; its settings are still in `cfg_MRZ80.asm`,
  disabled.)
- The baud rate is set in the MiSTer OSD, not in software, so
  `DEFSERCFG` is report-only.  `ACIA0CLK`/`ACIA1CLK` are set to 153600
  (9600 x 16) only so that the driver's baud-rate check accepts 9600
  with its divide-by-16 setting; the video terminal has no baud rate.
- `INTMODE=1`: three sources drive the Z80 `INT` pin, ANDed (active low)
  in the MrZ80 core: the IntervalTimer (`Components/TIMER/IntervalTimer.vhd`,
  ports 0xD0-0xD3) and the two ACIAs' interrupt outputs (MrZ80 commit
  `6dc802c`).  Each handler in the IM1 call list checks its own device's
  status and returns "not handled" if the request is not its own, so they
  share the level interrupt.  Disk I/O is still polled.  The timer is
  driven by its own HBIOS module,
  `Source/HBIOS/itim.asm` (enabled by `ITIMENABLE`, base `ITIMIO`), which
  follows the `sctim.asm` pattern: PREINIT stops the timer, probes it by
  reading back the INTERVAL registers and hooks `ITIM_INT` into the IM1 call
  list; INIT programs INTERVAL = 1000 / `TICKFREQ` ms and starts it
  periodic (auto-restart).  `ITIM_INT` acknowledges the level interrupt and
  chains to `HB_TIMINT`, which maintains `HB_TICKS`/`HB_SECS` (SYSGET TIMER,
  boot timeout).  `TICKFREQ` must divide 1000 (default 50 Hz = 20 ms);
  other values fail the build.  A missed tick (interrupts masked > 1
  interval) sets the sticky OVERFLOW status bit but is not compensated.
  Wall-clock time comes from the DS12887 via the stock DS12RTC driver
  (`DS12RTC_BASE`=0x70).  The CPU runs at 10 MHz (50 MHz core clock
  divided by 5).
- `ACIAINTS=TRUE` (commit `9f384430`): interrupt driven ACIA receive,
  where input is taken from the IM1 call list into the driver's ring
  buffer.  `ACIAINTS` (new in `acia.asm`, default TRUE in
  `cfg_MASTER.asm` so other platforms are unchanged: RC2014_std.rom is
  byte-identical) was added when the ACIAs' INT outputs were not yet
  wired: with `INTMODE=1` the driver would then have waited for receive
  interrupts that never came, so `cfg_MRZ80.asm` set it FALSE to keep the
  ACIAs polled.  Set it FALSE again to go back to polling (for example on
  an older MrZ80 core without the ACIA INT wiring).
- Sound = the stock AY driver (`ay.asm`) with `AYENABLE=TRUE`,
  `AYMODE=AYMODE_COLECO`, `AY_CLK=1789772`.  The MrZ80 has two YM2149s
  (`Components/PSG/MrZ80_PSG.sv`, MrZ80 `HARDWARE.md` "PSG sound"):
  device 1 at 0x50 (select) / 0x51 (data) is exactly the Coleco port
  layout, and the PSG runs at the MSX clock, so the driver needs no
  changes.  Its probe (write R2 = 55h, read it back from 0x51) finds the
  chip; the boot banner shows `AY: MODE=COLECO IO=0x50`.  RomWBW drives
  only one AY; device 2 at 0x68 (select) / 0x60 (data) is for software
  that knows about it (vibetune: VTUNECFG dual-card, second card "EB").
  Both ports of each pair read back the selected register.  Stereo
  panning (Mono/ABC/ACB) is an MrZ80 OSD option, not a RomWBW setting.
  Note that TUNE.COM does its own chip detection on top of the driver: it
  writes R2 = 0AAh and reads it back from the third column (RIN) of its
  config table.  Every Coleco row there uses 0x52, the RC Sound Module's read
  port, which the MrZ80 does not decode, so the platform-29 row uses
  RIN = 0x51 instead - the chip answers reads on both ports of its pair.
  With that row present plain `TUNE file.pt3` finds the chip too, verified on
  hardware 2026-11-04 (`TUNE VICTORY.PT3` prints
  `MrZ80 YM2149 PSG (50H/51H), timer mode` and plays); `-coleco` (which skips
  the probe) and `--hbios` (which plays through the driver) work either way.


## MrZ80 I/O ports used by RomWBW

| Port(s) | Function |
|---------|----------|
| `0x38`  | ROM-disable trigger. Any write disables the boot ROM at 0x0000-0x1FFF. Not needed when the .BIN is preloaded (ROM is already off). |
| `0x50`-`0x51` | PSG device 1 (YM2149): 0x50 register select, 0x51 data; both read the selected register. Driven by `ay.asm` (`AYMODE_COLECO`). Select values 0x80-0x99 reach the MrZ80 stereo mixer registers (not used by RomWBW). |
| `0x60`, `0x68` | PSG device 2 (YM2149): 0x68 register select, 0x60 data. Not used by RomWBW (vibetune's "EB" second card). |
| `0x80`  | Video terminal + keyboard (6850 model): status (read) / control (write). ACIA unit 1. |
| `0x81`  | Video terminal: keyboard (read) / display (write). |
| `0x82`  | bufferedUART: status (read) / control (write). ACIA unit 0. |
| `0x83`  | bufferedUART: data. |
| `0x88`-`0x8F` | SPI SD card controller (`sd_controller.vhd`), driven by `mrz80sd.asm` (unit 2 of the MRZ80SD driver, `MRZ80SDCNT=2`). No size registers; capacity comes from `MRZ80SD1BLKS` (default `$FFFFFF`, set it to the real card size: a read past the card end hangs the controller until reset). Status bit 4 = init busy (stays set when no card is present). |
| `0x90`-`0x97` | HPS image block device (`hps_blockdev.vhd`), driven by `mrz80sd.asm` (unit 1 of the MRZ80SD driver). Size registers at +5..+7. |
| `0xB0`-`0xB3` | MMU frame 0-3 page registers, low byte (Z2-compatible). |
| `0xB4`-`0xB7` | MMU frame 0-3 page registers, high byte (pages > 255; unused here since the max page number is 63). |
| `0xB8`-`0xBC` | MMU direct-access window (4 pointer bytes + data port; unused). |
| `0xBD`-`0xBF` | MMU reserved (reads 0, writes ignored). `MPGENA` is set to 0xBD. |
| `0xD0`-`0xD3` | Interval timer / Z80 `INT` source (`IntervalTimer.vhd`), driven by `itim.asm` (`ITIMIO`). INTERVAL lo/hi at +0/+1, CONTROL (w) / STATUS (r) at +2, COMMAND (w) / STATUS (r) at +3. Level interrupt; STATUS bit 3 = INTREQ, ACK = COMMAND bit 1. |


## Technical background details

More detail about the hardware implementation of the MrZ80 system is
available in ../MrZ80/HARDWARE.md that describes the memory layout
and various peripherals.

### MMU

The MMU maps 16K memory segments into 4 frames. The MMU is
compatible with the MM_Z2 in the basic ways.  The differences come
from supporting a 256MB address space, where the 128 MB of SDRAM
occupies the region starting at physical address 0, and the small
Block RAM starts right above it at the 128 MB mark.  The 8 bits
available in each of the page frame registers is not sufficient to
map all the address space, so there are additional registers to
allow the remaining address bits to be specified.

When writing the low bits of a page frame offset, the high bits are
zeroed, and then a subsequent write can supply those.  If only the
lower part of the address space is required, then the existing
Z2-compatible mapping registers are all that are required.

### ROM software

The FPGA loads an up to 512K long .BIN file into SDRAM at physical
address 0 and sets up the MMU so that the first 16K of Z80 logical
memory maps to the loaded image (reset mapping: frame 0 -> SDRAM
page 0, frames 1-3 -> SDRAM pages 1-3).  The boot ROM (in the 64K
Block RAM at physical 0x8000000) is disabled whenever the SDRAM
image is preloaded and execution starts at logical 0x0000.

### RAM disk

The 2048K of RomWBW RAM occupies the SDRAM immediately above the 512K
ROM image (starting at page 32).  The build reports 16 ROM banks (12 of
them the 384K ROM disk), 64 RAM banks (48 of them the 1536K RAM disk)
and 11 application banks.

### Serial ports

There are 3 emulated serial ports available.  The MiSTer OSD
(on-screen display) menus are used to specify the baud rate.  It's
not possible to presently set the baud rate, bits per character or
parity from code.  This may change in the future.

The port wired into the Z80 I/O space is the `bufferedUART`
(../MrZ80/Components/UART/bufferedUART.vhd): a 6850 ACIA compatible
device with a 64-byte RX FIFO and hardware flow control.  It is 8N1
only with no parity.  Note that it only transmits when `n_cts` is
low; `n_dcd` is hardwired low but `n_cts` comes from the FPGA pin.


## Future work / TODO

- Sound: hardware-test vibetune single-chip and dual-card.  Plain
  `TUNE file.pt3` (auto-detect) and `TUNE file.pt3 -coleco` both play on
  hardware (2026-11-04).  A second AY driver instance for device 2
  (0x68/0x60) would need `ay.asm` changes; not planned.

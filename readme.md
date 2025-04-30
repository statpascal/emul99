# Emul99

Emul99 is a simulator of the TI 99/4A home computer, implemented in the
Pascal programming language and giving special focus on TI's UCSD P-code
system. It uses GTK3/Cairo and SDL2 for graphics and sound and can be
compiled with the Free Pascal Compiler (Delphi mode) under Linux and MacOS.

Emul99 provides the following features:

- Emulation of console with 32K extension/SAMS with 16 MByte
- Hotkeys to change speed of simulated system (for compiling large programs)
- Emulation of RS232 card
- P-code card with optional 80 column/internal VDP dual screen
- Transfer tool for text files between host system and UCSD disk images
- Several disk systems:
  * DS/SD floppy controller with original DSR ROM using 90/180 KByte sector images
  * Program/data files in TIFILES format in host system directory
  * DSR for P-code system with disk images of up to 16 MByte
- TiPi access via its WebSocket interface
- Cassette input/output using WAV files


## Compiling Emul99

To compile the simulator, a recent version of the Free Pascal Compiler
(3.2.2 is recommended) and the GTK3, SDL2 and C library need to be
installed. Examples for some systems are:

- Debian/Raspberry Pi OS

    apt-get install fpc libgtk-3-dev libsdl2-dev

- Ubuntu/Linux Mint

    sudo apt install fp-compiler libsdl2-dev libgtk-3-dev build-essential

- MacOS

    brew install fpc sdl2 gtk+3

  The path to the installation directory (BREW_BASE) needs to be set to the
  base directory of Homebrew in the build script "compile-fpc.sh".

Executing the build script "compile-fpc.sh" generates the binaries "emul99"
(the simulator) and "ucsddskman" (a disk image manager for UCSD text files)
in the "bin" directory. The assembly of the DSR ROMs for the simulated
devices and the dummy ROM is optional; these binaries are included in the
distribution.

Changing to the "bin" directory and executing "emul99" starts the simulator
with a simple dummy ROM image displaying a message.

The simulator is developed and tested using the following environments:

- openSuse Tumbleweed (x64): main development system
- Raspberry Pi OS (Debian bookworm) on Pi 4
- Linux environment of ARM Chromebook (Debian bookworm)
- MacOS 14 Sonoma (x64)


## Configuration

The simulator is configured using text files which can be loaded by giving
them as command line arguments; e.g.  "emul99 exbasic.cfg".  If no argument is
given, the default file "ti99.cfg" is used.  All options available are shown
and described in "example.cfg".

Options may also be specified on the command line, overriding
previous values (except P-code GROM files). E.g., to apply the "Disk Manager" to a
a disk different from the one given in the config file the command

    bin/emul99 bin/diskman.cfg fdc_dsk1=diskimages/disk1.dsk

may be used.
Pathes given in config file are relative to the location of the config file while pathes
provided on the command line are relative to the current working directory.

It is not possible to change any part of the configuration (e.g., disk
images or cartridges) while the simulator is running. This can be mitigated
by running multiple instances with different configurations simultaneously
on the same disk images (see below).


## ROM files

The original ROMs are copyrighted and cannot be distributed with the
simulator. For a working setup, at least the console ROM and GROMs (combined
into a single file and padded to 8 KB) are required. All config files in the
bin directory include "common.cfg" which loads these ROMS.

    cpu_freq = 3000000
    console_rom = ../roms/994aROM.Bin
    console_groms = ../roms/994AGROM.Bin

Additional ROMs that can be utilized are 

- the original disk controller DSR,
- the DSR of the TiPi (included in the package), 
- the DSR of the RS232 card,
- the ROMs/GROMs of the P-code card.  

The directory "roms" contains a file "roms.txt" showing the file names and
their sizes as they are expected by the various configuration files.

Multiple GROM bases within the console are not supported. Cartridge ROMs
can be bank switched and inverted (option "cart_inverted"). 
For a bank switched ROM, either multiple
8 KB files (e.g., the card_rom entries in exbasic.cfg) or a single large
file may be specified.

For example, to load a typical cartridge consisting of a ROM and GROM image,
one would specify

    cart_rom = ../modules/ParsecC.Bin
    cart_groms = ../modules/ParsecG.Bin

For a bank switched cartridge with multiple 8 KB ROM files, this becomes

    cart_rom = ../modules/TI-ExtBC.Bin
    cart_rom = ../modules/TI-ExtBD.Bin
    cart_groms = ../modules/TI-ExtBG.Bin

A large bank switched ROM (like the 512 KB file of the MegaDemo) requires
just

    cart_rom = ../modules/megademo.bin


## System Memory

Without further options, only the console with 16 KByte VDP RAM and the 256
byte scratch pad is simulated. The option "mem_ext" activates either a
standard 32 KByte extension with 

    mem_ext = 2

or a 16 MByte SAMS extension with 

    mem_ext = 1

The older key "mem_32k_ext" can also be used for compatibility with previous
versions of the simulator.

When loading the MiniMemory module, its 4 KByte RAM needs to be activated
seperately with "cart_minimem":

    cart_rom = ../modules/MiniMemC.Bin
    cart_groms = ../modules/MiniMemG.Bin
    cart_minimem = 1

The contents of the MiniMemory RAM are not preserved between different runs
of the simulator.


## Keyboard

Keys are mapped to a standard keyboard.  

- FCTN: ALT-Left (Linux), CMD-Right (Mac)
- Quit: ALT-Left + = (Linux), CMD-Right + = (Mac)
- Alpha Lock: permanently switched off
- First Joystick: 4, 6, 8, 2 in numeric pad, fire button is 0

A line feed in the Terminal Emulator II module is generated with Ctrl+J.
These mappings are defined in
the file "ti99.pas" and can only be modified by editing the source file.

Four function keys are used to change the execution speed of the simulated
system:

| Key | Function |
|-----|----------|
| F5  | restore CPU frequency to value in configuration file (default 3 MHz) |
| F6  |set frequency to 1 GHz (resulting in maximum speed as current systems will not be able to actually achieve this) |
| F7  | decrease CPU frequency by 1 MHz |
| F8  | increase CPU frequency by 1 MHz |

A reset key can be configured using the "reset_key" option; it defaults to
the Pause/Break key. The "magic numbers" are the key codes of GTK3; a rather
incomplete list is e.g. in the source file src/fpcunits/gtk3.pas.

    reset_key = 65299


## Disk access

There are three ways to simulate disk access:

- The original DSR of the 90/180 KB TI disk controller
- Files in TIFILES format in a configurable directory of the host
- Special DSR for P-Code system (see below)

The first option requires the original ROM of the disk controller; using the
config entries "fdc_dsr" and "fdc_dsk1" to "fdc_dsk3" up to three disk
images (92160 bytes for SS/SD, 184320 bytes for DS/SD) can be loaded.  It
provides DSK1 through DSK3 devices. The following example shows a typical
configuration.

    fdc_dsr = ../roms/Disk.Bin
    fdc_dsk1 = ../diskimages/test1.dsk
    fdc_dsk2 = ../diskimages/test2.dsk
    fdc_dsk3 = ../diskimages/test3.dsk

To store files in a host system directory, the config entries "disksim_dsr"
and "disksim_dir" need to be specified.  The DSR in "roms/disksim.bin"
provides DSK0 through DSK3.  

    disksim_dsr = ../roms/disksim.bin
    disksim_dir = ../diskfiles

The host system DSR can be used together with the disk controller DSR: the
latter one uses a lower CRU base resulting in only DSK0 pointing to the host
directory (see e.g. the example config file bin/exbasic.cfg). File names
containing slashes are modified to avoid directory traversal on the host.

Note that the host system DSR does not provide sector based access to the disk or
individual files (only PAB based operations are supported); in particular it
is not possible to get a directory listing.


## TiPi

The TiPi hardware is simulated and can be used with the original DSR ROM (an
assembled version is included in the "roms" directory).  On the Raspberry Pi
side, WebSocket emulation mode needs to be enabled; the file README.md in
the emulation directory of the tipi installation provides further details. 
IP and port of the WebSocket server are set in a config file as shown; see
example.cfg or tipi.cfg for a complete example.

    tipi_dsr = ../roms/tipi.bin
    tipi_addr = 127.0.0.1:9901

Please note that the code does almost no error checking; if the connection
to the WebSocket server cannot be established or gets broken the emulated
system will either freeze or perform a reset. Mouse simulation is not yet
tested and will probably not work.


## P-code simulation

The P-code system uses only sector based disk operations (subroutine >10 of
the DSR) which can address a maximum of 65536 disk sectors with 256 bytes
each. Correspondingly, the P-code system can utilize 32768 blocks with 512
bytes. The pcodedisk DSR (file roms/pcodedisk.bin) makes use of these limits 
to provide disk images of up to 16 MByte and can be used as an alternative
to the original floppy DSR which limits disks to 90/180 KB. Howeever, as it only
supports subroutine >10, it is not very useful in general. It is configured
with the following settings:

    pcodedisk_dsr = ../roms/pcodedisk.bin
    pcodedisk_dsk1 = ../diskimages/ucsd_system_1.dsk
    pcodedisk_dsk2 = ../diskimages/ucsd_dev_1.dsk
    pcodedisk_dsk3 = ../diskimages/ucsd_test.dsk

The images files can be created with dd; e.g. use 

    dd if=/dev/zero of=blank.disk bs=512 count=32768 

to create a disk image of maximal size. A UCSD file system can then be
added from within the P-code system with the "Zero" option of the Filer,
which will ask for the number of blocks on the disk (with 32767 being the
maximum).

A 360 KByte image can hold the complete UCSD system comprising four 90 KB
disks: one can copy all files with the Filer to a single 360 KB image and use it
as first disk.

With 90 KB or 180 KB disk images the original disk DSR may be used as
well:

    fdc_dsr = ../roms/Disk.Bin
    fdc_dsk1 = ../diskimages/ucsd_pascal_compiler.dsk
    fdc_dsk2 = ../diskimages/ucsd_pascal_editor_filer_1.dsk
    fdc_dsk3 = ../diskimages/ucsd_pascal_editor_filer_2.dsk

An internal 80x24 screen image is maintained at memory address 2000h.  The
simulator provides a flag "pcode_screen80" to use this image instead of or
in addition to the output created by the VDP (see ucsd-80.cfg) to display 80
columns of text:

    pcode_screen80 = 1

    ; for dual screen display, use 
    ; pcode_screen80 = 2

With SAMS support enabled, it is assumed that the mapping
of the 3rd memory page (containing the screen buffer) uses the default value
of the transparent mode (is is safe to temporarily use the page for other
purposes).

A simple tool (ucsddiskman) can list the contents of a UCSD disk image and
copy text files between the host system and disk images. It provides the
following options:

    ucsddskman image-name list
    ucsddskman image-name extract ucsd-file local-file
    ucsddskman image-name add ucsd-file local-file
    ucsddskman image-name remove ucsd-file

Files are only added after the last used block. To update an existing text
file in a disk image, it first needs to be removed.

Overclocking the system (cpu_freq setting in the configuration file) might
also be desirable. The example configuration in ucsd-80.cfg uses a fivefold
speed (15 MHz) which is close to making the keyboard unusable. 


## Multiple Instances

Disk images (using the original DSR or the P-code DSR) are memory mapped and
can be shared between multiple instances of the simulator. Changes are
immediately visible to other instances but there is no mechanism to
synchronize them; so data corruption is possible if they are written to at
the same time.

The simulator does not provide a utility to transfer files between standard
TI disk images and the host system. Programs like xdm99 from Ralph Benzinger's
xdt99 tools can be utilized for this task.


## Cassette I/O

The simulator can read and write WAV files (22050 Hz, unsigned 8 bit, mono)
that can be played to or read from a real machine. Because there is no
mechanism to set the position of the tape in the user interface, two
different WAV files are used for input and output (see e.g. exbasic.cfg). 
The input wave file is loaded and analyzed when the simulator starts, so
later changes do not have any effect on a running session. The required
config settings are:

    cass_out = ../diskimages/cass-out.wav
    cass_in = ../diskimages/cass-in.wav

One can store multiple programs and/or data files in an output WAV
file; they have to be loaded again in the same order.

There is no attempt to reconstruct bad recordings from old cassette tapes -
the simulator will consider any input exceeding the ReadThreshold (see
tape.pas) as a toggle of the cassette input.


## Serial/Parallel I/O

Serial emulation requires the original DSR ROM of the RS232C card. Input and
output is redirected to the file system with configurable file names or
named pipes. A named pipe should be used for input data. 

Please note that the current implementation only provides the functionality
used by TI's DSR. Interrupt handling is supported for incoming data as
required by the Terminal Emulator module.

A typical configuration (suited for the P-Code system) is shown in bin/serial.cfg:

    rs232_dsr = ../roms/RS232.Bin

    RS232/1_out = ../REMOUT,nozero
    RS232/2_out = ../PRINTER,nozero,append
    PIO/1_out = ../PIOOUT

    ; A FIFO (named pipe) should be used for input

    RS232/1_in = ../REMIN
    PIO/1_in = ../PIOIN

File names are relative to the configuration directory (bin). 
Two options can be added to output filenames:

- nozero: will not output any zero bytes. This is useful when transferring text files with the Transfer option of the Filer, which simply copies complete disk blocks including zeroes.
- append: appends to an existing file instead of overwriting it.

Files (or FIFOs for input files) will be created if they do not exist.
In UCSD-Pascal, the REMIN FIFO can be read  with the following program:

    program serread;
    var
        f: text;
        ch: char;
    begin
        reset (f, 'REMIN:');
        while not eof (f) do
            begin
                read (f, ch);
                if ch = chr (10) then
                    writeln
                else
                    write (ch)
            end;
        close (f)
    end.

Upon execution, the program will read from the FIFO until an EOF is
signalled with a binary value of 3. E.g. the following Linux commands feed
two lines into the program, followed by EOF:

    echo "This is the first line" > REMIN
    echo "This is the second line" > REMIN
    echo -n $'\x03' > REMIN

In Extended BASIC, the following program is equivalent to the above Pascal
program:

    100 OPEN #1:"RS232/1.EC",INPUT ,DISPLAY ,FIXED 1
    110 LINPUT #1:A$
    120 IF A$=CHR$(10)THEN PRINT ELSE PRINT A$;
    130 IF A$<>CHR$(3)THEN 110
    140 CLOSE #1

It can be sent to the file PRINTER with

    LIST "RS232/2"


## Implementation Notes

The implementation is rather concise (about 5500 lines of Pascal source
code without the UCSD disk manager) and uses libraries when possible. For
example, one can set a sampling rate of 223722 with the SDL and implement
sound output as the attenuator weighted sum of the toggling tone generators.

CPU, VDP and the 9901 timer are interleaved and executed in a seperate
thread; this thread will perform a sleep every millisecond to synchronize
with real time.

The DSRs for the simulated devices (host directory and P-Code disk
system) transform control to the simulator with an "XOP 0" instruction,
specifying the requested operation as a dummy source address. The simulated
TMS9900 dispatches these XOP calls in the file "xophandler.pas" when they
occur in the DSR ROM address range. The high byte of the dummy source address
equals the CRU base of the simulated device (the CRU bases are defined in
types.pas)

Instead of GTK3/Cairo, SDL2 could have been used for graphical output. Yet,
as the simulator serves mainly as a test program for a Pascal compiler, the
additional library is utilized to test its bindings.


## Known Bugs and Limitations

- The unofficial video modes of the VDP might work but remain untested 
  as no software seems to use them.
- The directory based disk DSR does not provide sector based
  access and cannot read directory information. Software requiring this may
  use the original disk controller DSR.
- TI's GROM address counter jumps to the beginning of the respective GROM when
  6K is reached. This behaviour is implemented in "grom.pas" but may be
  incompatible with larger 3rd party GROMs.
- Comparing the performance of a BASIC program with that of a real machine, 
  the simulator is about 5% too fast. 
- The sound generator is sampled about 870 times per second and it is
  assumed that its settings remain unchanged during the sampling interval.
  Changes occuring during that interval should be recorded with a CPU
  timestamp and handled when generating output.
- An infinite recursion of "X" operations crashes the simulator with a stack
  overflow.
- The emulation of the RS232 card provides only the functionality used by TI's DSR.


## Acknowledgements

The simulator would not have been possible without Thierry Nouspikel's
TI-99/4A Tech Pages (http://www.nouspikel.com/ti99/titechpages.htm). 
Whenever something remained unclear, the implementations of Rasmus
Moustgaard's JS99er (https://js99er.net), Mike Brent's Classic99
(http://harmlesslion.com/software/classic99) and Marc Rousseau's TI-99/Sim
(https://www.mrousseau.org/programs/ti99sim) were helpful. Many ideas, e.g. 
implementing the 32K word address space of the TMS9900 as an array of
read/write functions, were taken from JS99er while the wait states for
the memory mapped devices are based upon Classic99.


## License

Copyright 2022 - 2025 Michael Thomas

Emul99 is licensed under the GNU General Public License version 2 - see
the file "COPYING" in this directory for details.

The TiPi DSR ROM (file roms/tipi.bin) is public domain software released
under the Unlicense.

The dummy ROM uses a 5x8 font from X11 which is governed by the MIT license.

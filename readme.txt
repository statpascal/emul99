ti99.pas

ti99.pas is a simulator for the TI 99/4A home computer, implemented in the
Pascal programming language and giving special focus on TI's UCSD P-code
system. It uses GTK3/Cairo and SDL2 for graphics and sound and can be
compiled with the Free Pascal Compiler under Linux.

ti99.pas provides the following features:

- emulation of console with 32K extension
- P-code card with optional 80 column display
- several disk systems:
  * DS/SD floppy controller with original DSR ROM using 90/180 KByte images
  * Program/data files in TIFILES format in host system directory
  * DSR for P-code system with disk images of up to 16 MByte
- cassette input/output using WAV files


Compiling ti99.pas

To compile the simulator, the GTK3, SDL2 and C library need to be
installed. E.g., under Debian 11, this can be achieved with

apt-get install fpc gtk+3 libsdl2-dev

and under Ubuntu 21 with

sudo apt install fp-compiler libsdl2-dev libgtk-3-dev gcc

Executing the build script "compile-fpc.sh" generates the binaries "ti99"
(the simulator) and "ucsddskman" (a disk image manager for UCSD text files)
in the "bin" directory. Changing to the "bin" directory and executing
"ti99" starts the simulator with a simple dummy ROM image displaying a
message.

The simulator is configured using text files which can be loaded by giving
them as command line argument; e.g.  "ti99 exbasic.cfg".  If no argument is
given, the default file "ti99.cfg" is used.  All options available are shown
and described in "example.cfg".

Currently it is not possible to change any part of configuration (e.g., disk
images or cartridges) while the simulator is running. This can be mitigated
by running multiple instances with different configurations simultaneously
on the same disk images (see below).


ROM files

The original ROMs are copyrighted and cannot be distributed with the
simulator. For a minimal setup, at least the console ROM and GROMs (combined
into a single file and padded to 8 KB) are required. 

Additional ROMs that can be utilized are the original disk controller DSR
ROM and the ROMs/GROMs of the P-code card. The latter ones consist of 8
files with the GROMs (6 KB each), a 4 KB file with the lower part of the DSR
ROM and an 8 KB file with the two upper banks. 

The directory "roms" contains a file "roms.txt" showing the file names and
their sizes (as they are expected by the various configuration files).

Multiple GROM bases within the console are not supported. Cartridge ROMs
can be bank switched and inverted. For a bank switched ROM, either multiple
8 KB files (e.g., the card_rom entries in exbasic.cfg) or a single large
file may be specified.


Keyboard

Keys are mapped to a standard PC keyboard.  The function key of the TI 99
keyboard is reached by the right menu key (left of the right control key). 
Alpha Lock is switched off and cannot be activated, but a similar effect can
be obtained by using Caps-Lock on the PC keyboard. The first joystick is
mapped to the keys 4, 6, 8 and 2 in the numeric pad (with NumLock enabled)
and the left "Alt" key is the fire button. These mappings are defined in
the file "ti99.pas" and can only be changed by editing the source file.


Multiple Instances

Disk images (using the original DSR or the P-code DSR) are memory mapped and
can be shared between multiple instances of the simulator. Changes are
immediately visible to other instances but there is no mechanism to
synchronize them; so data corruption is possible if they are written to at
the same time.

The simulator does not provide a utility to transfer files between standard
TI disk images and the host system. Programs like xdm99 from Ralph Benzinger's
xdt99 tools can be utilized for this task.


P-code simulation

The P-code card uses only sector based disk operations (subroutine >10 of
the DSR) which can address a maximum of 65536 disk sectors with 256 bytes
each. Correspondingly, the P-code system can utilize 32768 blocks with 512
bytes. The pcodedisk DSR makes use of these limits to provide disk images
of up to 16 MByte.

The images files can be created with dd; e.g. use 

dd if=/dev/zero of=blank.disk bs=512 count=32768 

to create a disk image of maximal size. A UCSD file system can then be
added from within the P-code sytem with the Filer.

Moreover, an internal 80x24 screen image is maintained at memory address
>2000.  The simulator provides a flag to use this image instead of the
output created by the VDP (see ucsd.cfg) to display 80 columns of text.

A simple tool (ucsddiskman) can iist the contents of a UCSD disk image and
copy text files between the host system and disk images. It provides the
following options:

ucsddskman image-name list
ucsddskman image-name extract ucsd-file local-file
ucsddskman image-name add ucsd-file local-file

Files are only added after the last used block.

Overclocking the system (cpufreq setting) can also be desirable. 


Cassette I/O

The simulator can read and write WAV files (22.050 Hz, unsigned 8 bit, mono)
that can be played to or read from a real machine. Because there is no
mechanism to set the position of the tape in the user interface, two
different WAV files are used for input and output (see e.g. exbasic.cfg). 
The input wave file is loaded and analyzed when the simulator starts, so
later changes do not have any effect on a running session.

One can store multiple programs and/or data files in an output WAV
file; they have to be loaded again in the same order.

There is no attempt to reconstruct recordings from old cassette tapes - the
simulator will consider any input exceeding the ReadThreshold (see tape.pas)
as a toggle of the cassette input.


Implementation Notes

The implementation is rather concise (about 5.000 lines of Pascal source
code without the UCSD disk manager) and uses libraries when possible. For
example, one can set a sampling rate of 223722 with the SDL and implement
sound output as the attenuator weighted sum of the toggling tone generators.

VDP, CPU and sound run independently in seperate threads; the VDP performs a
sleep after every scanline while the CPU does the same after every
instruction. On a slower machine, scanlines containing multiple sprites may
take longer than the available 64 microseconds to render which can cause
problems with code relying on an exact scanline timing.

The timer of the TMS9901 needs to be interleaved with the CPU to
get the required exact timing for cassette operations.  

This approach is sufficient to run the "Don't mess with Texas" megademo but
the output of the recent Copper demo is rather distorted.

The DSRs for the special P-code (pcodedisk.a99) and host system
(disksim.a99) disk simulation need to transform control to the simulator at
some point.  This is done via an "XOP 0" instruction, specifying the
requested operation as a dummy source address.

Instead of GTK3/Cairo, SDL2 could have been used for graphical output. Yet,
as the simulator serves mainly as a test program for a Pascal compiler, the
additional library was utilized to test its bindings.


Known Bugs and Limitations

- The unofficial video modes of the VDP are not supported.
- The directory based disk DSR does not provide sector based
  access and cannot read directory information. Software requiring this may
  use the original disk controller DSR.
. TI's GROM address counter jumps to the beginning of the respective GROM when
  6K is reached. This behaviour is implemented in "grom.pas" but may be
  incompatible with larger 3rd party GROMs.
- Comparing the performance of a BASIC program with that of a real machine, 
  the simulator is about 10% too fast. 
- The noise generator seems to be too shrill; it is probably not yet done
  correctly.
- The recent "Copper Demo" does not work well at all.


Acknowledgements

The simulator would not have been possible without Thierry Nouspikel's
TI-99/4A Tech Pages (http://www.nouspikel.com/ti99/titechpages.htm). 
Whenever something remained unclear, the implementations of Rasmus
Moustgaard's JS99er (https://js99er.net), Mike Brent's Classic99
(http://harmlesslion.com/software/classic99) and Marc Rousseau's TI-99/Sim
(https://www.mrousseau.org/programs/ti99sim) were helpful. Many ideas, e.g. 
implementing the 32K word address space of the TMS9900 as an array of
read/write functions, were taken from JS99er.

The dummy ROM uses a 5x8 font from X11 which is governed by the MIT license.


License

Copyright (C) 2022 Michael Thomas
ti99.pas is licensed under the GNU General Public License version 2 - see
the file "COPYING" in this directory for details.

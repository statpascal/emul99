unit types;

interface

const
    MaxAddress = 65535;
    MaxCruAddress = 4191;
    NumberDrives = 3;
    
    PcodeDiskCruAddress = $1000;    
    FdcCardCruAddress = $1100;
    DiskSimCruAddress = $1200;
    RS232CruAddress = $1300;
    TipiCruAddress = $1400;
    SerialSimCruAddress = $1500;
    SAMSCruAddress = $1e00;
    PcodeCardCruAddress = $1f00;

type
    TCruAddress = 0..MaxCruAddress;
    TCruR12Address = 0..2 * MaxCruAddress;
    TCruBit = 0..1;
    TUint8Ptr = ^uint8;
    TUint16Ptr = ^uint16;
    TDiskDrive = 1..NumberDrives;
    
    TDsrRom = record
        case boolean of
            false: (w: array [$2000..$2fff] of uint16);
            true:  (b: array [$4000..$5fff] of uint8)
    end;

implementation

end.
    

unit types;

interface

const
    MaxAddress = 65535;
    MaxCruAddress = 4191;
    NumberDrives = 3;

type
    TCruAddress = 0..MaxCruAddress;
    TCruR12Address = 0..2 * MaxCruAddress;
    TCruBit = 0..1;
    TMemoryPtr = ^uint8;
    TDiskDrive = 1..3;

implementation

end.
    

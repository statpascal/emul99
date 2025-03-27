unit sdl2;

interface

const
//    libSDL = 'libSDL2.so';

    SDL_INIT_AUDIO = $00000010;
    
    AUDIO_U8       = $0008; 
    AUDIO_S8       = $8008;
    AUDIO_U16LSB   = $0010;
    AUDIO_S16LSB   = $8010;
    AUDIO_U16MSB   = $1010;
    AUDIO_S16MSB   = $9010;
    AUDIO_U16      = AUDIO_U16LSB;
    AUDIO_S16      = AUDIO_S16LSB;
    
type
    SDL_AudioFormat = uint16;
    SDL_AudioCallback = procedure (userdata, stream: pointer; len: int32);
    
    SDL_AudioSpec = record
        freq: int32;
        format: SDL_AudioFormat;
        channels, silence: uint8;
        samples, padding: uint16;
        size: uint32;
        callback, userdata: pointer
    end;
    
function SDL_Init (flags: uint32): int32; external; //  libSDL;
function SDL_OpenAudio (var desired, obtained: SDL_AudioSpec): int32; external; // libSDL;
procedure SDL_PauseAudio (pause_on: int32); external; // libSDL;
procedure SDL_CloseAudio; external; //  libSDL;


implementation

end.
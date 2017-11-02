module gbcsoundcontroller;

pragma(msg, "TODO: import useless");
import std.stdio;
import std.range;
import std.array;
import std.math;
import std.conv;
import std.random;
import std.algorithm;
import std.format;

import interfaces.mmu8b;
import derelict.openal.al;


pragma(msg, "TODO: Only power-of-two frequencies (or those which divide the chosen final frequency) are well played because of the nearest interpolation (frequencies are implicitly adapted to fit well)");
pragma(msg, "TODO: Sound frequency should be arround 2.4% faster on SGB (not done here) causing wrong notes");
pragma(msg, "TODO: See bug with frequency sweeping (cf pokemon silver)");
pragma(msg, "TODO: Check the value of the channel1_volumeEnvelope: test n°1 say 0x00, GCB manual say nothing (default: 0xF3)");
pragma(msg, "TODO: support additionnal Vin (NR50)");
pragma(msg, "TODO: Is there an issue with loop & sweep enabled together ?");
final class GbcSoundController : Mmu8bItf
{
    private:

    enum ClockState
    {
        ENABLED,
        CLOCK_ONCE,
        LOCKED
    }

    struct SoundValue
    {
        // Normalized values in [-1.0f, 1.0f]
        float left;
        float right;
    }

    immutable bool useCgb;
    static immutable uint cpuFrequency = 4_194_304;
    ubyte channel1_sweep = 0x00;
    ubyte channel1_soundLength = 0xBF;
    ubyte channel1_volumeEnvelope = 0xF3;
    ubyte channel1_frequencyLo = 0x00; // Init value undefined
    ubyte channel1_frequencyHi = 0xBF;
    ClockState channel1_internalSweepState = ClockState.LOCKED;
    bool channel1_internalLengthLock = false;
    ubyte channel2_soundLength = 0x3F;
    ubyte channel2_volumeEnvelope = 0x00;
    ubyte channel2_frequencyLo = 0x00; // Init value undefined
    ubyte channel2_frequencyHi = 0xBF;
    bool channel2_internalLengthLock = false;
    ubyte channel3_soundOnOff = 0x7F;
    ubyte channel3_soundLength = 0xFF;
    ubyte channel3_volume = 0x9F;
    ubyte channel3_frequencyLo = 0x00; // Init value undefined
    ubyte channel3_frequencyHi = 0xBF;
    ubyte[16] channel3_wavePatternRam = 0xFF; // Init value undefined
    bool channel3_internalLengthLock = false;
    ubyte channel4_soundLength = 0xFF;
    ubyte channel4_volumeEnvelope = 0x00;
    ubyte channel4_polynomialCounter = 0x00;
    ubyte channel4_control = 0xBF;
    bool channel4_internalLengthLock = false;
    ubyte channelControl = 0x77;
    ubyte soundOutput = 0xF3;
    ubyte soundEnabled = 0xF0; // 0xF1 for GB, 0xF0 for SGB
    float[32768] randomValues;
    uint internalClock = 0;
    static immutable uint clockStep = 32; // Must be a power of two (1=useless, 2=perfect/very-slow, 4..16=good/slow, 32..64=medium/fast, 128+=bad/very-fast)
    static immutable uint maxInternalClock = 4_194_304; // Must divisible by all the frequency used in this module
    static immutable uint bufferCount = 8; // 2: double buffering (minimum & synchronized), 3: triple buffering (medium)... But higher values increase latency
    static immutable uint soundFrequency = cpuFrequency / clockStep; // Generally: perfect=65536, good=48000, medium=32768, bad=16384
    static immutable uint soundBufferSize = 65536 / clockStep * 2; // final buffer size (stereo sound), small values cause performance issues, high values cause a high latency
    uint bufferCur = 0;
    float[4] channelCur = 0;
    ALCdevice* device;
    ALCcontext* context;
    uint alSource;
    uint[bufferCount] alBuffers;
    short[soundBufferSize][bufferCount] soundBuffers;


    public:

    this(bool cgbMode)
    {
        useCgb = cgbMode;

        // DerelictAL initialization

        if(!DerelictAL.isLoaded)
        {
            DerelictAL.load();

            if(!DerelictAL.isLoaded)
                throw new Exception("Unable to load OpenAL");
        }


        // OpenAL initialization

        device = alcOpenDevice(null);

        if(device == null)
            throw new Exception("Unable to find an audio device");

        context = alcCreateContext(device, null);

        if(context == null)
            throw new Exception("Unable to create an audio context using OpenAL");

        alcMakeContextCurrent(context);
        checkErrors();


        // Listener initialization

        alListener3f(AL_POSITION, 0.0, 0.0, 2.0);
        checkErrors("Unable to configure the OpenAL listener");

        alListener3f(AL_VELOCITY, 0.0, 0.0, 0.0);
        checkErrors("Unable to configure the OpenAL listener");

        immutable float[] listenerOri = [0.0, 0.0, 2.0, 0.0, 2.0, 0.0];
        alListenerfv(AL_ORIENTATION, listenerOri.ptr);
        checkErrors("Unable to configure the OpenAL listener");


        // Sound sources initialization

        alGenSources(1, &alSource);
        checkErrors("Unable to create OpenAL sound sources");

        alSourcef(alSource, AL_PITCH, 1.0f);
        checkErrors("Unable to configure an OpenAL sound source");

        alSourcef(alSource, AL_GAIN, 1.0f);
        checkErrors("Unable to configure an OpenAL sound source");

        alSource3f(alSource, AL_POSITION, 0.0, 1.0, 1.0);
        checkErrors("Unable to configure an OpenAL sound source");

        alSource3f(alSource, AL_VELOCITY, 0.0, 0.0, 0.0);
        checkErrors("Unable to configure an OpenAL sound source");


        // Buffers initialization

        alGenBuffers(alBuffers.length, alBuffers.ptr);
        checkErrors("Unable to create OpenAL sound buffers");
/*
        foreach(uint i ; 0..bufferCount)
        {
            alBufferData(alBuffers[i], AL_FORMAT_STEREO16, soundBuffers[i].ptr, cast(int)(soundBuffers[i].length*short.sizeof), soundFrequency);
            checkErrors(format("Unable to bind the data of an OpenAL sound buffer (buffer %d)", i+1));
        }
*/

        // Data and registers initialization

        foreach(int i ; 0..randomValues.length)
            randomValues[i] = uniform(-1.0f, 1.0f);

        if(useCgb)
        {
            channel3_wavePatternRam =   [
                                            0x84, 0x40, 0x43, 0xAA, 0x2D, 0x78, 0x92, 0x3C, 
                                            0x60, 0x59, 0x59, 0xB0, 0x34, 0xB8, 0x2E, 0xDA
                                        ];
        }
        else
        {
            channel3_wavePatternRam =   [
                                            0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF,
                                            0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0xFF
                                        ];
        }
    }

    ~this()
    {
        alSourceStop(alSource);
        alDeleteSources(1, &alSource);
        alDeleteBuffers(alBuffers.length, alBuffers.ptr);
        alcDestroyContext(context);
        alcCloseDevice(device);
    }

    void resetRegisters()
    {
        channel1_sweep = 0x00;
        channel1_soundLength = 0x3F;
        pragma(msg, "TODO: Check the value of the channel1_volumeEnvelope: test n°1 say 0x00, GCB manual say nothing (default: 0xF3)");
        channel1_volumeEnvelope = 0x00;
        channel1_frequencyLo = 0xFF;
        channel1_frequencyHi = 0xBF;
        channel1_internalSweepState = ClockState.LOCKED;
        channel1_internalLengthLock = false;
        channel2_soundLength = 0x3F;
        pragma(msg, "TODO: Check the value of the channel2_volumeEnvelope: test n°1 say 0x00, GCB manual say nothing (default: 0xF3)");
        channel2_volumeEnvelope = 0x00;
        channel2_frequencyLo = 0xFF;
        channel2_frequencyHi = 0xBF;
        channel2_internalLengthLock = false;
        channel3_soundOnOff = 0x7F;
        channel3_soundLength = 0xFF;
        channel3_volume = 0x9F;
        channel3_frequencyLo = 0xFF;
        channel3_frequencyHi = 0xBF;
        channel3_internalLengthLock = false;
        channel4_soundLength = 0xFF;
        channel4_volumeEnvelope = 0x00;
        channel4_polynomialCounter = 0x00;
        channel4_control = 0xBF;
        channel4_internalLengthLock = false;
        channelControl = 0x00;
        soundOutput = 0x00;
        soundEnabled = 0x70;

        if(useCgb)
            internalClock = 0;

        //alSourcei(alSource, AL_BUFFER, 0);
        //checkErrors("Unable to unbind the sound buffer of an OpenAL sound");

        //alSourcePlay(alSource);
        //checkErrors("Unable to play an OpenAL sound");
    }

    ubyte loadByte(ushort address)
    {
writefln("DEBUG: read(address: %0.2X)", address);
        switch(address)
        {
            // Channel 1 Sweep register
            case 0xFF10:
                return channel1_sweep | 0b10000000;

            // Channel 1 Sound length/Wave pattern duty
            case 0xFF11:
                return channel1_soundLength | 0b00111111;

            // Channel 1 Volume Envelope
            case 0xFF12:
                return channel1_volumeEnvelope;

            // Nothing
            case 0xFF13:
                return 0xFF;

            // Channel 1 Frequency hi
            case 0xFF14:
                return channel1_frequencyHi | 0b10111111;

            // Nothing
            case 0xFF15:
                return 0xFF;

            // Channel 2 Sound Length/Wave Pattern Duty
            case 0xFF16:
                return channel2_soundLength | 0b00111111;

            // Channel 2 Volume Envelope
            case 0xFF17:
                return channel2_volumeEnvelope;

            // Nothing
            case 0xFF18:
                return 0xFF;

            // Channel 2 Frequency hi data
            case 0xFF19:
                return channel2_frequencyHi | 0b10111111;

            // Channel 3 Sound on/off
            case 0xFF1A:
                return channel3_soundOnOff;

            // Nothing
            case 0xFF1B:
                return 0xFF;

            // Channel 3 Select output level
            case 0xFF1C:
                return channel3_volume;

            // Nothing
            case 0xFF1D:
                return 0xFF;

            // Channel 3 Frequency's higher data
            case 0xFF1E:
                return channel3_frequencyHi | 0b10111111;

            // Nothing
            case 0xFF1F:
                return 0xFF;

            // Nothing
            case 0xFF20:
                pragma(msg, "TODO: port access allowed in read mode ? tests say no !");
                return 0xFF;

            // Channel 4 Volume Envelope
            case 0xFF21:
                return channel4_volumeEnvelope;

            // Channel 4 Polynomial Counter
            case 0xFF22:
                return channel4_polynomialCounter;

            // Channel 4 Counter/consecutive; Inital
            case 0xFF23:
                return channel4_control | 0b10111111;

            // Channel control / ON-OFF / Volume
            case 0xFF24:
                return channelControl;

            // Selection of Sound output terminal
            case 0xFF25:
                return soundOutput;

            // Sound on/off
            case 0xFF26:
                return soundEnabled;

            // Nothing
            case 0xFF27: .. case 0xFF2F:
                return 0xFF;

            // Wave Pattern RAM
            case 0xFF30: .. case 0xFF3F:
                return channel3_wavePatternRam[address & 0x0F];

            default:
                throw new Exception(format("Execution failure: Out of memory access (read at %0.4X)", address));
        }
    }

    void saveByte(ushort address, ubyte value)
    {
writefln("DEBUG: write(address: %0.2X, value: %0.2X)", address, value);
        switch(address)
        {
            // Channel 1 Sweep register
            case 0xFF10:
                if((soundEnabled & 0b10000000) != 0)
                    channel1_sweep = value | 0b10000000;
                break;

            // Channel 1 Sound length/Wave pattern duty
            case 0xFF11:
                if((soundEnabled & 0b10000000) != 0)
                {
                    channel1_soundLength = value;
                    channel1_internalLengthLock = false;
                }
                break;

            // Channel 1 Volume Envelope
            case 0xFF12:
                if((soundEnabled & 0b10000000) != 0)
                {
                    channel1_volumeEnvelope = value;

                    pragma(msg, "TODO: Check if channel sound should be disabled when the volume is set to 0 and the volume is decreased (cf test 2 passed)");
                    if((channel1_volumeEnvelope & 0b11110000) == 0 && (channel1_volumeEnvelope & 0b00001000) == 0)
                        soundEnabled &= 0b11111110;
                }
                break;

            // Channel 1 Frequency lo
            case 0xFF13:
                if((soundEnabled & 0b10000000) != 0)
                    channel1_frequencyLo = value;
                break;

            // Channel 1 Frequency hi
            case 0xFF14:
                if((soundEnabled & 0b10000000) != 0)
                {
                    const bool enabledBefore = (channel1_frequencyHi & 0b10000000) == 0;
                    const bool loopBefore = (channel1_frequencyHi & 0b01000000) == 0;

                    channel1_frequencyHi = value | 0b00111000;

                    const bool enabled = (channel1_frequencyHi & 0b10000000) != 0;
                    const bool loop = (channel1_frequencyHi & 0b01000000) == 0;

///////////////////
writeln("[1] TRIGGER (len=", channel1_soundLength & 0b00111111, ")");

                    if(internalClock % 16384 <= 8192)
                    {
                        if(loopBefore && !loop && !channel1_internalLengthLock)
                        {
                            if((channel1_soundLength & 0b00111111) == 0b00111111)
                            {
writeln("[1] LEN_LOCKED (TRIGGER NOLOOP)");
                                soundEnabled &= 0b11111110;
                                channel1_frequencyHi &= 0b01111111;
                                channel1_internalLengthLock = true;
                            }

                            channel1_soundLength = (channel1_soundLength & 0b11000000) | ((channel1_soundLength + 1) & 0b00111111);
writeln("[1] LEN_CLOCKED (TRIGGER NOLOOP) to ", channel1_soundLength & 0b00111111);
                        }

                        if(enabled && channel1_internalLengthLock)
                        {
writeln("[1] LEN_UNLOCKED (TRIGGER ENABLE)");
                            channel1_internalLengthLock = false;

                            if(!loop)
                            {
                                if((channel1_soundLength & 0b00111111) == 0b00111111)
                                {
writeln("[1] LEN_LOCKED (TRIGGER ENABLE)");
                                    soundEnabled &= 0b11111110;
                                    channel1_frequencyHi &= 0b01111111;
                                    channel1_internalLengthLock = true;
                                }

                                channel1_soundLength = (channel1_soundLength & 0b11000000) | ((channel1_soundLength + 1) & 0b00111111);
writeln("[1] LEN_CLOCKED (TRIGGER ENABLE) to ", channel1_soundLength & 0b00111111);
                            }
                        }
                    }
                    else if(enabled)
                    {
                        channel1_internalLengthLock = false;
                    }
///////////////////

                    if((channel1_frequencyHi & 0b10000000) != 0)
                    {
                        pragma(msg, "TODO: Check if channel sound should not be enabled when the volume is set to 0 and the volume is decreased (cf test 2 passed)");
                        if((channel1_volumeEnvelope & 0b11110000) != 0 || (channel1_volumeEnvelope & 0b00001000) != 0)
                            soundEnabled |= 0b00000001;

///////////////////////////////////////////////////////////////////////////////
                        const float sweepTime = (channel1_sweep & 0b01110000) >> 4;
                        const bool sweepIncreased = (channel1_sweep & 0b0001000) == 0;
                        const uint sweepShiftCount = channel1_sweep & 0b0000111;

                        pragma(msg, "TODO: To check - Highly experimental !");
                        if(sweepShiftCount > 0)
                        {
                            const uint tmpFrequency = ((channel1_frequencyHi & 0b00000111) << 8) | channel1_frequencyLo;

                            if(sweepIncreased)
                            {
                                const uint newFrequencyRegister = tmpFrequency + (tmpFrequency >> sweepShiftCount);

                                if(newFrequencyRegister <= 2047)
                                {
                                    channel1_frequencyHi = (channel1_frequencyHi & 0b11111000) | ((newFrequencyRegister >> 8) & 0b00000111);
                                    channel1_frequencyLo = newFrequencyRegister & 0b11111111;
writefln("[1] SWEEP_CLOCK (trigger increase to freq=%0.2X|%0.2X)", channel1_frequencyHi, channel1_frequencyLo);
                                }
                                else
                                {
                                    soundEnabled &= 0b11111110;
writefln("[1] SWEEP_SOUND_DISABLE (trigger increase)");
                                }
                            }
                            else
                            {
                                const uint newFrequencyRegister = tmpFrequency - (tmpFrequency >> sweepShiftCount);

                                if(newFrequencyRegister >= 0)
                                {
                                    channel1_frequencyHi = (channel1_frequencyHi & 0b11111000) | ((newFrequencyRegister >> 8) & 0b00000111);
                                    channel1_frequencyLo = newFrequencyRegister & 0b11111111;
writefln("[1] SWEEP_CLOCK (trigger decrease to freq=%0.2X|%0.2X)", channel1_frequencyHi, channel1_frequencyLo);
                                }
                                else
                                {
                                    soundEnabled &= 0b11111110;
writefln("[1] SWEEP_SOUND_DISABLE (trigger decrease)");
                                }
                            }
                        }

                        if(sweepShiftCount > 0 && sweepTime > 0)
                        {
                            channel1_internalSweepState = ClockState.ENABLED;
writefln("[1] SWEEP_STATE=ENABLED (trigger)");
                        }
                        else if(sweepTime > 0 || sweepShiftCount > 0)
                        {
                            channel1_internalSweepState = ClockState.CLOCK_ONCE;
writefln("[1] SWEEP_STATE=CLOCK_ONCE (trigger)");
                        }
                        else
                        {
                            channel1_internalSweepState = ClockState.LOCKED;
writefln("[1] SWEEP_STATE=LOCKED (trigger)");
                        }
///////////////////////////////////////////////////////////////////////////////
                    }
                }
                break;

            // Nothing
            case 0xFF15:
                break;

            // Channel 2 Sound Length/Wave Pattern Duty
            case 0xFF16:
                if((soundEnabled & 0b10000000) != 0)
                    channel2_soundLength = value;
                break;

            // Channel 2 Volume Envelope
            case 0xFF17:
                if((soundEnabled & 0b10000000) != 0)
                {
                    channel2_volumeEnvelope = value;

                    pragma(msg, "TODO: Check if channel sound should be disabled when the volume is set to 0 and the volume is decreased (cf test 2 passed)");
                    if((channel2_volumeEnvelope & 0b11110000) == 0 && (channel2_volumeEnvelope & 0b00001000) == 0)
                        soundEnabled &= 0b11111101;
                }
                break;

            // Channel 2 Frequency lo data
            case 0xFF18:
                if((soundEnabled & 0b10000000) != 0)
                    channel2_frequencyLo = value;
                break;

            // Channel 2 Frequency hi data
            case 0xFF19:
                if((soundEnabled & 0b10000000) != 0)
                {
                    const bool enabledBefore = (channel2_frequencyHi & 0b10000000) == 0;
                    const bool loopBefore = (channel2_frequencyHi & 0b01000000) == 0;

                    channel2_frequencyHi = value | 0b00111000;

                    const bool enabled = (channel2_frequencyHi & 0b10000000) != 0;
                    const bool loop = (channel2_frequencyHi & 0b01000000) == 0;

                    if((channel2_frequencyHi & 0b10000000) != 0)
                    {
                        pragma(msg, "TODO: Check if channel sound should not be enabled when the volume is set to 0 and the volume is decreased (cf test 2 passed)");
                        if((channel2_volumeEnvelope & 0b11110000) != 0 || (channel2_volumeEnvelope & 0b00001000) != 0)
                            soundEnabled |= 0b00000010;
                    }

///////////////////
writeln("[2] TRIGGER (len=", channel2_soundLength & 0b00111111, ")");

                    if(internalClock % 16384 <= 8192)
                    {
                        if(loopBefore && !loop && !channel2_internalLengthLock)
                        {
                            if((channel2_soundLength & 0b00111111) == 0b00111111)
                            {
writeln("[2] LEN_LOCKED (TRIGGER NOLOOP)");
                                soundEnabled &= 0b11111101;
                                channel2_frequencyHi &= 0b01111111;
                                channel2_internalLengthLock = true;
                            }

                            channel2_soundLength = (channel2_soundLength & 0b11000000) | ((channel2_soundLength + 1) & 0b00111111);
writeln("[2] LEN_CLOCKED (TRIGGER NOLOOP) to ", channel2_soundLength & 0b00111111);
                        }

                        if(enabled && channel2_internalLengthLock)
                        {
writeln("[2] LEN_UNLOCKED (TRIGGER ENABLE)");
                            channel2_internalLengthLock = false;

                            if(!loop)
                            {
                                if((channel2_soundLength & 0b00111111) == 0b00111111)
                                {
writeln("[2] LEN_LOCKED (TRIGGER ENABLE)");
                                    soundEnabled &= 0b11111101;
                                    channel2_frequencyHi &= 0b01111111;
                                    channel2_internalLengthLock = true;
                                }

                                channel2_soundLength = (channel2_soundLength & 0b11000000) | ((channel2_soundLength + 1) & 0b00111111);
writeln("[2] LEN_CLOCKED (TRIGGER ENABLE) to ", channel2_soundLength & 0b00111111);
                            }
                        }
                    }
                    else if(enabled)
                    {
                        channel2_internalLengthLock = false;
                    }
///////////////////
                }
                break;

            // Channel 3 Sound on/off
            case 0xFF1A:
                if((soundEnabled & 0b10000000) != 0)
                {
                    channel3_soundOnOff = value | 0b01111111;
                    soundEnabled &= 0b11111011;
                }
                break;

            // Channel 3 Sound Length
            case 0xFF1B:
                pragma(msg, "TODO: port access allowed in read mode ? tests say no !");
                if((soundEnabled & 0b10000000) != 0)
                    channel3_soundLength = value;
                break;

            // Channel 3 Select output level
            case 0xFF1C:
                if((soundEnabled & 0b10000000) != 0)
                {
                    channel3_volume = value | 0b10011111;
                    
                    pragma(msg, "TODO: Check if channel sound should be disabled when the volume is set to 0 and the sound stoped (cf test 2 passed)");
                    if((channel3_volume & 0b01100000) == 0 && (channel3_soundOnOff & 0b10000000) == 0)
                        soundEnabled &= 0b11111011;
                }
                break;

            // Channel 3 Frequency's lower data
            case 0xFF1D:
                if((soundEnabled & 0b10000000) != 0)
                    channel3_frequencyLo = value;
                break;

            // Channel 3 Frequency's higher data
            case 0xFF1E:
                if((soundEnabled & 0b10000000) != 0)
                {
                    const bool enabledBefore = (channel3_frequencyHi & 0b10000000) == 0;
                    const bool loopBefore = (channel3_frequencyHi & 0b01000000) == 0;

                    channel3_frequencyHi = value | 0b00111000;

                    const bool enabled = (channel3_frequencyHi & 0b10000000) != 0;
                    const bool loop = (channel3_frequencyHi & 0b01000000) == 0;

                    if((channel3_frequencyHi & 0b10000000) != 0)
                    {
                        pragma(msg, "TODO: Check if channel sound should not be enabled when the volume is set to 0 and the sound stoped (cf test 2 passed)");
                        if((channel3_volume & 0b01100000) != 0 || (channel3_soundOnOff & 0b10000000) != 0)
                            soundEnabled |= 0b00000100;
                    }

///////////////////
writeln("[3] TRIGGER (len=", channel3_soundLength, ")");

                    if(internalClock % 16384 <= 8192)
                    {
                        if(loopBefore && !loop && !channel3_internalLengthLock)
                        {
                            if(channel3_soundLength == 0b11111111)
                            {
writeln("[3] LEN_LOCKED (TRIGGER NOLOOP)");
                                soundEnabled &= 0b11111011;
                                channel3_frequencyHi &= 0b01111111;
                                channel3_internalLengthLock = true;
                            }

                            channel3_soundLength++;
writeln("[3] LEN_CLOCKED (TRIGGER NOLOOP) to ", channel3_soundLength);
                        }

                        if(enabled && channel3_internalLengthLock)
                        {
writeln("[3] LEN_UNLOCKED (TRIGGER ENABLE)");
                            channel3_internalLengthLock = false;

                            if(!loop)
                            {
                                if(channel3_soundLength == 0b11111111)
                                {
writeln("[3] LEN_LOCKED (TRIGGER ENABLE)");
                                    soundEnabled &= 0b11111011;
                                    channel3_frequencyHi &= 0b01111111;
                                    channel3_internalLengthLock = true;
                                }

                                channel3_soundLength++;
writeln("[3] LEN_CLOCKED (TRIGGER ENABLE) to ", channel3_soundLength);
                            }
                        }
                    }
                    else if(enabled)
                    {
                        channel3_internalLengthLock = false;
                    }
///////////////////
                }
                break;

            // Nothing
            case 0xFF1F:
                break;

            // Channel 4 Sound Length
            case 0xFF20:
                if((soundEnabled & 0b10000000) != 0)
                    channel4_soundLength = value | 0b11000000;
                break;

            // Channel 4 Volume Envelope
            case 0xFF21:
                if((soundEnabled & 0b10000000) != 0)
                {
                    channel4_volumeEnvelope = value;

                    pragma(msg, "TODO: Check if channel sound should be disabled when the volume is set to 0 and the volume is decreased (cf test 2 passed)");
                    if((channel4_volumeEnvelope & 0b11110000) == 0 && (channel4_volumeEnvelope & 0b00001000) == 0)
                        soundEnabled &= 0b11110111;
                }
                break;

            // Channel 4 Polynomial Counter
            case 0xFF22:
                if((soundEnabled & 0b10000000) != 0)
                    channel4_polynomialCounter = value;
                break;

            // Channel 4 Counter/consecutive; Inital
            case 0xFF23:
                if((soundEnabled & 0b10000000) != 0)
                {
                    const bool enabledBefore = (channel4_control & 0b10000000) == 0;
                    const bool loopBefore = (channel4_control & 0b01000000) == 0;

                    channel4_control = value | 0b00111111;

                    const bool enabled = (channel4_control & 0b10000000) != 0;
                    const bool loop = (channel4_control & 0b01000000) == 0;

                    if((channel4_control & 0b10000000) != 0)
                    {
                        pragma(msg, "TODO: Check if channel sound should not be enabled when the volume is set to 0 and the volume is decreased (cf test 2 passed)");
                        if((channel4_volumeEnvelope & 0b11110000) != 0 || (channel4_volumeEnvelope & 0b00001000) != 0)
                            soundEnabled |= 0b00001000;
                    }

///////////////////
writeln("[4] TRIGGER (len=", channel4_soundLength & 0b00111111, ")");

                    if(internalClock % 16384 <= 8192)
                    {
                        if(loopBefore && !loop && !channel4_internalLengthLock)
                        {
                            if((channel4_soundLength & 0b00111111) == 0b00111111)
                            {
writeln("[4] LEN_LOCKED (TRIGGER NOLOOP)");
                                soundEnabled &= 0b11110111;
                                channel4_control &= 0b01111111;
                                channel4_internalLengthLock = true;
                            }

                            channel4_soundLength = (channel4_soundLength & 0b11000000) | ((channel4_soundLength + 1) & 0b00111111);
writeln("[4] LEN_CLOCKED (TRIGGER NOLOOP) to ", channel4_soundLength & 0b00111111);
                        }

                        if(enabled && channel4_internalLengthLock)
                        {
writeln("[4] LEN_UNLOCKED (TRIGGER ENABLE)");
                            channel4_internalLengthLock = false;

                            if(!loop)
                            {
                                if((channel4_soundLength & 0b00111111) == 0b00111111)
                                {
writeln("[4] LEN_LOCKED (TRIGGER ENABLE)");
                                    soundEnabled &= 0b11110111;
                                    channel4_control &= 0b01111111;
                                    channel4_internalLengthLock = true;
                                }

                                channel4_soundLength = (channel4_soundLength & 0b11000000) | ((channel4_soundLength + 1) & 0b00111111);
writeln("[4] LEN_CLOCKED (TRIGGER ENABLE) to ", channel4_soundLength & 0b00111111);
                            }
                        }
                    }
                    else if(enabled)
                    {
                        channel4_internalLengthLock = false;
                    }
///////////////////
                }
                break;

            // Channel control / ON-OFF / Volume
            case 0xFF24:
                if((soundEnabled & 0b10000000) != 0)
                    channelControl = value;
                break;

            // Selection of Sound output terminal
            case 0xFF25:
                if((soundEnabled & 0b10000000) != 0)
                    soundOutput = value;
                break;

            // Sound on/off
            case 0xFF26:
                soundEnabled = (soundEnabled & 0b01111111) | (value & 0b10000000);

                if((soundEnabled & 0b10000000) == 0)
                    resetRegisters();
                break;

            // Nothing
            case 0xFF27: .. case 0xFF2F:
                break;

            // Wave Pattern RAM
            case 0xFF30: .. case 0xFF3F:
                if((soundEnabled & 0b10000000) != 0)
                    channel3_wavePatternRam[address & 0x0F] = value;
                break;

            default:
                throw new Exception(format("Execution failure: Out of memory access (write at %0.4X)", address));
        }
    }

    SoundValue tickChannel1()
    {
        const bool loop = (channel1_frequencyHi & 0b01000000) == 0;
        float soundValue = 0.0f;

        if((soundEnabled & 0b00000001) != 0)
        {
            // Sound length & sound wave pattern
            static float[][] wavePatterns = [
                                                [-1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                [-1.0f, -1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                [-1.0f, -1.0f, -1.0f, -1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                [-1.0f, -1.0f, -1.0f, -1.0f, -1.0f, -1.0f, +1.0f, +1.0f], 
                                            ];
            immutable float[8] wavePattern = wavePatterns[channel1_soundLength >> 6];

            // Sound envelope
            const uint initialVolume = channel1_volumeEnvelope >> 4;
            const bool volumeIncreased = (channel1_volumeEnvelope & 0b00001000) != 0;
            const uint sweepCount = channel1_volumeEnvelope & 0b00000111;

            // Sound frequency
            const uint tmpFrequency = ((channel1_frequencyHi & 0b00000111) << 8) | channel1_frequencyLo;
            const uint frequency = 131072 / (2048 - tmpFrequency);
            const uint realFrequency = frequency * 8; // take into account the wave pattern

            // Stereo loud speakers
            const float so1Volume = (((channelControl & 0b01110000) >> 4) * (soundOutput & 0b00000001)) / 7.0f;
            const float so2Volume = ((channelControl & 0b00000111) * ((soundOutput & 0b00010000) >> 4)) / 7.0f;
            const float globalVolume = (so1Volume + so2Volume) / 2.0f;

            if(frequency*2 <= soundFrequency)
            {
                const float volume = initialVolume / 15.0f;
                const uint cur = cast(uint)channelCur[0];
                soundValue = wavePattern[cur%8] * volume * globalVolume;
                //const float weight = fmod(channelCur[0], 1.0f);
                //soundValue = (wavePattern[cur%8] * (1.0f-weight) + wavePattern[(cur+1)%8] * weight) * volume * globalVolume;
                channelCur[0] += cast(float)realFrequency / soundFrequency;

                if(channelCur[0] >= 256.0f)
                    channelCur[0] = fmod(channelCur[0], 256.0f);
            }
            else
            {
                if(internalClock % 4096 == 0)
                    writeln("WARNING: sound not played on channel 1 (frequency to high)");
            }

            if(sweepCount != 0 && internalClock % (cpuFrequency / 64) == 0)
            {
                pragma(msg, "TODO: To check - Possible bug with the modulo since sweepCount is not a power of two and internalClock is reset every 2**22");
                if((internalClock / (cpuFrequency / 64)) % sweepCount == 0)
                {
                    if(volumeIncreased && initialVolume != 15)
                        channel1_volumeEnvelope += 1 << 4;

                    else if(!volumeIncreased && initialVolume != 0)
                        channel1_volumeEnvelope -= 1 << 4;
                }
            }

            pragma(msg, "TODO: Check if the frequency sweeping work fine");
            if(internalClock % (cpuFrequency / 128) == 0)
            {
                // Sound sweep
                const float sweepTime = (channel1_sweep & 0b01110000) >> 4;
                const bool sweepIncreased = (channel1_sweep & 0b0001000) == 0;
                const uint sweepShiftCount = channel1_sweep & 0b0000111;

                if(channel1_internalSweepState == ClockState.ENABLED && sweepShiftCount > 0 && sweepTime > 0
                        || channel1_internalSweepState == ClockState.CLOCK_ONCE)
                {
                    const float realSweepTime = (sweepTime > 0) ? sweepTime : 8;

                    pragma(msg, "TODO: To check - Possible bug with the modulo since sweepShiftCount is not a power of two and internalClock is reset every 2**22");
                    if(sweepTime > 0 && (internalClock / (cpuFrequency / 128)) % sweepTime == 0)
                    {
                        if(sweepIncreased)
                        {
                            const uint newFrequencyRegister = tmpFrequency + (tmpFrequency >> sweepShiftCount);

                            if(newFrequencyRegister <= 2047)
                            {
                                channel1_frequencyHi = (channel1_frequencyHi & 0b11111000) | ((newFrequencyRegister >> 8) & 0b00000111);
                                channel1_frequencyLo = newFrequencyRegister & 0b11111111;
writefln("[1] SWEEP_CLOCK (tick increase to freq=%0.2X|%0.2X)", channel1_frequencyHi, channel1_frequencyLo);
                            }
                            else
                            {
                                pragma(msg, "TODO: To check - disable other registers ?");
                                soundEnabled &= 0b11111110;
                                channel1_internalSweepState = ClockState.LOCKED;
writefln("[1] SWEEP_SOUND_DISABLE (tick increase)");
                            }
                        }
                        else
                        {
                            const uint newFrequencyRegister = tmpFrequency - (tmpFrequency >> sweepShiftCount);

                            if(newFrequencyRegister >= 0)
                            {
                                channel1_frequencyHi = (channel1_frequencyHi & 0b11111000) | ((newFrequencyRegister >> 8) & 0b00000111);
                                channel1_frequencyLo = newFrequencyRegister & 0b11111111;
writefln("[1] SWEEP_CLOCK (tick decrease to freq=%0.2X|%0.2X)", channel1_frequencyHi, channel1_frequencyLo);
                            }
                            else
                            {
                                pragma(msg, "TODO: To check - disable other registers ?");
                                soundEnabled &= 0b11111110;
                                channel1_internalSweepState = ClockState.LOCKED;
writefln("[1] SWEEP_SOUND_DISABLE (tick decrease)");
                            }
                        }
                    }

                    if(channel1_internalSweepState == ClockState.CLOCK_ONCE)
                    {
                        channel1_internalSweepState = ClockState.ENABLED;
                        writefln("[1] SWEEP_STATE=ENABLED (tick)");
                    }
                }
            }
        }

        if(!loop && !channel1_internalLengthLock && internalClock % 16384 == 0)
        {
            if((channel1_soundLength & 0b00111111) == 0b00111111)
            {
writeln("[1] LEN_LOCKED (TICK)");
                soundEnabled &= 0b11111110;
                channel1_frequencyHi &= 0b01111111;
                channel1_internalLengthLock = true;
            }

            channel1_soundLength = (channel1_soundLength & 0b11000000) | ((channel1_soundLength + 1) & 0b00111111);
writeln("[1] LEN_CLOCKED (TICK) to ", channel1_soundLength & 0b00111111);
        }

        return SoundValue(soundValue, soundValue);
    }

    SoundValue tickChannel2()
    {
        const bool loop = (channel2_frequencyHi & 0b01000000) == 0;
        float soundValue = 0.0f;

        if((soundEnabled & 0b00000010) != 0)
        {
            // Sound length & sound wave pattern
            static float[][] wavePatterns = [
                                                [-1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                [-1.0f, -1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                [-1.0f, -1.0f, -1.0f, -1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                [-1.0f, -1.0f, -1.0f, -1.0f, -1.0f, -1.0f, +1.0f, +1.0f], 
                                            ];
            immutable float[8] wavePattern = wavePatterns[channel2_soundLength >> 6];

            // Sound envelope
            const uint initialVolume = channel2_volumeEnvelope >> 4;
            const bool volumeIncreased = (channel2_volumeEnvelope & 0b00001000) != 0;
            const uint sweepCount = channel2_volumeEnvelope & 0b00000111;

            // Sound frequency
            const uint tmpFrequency = ((channel2_frequencyHi & 0b00000111) << 8) | channel2_frequencyLo;
            const uint frequency = 131072 / (2048 - tmpFrequency);
            const uint realFrequency = frequency * 8; // take into account the wave pattern

            // Stereo loud speakers
            const float so1Volume = (((channelControl & 0b01110000) >> 4) * ((soundOutput & 0b00000010) >> 1)) / 7.0f;
            const float so2Volume = ((channelControl & 0b00000111) * ((soundOutput & 0b00100000) >> 5)) / 7.0f;
            const float globalVolume = (so1Volume + so2Volume) / 2.0f;

            if(frequency*2 <= soundFrequency)
            {
                const float volume = initialVolume / 15.0f;
                const uint cur = cast(uint)channelCur[1];
                soundValue = wavePattern[cur%8] * volume * globalVolume;
                //const float weight = fmod(channelCur[1], 1.0f);
                //soundValue = (wavePattern[cur%8] * (1.0f-weight) + wavePattern[(cur+1)%8] * weight) * volume * globalVolume;
                channelCur[1] += cast(float)realFrequency / soundFrequency;

                if(channelCur[1] >= 256.0f)
                    channelCur[1] = fmod(channelCur[1], 256.0f);
            }
            else
            {
                if(internalClock % 4096 == 0)
                    writeln("WARNING: sound not played on channel 2 (frequency to high)");
            }

            if(sweepCount != 0 && internalClock % (cpuFrequency / 64) == 0)
            {
                pragma(msg, "TODO: To check - Possible bug with the modulo since sweepCount is not a power of two and internalClock is reset every 2**22");
                if((internalClock / (cpuFrequency / 64)) % sweepCount == 0)
                {
                    if(volumeIncreased && initialVolume != 15)
                        channel2_volumeEnvelope += 1 << 4;

                    else if(!volumeIncreased && initialVolume != 0)
                        channel2_volumeEnvelope -= 1 << 4;
                }
            }
        }

        if(!loop && internalClock % 16384 == 0)
        {
            if((channel2_soundLength & 0b00111111) == 0b00111111)
            {
writeln("[2] LEN_LOCKED (TICK)");
                soundEnabled &= 0b11111101;
                channel2_frequencyHi &= 0b01111111;
                channel2_internalLengthLock = false;
            }

            channel2_soundLength = (channel2_soundLength & 0b11000000) | ((channel2_soundLength + 1) & 0b00111111);
writeln("[2] LEN_CLOCKED (TICK) to ", channel2_soundLength & 0b00111111);
        }

        return SoundValue(soundValue, soundValue);
    }

    SoundValue tickChannel3()
    {
        const bool loop = (channel3_frequencyHi & 0b01000000) == 0;
        float soundValue = 0.0f;

        if((soundEnabled & 0b00000100) != 0)
        {
            // Sound frequency
            const uint tmpFrequency = ((channel3_frequencyHi & 0b00000111) << 8) | channel3_frequencyLo;
            const uint frequency = 65536 / (2048 - tmpFrequency);
            const uint realFrequency = frequency * 32; // take into account the wave pattern

            // Volume
            static float[] volumeLevels = [0.0f, 1.0f, 0.5f, 0.25f];
            const float volume = volumeLevels[(channel3_volume & 0b01100000) >> 5];

            // Stereo loud speakers
            const float so1Volume = (((channelControl & 0b01110000) >> 4) * ((soundOutput & 0b00000100) >> 2)) / 7.0f;
            const float so2Volume = ((channelControl & 0b00000111) * ((soundOutput & 0b01000000) >> 6)) / 7.0f;
            const float globalVolume = (so1Volume + so2Volume) / 2.0f;

            if(frequency*16 <= soundFrequency)
            {
                const uint cur = cast(uint)channelCur[2] % 32;
                const ubyte userValue = (channel3_wavePatternRam[(cur/2)%16] >> (4-(cur%2)*4)) & 0b00001111;
                soundValue = (userValue / 7.5f - 1.0f) * volume * globalVolume;
                channelCur[2] += cast(float)realFrequency / soundFrequency;
            }
            else
            {
                if(internalClock % 4096 == 0)
                    writeln("WARNING: sound not played on channel 3 (frequency to high)");
            }

            if(channelCur[2] >= 256.0f)
                channelCur[2] = fmod(channelCur[2], 256.0f);
        }

        if(!loop && internalClock % 16384 == 0)
        {
            if(channel3_soundLength == 0b11111111)
            {
writeln("[3] LEN_LOCKED (TICK)");
                soundEnabled &= 0b11111011;
                channel3_frequencyHi &= 0b01111111;
                channel3_internalLengthLock = false;
            }

            channel3_soundLength++;
writeln("[3] LEN_CLOCKED (TICK) to ", channel3_soundLength);
        }

        return SoundValue(soundValue, soundValue);
    }

    SoundValue tickChannel4()
    {
        const bool loop = (channel4_control & 0b01000000) == 0;
        float soundValue = 0.0f;

        if((soundEnabled & 0b00001000) != 0)
        {
            // Sound envelope
            const float initialVolume = channel4_volumeEnvelope >> 4;
            const bool volumeIncreased = (channel4_volumeEnvelope & 0b00001000) != 0;
            const uint sweepCount = channel4_volumeEnvelope & 0b00000111;

            // Sound frequency
            const uint freqShift = min((channel4_polynomialCounter >> 4) + 1, 14);
            const uint counterBits = (channel4_polynomialCounter & 0b00001000) == 0 ? 15 : 7;
            const uint counterMask = (1 << counterBits) - 1;
            const float freqDivider = max(cast(float)(channel4_polynomialCounter & 0b00000111), 0.5f);
            const uint frequency = cast(uint)(524288.0f / freqDivider) >> freqShift;

            // Stereo loud speakers
            const float so1Volume = (((channelControl & 0b01110000) >> 4) * ((soundOutput & 0b00001000) >> 3)) / 7.0f;
            const float so2Volume = ((channelControl & 0b00000111) * ((soundOutput & 0b10000000) >> 7)) / 7.0f;
            const float globalVolume = (so1Volume + so2Volume) / 2.0f;

            if(frequency > soundFrequency)
                if(internalClock % 4096 == 0)
                    writeln("WARNING: sound with to high frequency (channel 4)");

            const float volume = initialVolume / 15.0f;
            const uint cur = cast(uint)channelCur[3] & counterMask;
            soundValue = randomValues[cur] * volume * globalVolume;
            channelCur[3] += cast(float)min(frequency, soundFrequency) / soundFrequency;

            pragma(msg, "TODO: To check - enable even with disabled sound ?");
            if(channelCur[3] >= counterMask)
                channelCur[3] = fmod(channelCur[3], counterMask);

            if(sweepCount != 0 && internalClock % (cpuFrequency / 64) == 0)
            {
                pragma(msg, "TODO: To check - Possible bug with the modulo since sweepCount is not a power of two and internalClock is reset every 2**22");
                if((internalClock / (cpuFrequency / 64)) % sweepCount == 0)
                {
                    if(volumeIncreased && initialVolume != 15)
                        channel4_volumeEnvelope += 1 << 4;

                    else if(!volumeIncreased && initialVolume != 0)
                        channel4_volumeEnvelope -= 1 << 4;
                }
            }
        }

        if(!loop && internalClock % 16384 == 0)
        {
            if((channel4_soundLength & 0b00111111) == 0b00111111)
            {
writeln("[4] LEN_LOCKED (TICK)");
                soundEnabled &= 0b11110111;
                channel4_control &= 0b01111111;
                channel4_internalLengthLock = false;
            }

            channel4_soundLength = (channel4_soundLength & 0b11000000) | ((channel4_soundLength + 1) & 0b00111111);
writeln("[4] LEN_CLOCKED (TICK) to ", channel4_soundLength & 0b00111111);
        }

        return SoundValue(soundValue, soundValue);
    }

    SoundValue mixSound(int n)(in SoundValue[n] values)
    {
        float left = 0.0f;
        float right = 0.0f;

        foreach(const SoundValue v ; values)
        {
            left += v.left;
            right += v.right;
        }

        return SoundValue(left / n, right / n);
    }

    SoundValue normalize(in SoundValue value)
    {
        return SoundValue(min(max(value.left, -1.0f), 1.0f), min(max(value.right, -1.0f), 1.0f));
    }

    void tick()
    {
        pragma(msg, "TODO: Do not forget to decrease/increase the sound volume over time (because it can be read)");

        if(useCgb || (soundEnabled & 0b10000000) != 0)
            internalClock++;

        if(internalClock % clockStep == 0)
        {
            short bufferLeftSoundValue = 0;
            short bufferRightSoundValue = 0;

            if((soundEnabled & 0b10000000) != 0)
            {
                const SoundValue soundValueChan1 = tickChannel1();
                const SoundValue soundValueChan2 = tickChannel2();
                const SoundValue soundValueChan3 = tickChannel3();
                const SoundValue soundValueChan4 = tickChannel4();

                const float soundAmplitude = cast(float)(max(-short.min/2, short.max/2) - 1);
                const SoundValue soundValue = normalize(mixSound([soundValueChan1, soundValueChan2, soundValueChan3, soundValueChan4]));
                bufferLeftSoundValue = cast(short)(soundValue.left * soundAmplitude);
                bufferRightSoundValue = cast(short)(soundValue.right * soundAmplitude);
            }

            const uint buffId = (bufferCur / soundBufferSize) % bufferCount;
            const uint localBufferCur = bufferCur % soundBufferSize;
            soundBuffers[buffId][localBufferCur + 0] = bufferLeftSoundValue;
            soundBuffers[buffId][localBufferCur + 1] = bufferRightSoundValue;
            bufferCur += 2;

            if(bufferCur % soundBufferSize == 0)
            {
                int processedBufferCount;
                alGetSourceiv(alSource, AL_BUFFERS_PROCESSED, &processedBufferCount);

                int queuedBufferCount;
                alGetSourceiv(alSource, AL_BUFFERS_QUEUED, &queuedBufferCount);

                if(processedBufferCount > 0)
                {
                    while(processedBufferCount > 0)
                    {
                        alSourceUnqueueBuffers(alSource, 1, &alBuffers[(buffId+bufferCount-queuedBufferCount)%bufferCount]);
                        checkErrors("Unable to unqueue a sound buffer to an OpenAL source");
                        processedBufferCount--;
                        queuedBufferCount--;
                    }
                }
                else if(queuedBufferCount == bufferCount)
                {
                    writeln("Warning: sound buffer queuing too fast for the played source, buffers are replaced in the sound buffer queue");
                    alSourceStop(alSource);
                    checkErrors("Unable to stop an OpenAL source");
                    alSourceUnqueueBuffers(alSource, 1, &alBuffers[buffId]);
                    checkErrors("Unable to unqueue a sound buffer to an OpenAL source");
                    alSourcePlay(alSource);
                    checkErrors("Unable to play an OpenAL source");
                }

                alBufferData(alBuffers[buffId], AL_FORMAT_STEREO16, soundBuffers[buffId].ptr, soundBuffers[buffId].length*short.sizeof, soundFrequency);
                checkErrors(format("Unable to bind the data of an OpenAL sound buffer (buffer %d)", buffId+1));
                alSourceQueueBuffers(alSource, 1, &alBuffers[buffId]);
                checkErrors("Unable to queue a sound buffer to an OpenAL source");

                int state = 0;
                alGetSourcei(alSource, AL_SOURCE_STATE, &state);
                if(state != AL_PLAYING)
                    alSourcePlay(alSource);
            }

            //if(bufferCur == soundBufferSize * bufferCount)
            //    bufferCur = 0;

            if(internalClock == maxInternalClock)
                internalClock = 0;
        }
    }


    private:

    void checkErrors(string msg = "OpenAL critical error")
    {
        enum AlError
        {
            NoError = AL_NO_ERROR,
            InvalidName = AL_INVALID_NAME,
            InvalidEnum = AL_INVALID_ENUM,
            InvalidValue = AL_INVALID_VALUE,
            InvalidOperation = AL_INVALID_OPERATION,
            OutOfMemory = AL_OUT_OF_MEMORY
        }

        AlError val = cast(AlError)alGetError();
        if(val != AlError.NoError)
            throw new Exception(msg ~ " (OpenAL error " ~ to!string(val) ~ ")");
    }
};



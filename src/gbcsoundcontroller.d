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


pragma(msg, "TODO: support stereo sound and SO1/SO2 (sound output terminal)");
pragma(msg, "TODO: fix issue with real time sound (OpenAL latency problems) => mix sound mannually ?");
pragma(msg, "TODO: real time adaptation of played sounds using sound I/O ports => mix sound mannually ?");
pragma(msg, "TODO: support additionnal Vin (NR50)");
pragma(msg, "TODO: cf. issue with loop & sweep enabled together");
final class GbcSoundController : Mmu8bItf
{
    private:

    immutable uint cpuFrequency = 4_194_304;
    ubyte channel1_sweep = 0x80;
    ubyte channel1_soundLength = 0xBF;
    ubyte channel1_volumeEnvelope = 0xF3;
    ubyte channel1_frequencyLo = 0x00; // Init value undefined
    ubyte channel1_frequencyHi = 0xBF;
    ubyte channel2_soundLength = 0x3F;
    ubyte channel2_volumeEnvelope = 0x00;
    ubyte channel2_frequencyLo = 0x00; // Init value undefined
    ubyte channel2_frequencyHi = 0xBF;
    ubyte channel3_soundOnOff = 0x7F;
    ubyte channel3_soundLength = 0xFF;
    ubyte channel3_volume = 0x9F;
    ubyte channel3_frequencyLo = 0x00; // Init value undefined
    ubyte channel3_frequencyHi = 0xBF;
    ubyte[16] channel3_wavePatternRam = 0xFF; // Init value undefined
    ubyte channel4_soundLength = 0xFF;
    ubyte channel4_volumeEnvelope = 0x00;
    ubyte channel4_polynomialCounter = 0x00;
    ubyte channel4_control = 0xBF;
    ubyte channelControl = 0x77;
    ubyte soundOutput = 0xF3;
    ubyte soundEnabled = 0xF0; // 0xF1 for GB, 0xF0 for SGB
    float[32768] randomValues;
    uint[4] channelCountdown = 0;
    uint internalClock = 0;
    ALCdevice* device;
    ALCcontext* context;
    uint[4] channels;
    uint[4] buffers;


    public:

    this()
    {
        // DerelictAL initialization

        DerelictAL.load();

        if(!DerelictAL.isLoaded)
            throw new Exception("Unable to load OpenAL");


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

        alGenSources(channels.length, channels.ptr);
        checkErrors("Unable to create OpenAL sound sources");

        foreach(ref uint channel ; channels)
        {
            alSourcef(channel, AL_PITCH, 1.0f);
            checkErrors("Unable to configure an OpenAL sound source");

            alSourcef(channel, AL_GAIN, 1.0f);
            checkErrors("Unable to configure an OpenAL sound source");

            alSource3f(channel, AL_POSITION, 0.0, 1.0, 1.0);
            checkErrors("Unable to configure an OpenAL sound source");

            alSource3f(channel, AL_VELOCITY, 0.0, 0.0, 0.0);
            checkErrors("Unable to configure an OpenAL sound source");
        }


        // Buffers initialization

        alGenBuffers(buffers.length, buffers.ptr);
        checkErrors("Unable to create OpenAL sound buffers");


        // Data and registers initialization

        foreach(int i ; 0..randomValues.length)
            randomValues[i] = uniform(0.5f, 255.5f);
    }

    ~this()
    {
        foreach(uint channelId ; 0..channels.length)
            alSourceStop(channels[channelId]);

        alDeleteSources(channels.length, channels.ptr);
        alDeleteBuffers(buffers.length, buffers.ptr);
        alcDestroyContext(context);
        alcCloseDevice(device);
    }

    void resetRegisters()
    {
        channel1_sweep = 0x80;
        channel1_soundLength = 0x3F;
        channel1_volumeEnvelope = 0x00;
        channel1_frequencyLo = 0xFF;
        channel1_frequencyHi = 0xBF;
        channel2_soundLength = 0x3F;
        channel2_volumeEnvelope = 0x00;
        channel2_frequencyLo = 0xFF;
        channel2_frequencyHi = 0xBF;
        channel3_soundOnOff = 0x7F;
        channel3_soundLength = 0xFF;
        channel3_volume = 0x9F;
        channel3_frequencyLo = 0xFF;
        channel3_frequencyHi = 0xBF;
        channel4_soundLength = 0xFF;
        channel4_volumeEnvelope = 0x00;
        channel4_polynomialCounter = 0x00;
        channel4_control = 0xBF;
        channelControl = 0x00;
        soundOutput = 0x00;
        soundEnabled = 0x70;

        foreach(uint channelId ; 0..channels.length)
        {
            alSourcei(channels[channelId], AL_BUFFER, 0);
            checkErrors(format("Unable to unbind the sound buffer of an OpenAL sound (channel %d)", channelId+1));
        }
    }

    void playOnChannel(uint channelId)
    {
        alSourceStop(channels[channelId]);
        checkErrors(format("Unable to stop an OpenAL sound (channel %d)", channelId+1));

        alSourcePlay(channels[channelId]);
        checkErrors(format("Unable to play an OpenAL sound (channel %d)", channelId+1));
    }

    void playNewOnChannel(uint channelId, ubyte[] soundBuffer, uint frequency, bool loop)
    {
        alSourceStop(channels[channelId]);
        checkErrors(format("Unable to stop an OpenAL sound (channel %d)", channelId+1));

        alSourcei(channels[channelId], AL_BUFFER, 0);
        checkErrors(format("Unable to unbind the sound buffer of an OpenAL sound (channel %d)", channelId+1));

        alBufferData(buffers[channelId], AL_FORMAT_MONO8, soundBuffer.ptr, cast(int)soundBuffer.length, frequency);
        checkErrors(format("Unable to bind the data of an OpenAL sound buffer (channel %d)", channelId+1));

        alSourcei(channels[channelId], AL_BUFFER, buffers[channelId]);
        checkErrors(format("Unable to bind the sound buffer to an OpenAL sound (channel %d)", channelId+1));

        alSourcei(channels[channelId], AL_LOOPING, loop);
        checkErrors(format("Unable to set the loop mode of an OpenAL sound (channel %d)", channelId+1));

        alSourcePlay(channels[channelId]);
        checkErrors(format("Unable to play an OpenAL sound (channel %d)", channelId+1));

        channelCountdown[channelId] = cast(uint)(soundBuffer.length * cast(ulong)cpuFrequency / frequency);
    }

    void stopChannel(uint channelId)
    {
        alSourceStop(channels[channelId]);
        checkErrors(format("Unable to stop an OpenAL sound (channel %d)", channelId+1));

        channelCountdown[channelId] = 0;
    }

    ubyte loadByte(ushort address)
    {
        switch(address)
        {
            // Channel 1 Sweep register
            case 0xFF10:
                return channel1_sweep;

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
                pragma(msg, "TODO: port access allowed in read mode ? tests say no !");
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
                int isPlaying;
                ubyte result = soundEnabled;

                foreach(uint channelId ; 0..4)
                {
                    //alGetSourcei(channels[channelId], AL_SOURCE_STATE, &isPlaying);
                    //if(isPlaying == AL_PLAYING)
                    //    result |= 1 << channelId;

                    if(channelCountdown[channelId] > 0)
                        result |= 1 << channelId;
                }

                return result;

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
        pragma(msg, "DEBUG");
        //writefln("GbcSoundController::saveByte(0x%0.4X, 0x%0.2X/0b%0.8b)", address, value, value);

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
                    channel1_soundLength = value;
                break;

            // Channel 1 Volume Envelope
            case 0xFF12:
                if((soundEnabled & 0b10000000) != 0)
                    channel1_volumeEnvelope = value;
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
                    channel1_frequencyHi = value | 0b00111000;

                    if((channel1_frequencyHi & 0b10000000) != 0)
                    {
                        // Sound sweep
                        const bool sweepEnabled = (channel1_sweep & 0b01110000) != 0;
                        const float sweepTime = ((channel1_sweep & 0b01110000) >> 4) / 128.0f;
                        const bool sweepIncreased = (channel1_sweep & 0b0001000) == 0;
                        const uint sweepShiftCount = channel1_sweep & 0b0000111;
                        pragma(msg, "TODO: sound frequency variation not yet supported (channel 1)");

                        if(sweepEnabled)
                            writeln("WARNING: sweep on channel 1 is not yet supported");

                        // Sound length & sound wave pattern
                        const float length = (64 - (channel1_soundLength & 0b00111111)) / 256.0f;
                        immutable float[8] wavePattern =    [
                                                                [-1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                                [-1.0f, -1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                                [-1.0f, -1.0f, -1.0f, -1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                                [-1.0f, -1.0f, -1.0f, -1.0f, -1.0f, -1.0f, +1.0f, +1.0f], 
                                                            ][channel1_soundLength >> 6];

                        // Sound envelope
                        const float initialVolume = (channel1_volumeEnvelope >> 4) / 15.0f;
                        const bool increaseVolume = (channel1_volumeEnvelope & 0b00001000) != 0;
                        const float sign = (increaseVolume) ? 1.0f : -1.0f;
                        const uint sweepCount = channel1_volumeEnvelope & 0b00000111;
                        const float stepLength = sweepCount / 64.0f;

                        // Sound frequency
                        const uint tmpFrequency = ((channel1_frequencyHi & 0b00000111) << 8) | channel1_frequencyLo;
                        const uint frequency = 131072 / (2048 - tmpFrequency);
                        const uint realFrequency = frequency * 8; // take into account the wave pattern

                        const bool loop = (channel1_frequencyHi & 0b01000000) == 0;

                        const uint bufferSize = cast(uint)(length * realFrequency);
                        ubyte[] soundBuff = new ubyte[bufferSize];

                        float volume = initialVolume;

                        pragma(msg, "SO1/SO2 not fully supported");
                        const float so1Volume = (((channelControl & 0b01110000) >> 4) * (soundOutput & 0b00000001)) / 7.0f;
                        const float so2Volume = ((channelControl & 0b00000111) * ((soundOutput & 0b00010000) >> 4)) / 7.0f;
                        const float globalVolume = (so1Volume + so2Volume) / 2.0f;

                        if(sweepCount > 0)
                        {
                            const uint stepSize = cast(uint)(stepLength * realFrequency);

                            foreach(int i ; 0..bufferSize)
                            {
                                if(i % stepSize == stepSize-1)
                                    volume = fmin(fmax(volume + sign / 15.0f, 0.0f), 1.0f); // valid step ?

                                const float soundValue = wavePattern[i%8] * 127.0f * volume * globalVolume + 127.0f;
                                soundBuff[i] = cast(ubyte)fmin(fmax(soundValue, 0.5f), 255.5f);
                            }
                        }
                        else
                        {
                            foreach(int i ; 0..bufferSize)
                            {
                                const float soundValue = wavePattern[i%8] * 127.0f * globalVolume + 127.0f;
                                soundBuff[i] = cast(ubyte)fmin(fmax(soundValue, 0.5f), 255.5f);
                            }
                        }

                        playNewOnChannel(0, soundBuff, realFrequency, loop);
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
                    channel2_volumeEnvelope = value;
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
                    channel2_frequencyHi = value | 0b00111000;

                    if((channel2_frequencyHi & 0b10000000) != 0)
                    {
                        // Sound length & sound wave pattern
                        const float length = (64 - (channel2_soundLength & 0b00111111)) / 256.0f;
                        immutable float[8] wavePattern =    [
                                                                [-1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                                [-1.0f, -1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                                [-1.0f, -1.0f, -1.0f, -1.0f, +1.0f, +1.0f, +1.0f, +1.0f], 
                                                                [-1.0f, -1.0f, -1.0f, -1.0f, -1.0f, -1.0f, +1.0f, +1.0f], 
                                                            ][channel2_soundLength >> 6];

                        // Sound envelope
                        const float initialVolume = (channel2_volumeEnvelope >> 4) / 15.0f;
                        const bool increaseVolume = (channel2_volumeEnvelope & 0b00001000) != 0;
                        const float sign = (increaseVolume) ? 1.0f : -1.0f;
                        const uint sweepCount = channel2_volumeEnvelope & 0b00000111;
                        const float stepLength = sweepCount / 64.0f;

                        // Sound frequency
                        const uint tmpFrequency = ((channel2_frequencyHi & 0b00000111) << 8) | channel2_frequencyLo;
                        const uint frequency = 131072 / (2048 - tmpFrequency);
                        const uint realFrequency = frequency * 8; // take into account the wave pattern

                        const bool loop = (channel2_frequencyHi & 0b01000000) == 0;

                        const uint bufferSize = cast(uint)(length * realFrequency);
                        ubyte[] soundBuff = new ubyte[bufferSize];

                        float volume = initialVolume;

                        pragma(msg, "SO1/SO2 not fully supported");
                        const float so1Volume = (((channelControl & 0b01110000) >> 4) * ((soundOutput & 0b00000010) >> 1)) / 7.0f;
                        const float so2Volume = ((channelControl & 0b00000111) * ((soundOutput & 0b00100000) >> 5)) / 7.0f;
                        const float globalVolume = (so1Volume + so2Volume) / 2.0f;

                        if(sweepCount > 0)
                        {
                            const uint stepSize = cast(uint)(stepLength * realFrequency);

                            foreach(int i ; 0..bufferSize)
                            {
                                if(i % stepSize == 0)
                                    volume = fmin(fmax(volume + sign / 15.0f, 0.0f), 1.0f); // valid step ?

                                const float soundValue = wavePattern[i%8] * 127.0f * volume * globalVolume + 127.0f;
                                soundBuff[i] = cast(ubyte)fmin(fmax(soundValue, 0.5f), 255.5f);
                            }
                        }
                        else
                        {
                            foreach(int i ; 0..bufferSize)
                            {
                                const float soundValue = wavePattern[i%8] * 127.0f * globalVolume + 127.0f;
                                soundBuff[i] = cast(ubyte)fmin(fmax(soundValue, 0.5f), 255.5f);
                            }
                        }

                        playNewOnChannel(1, soundBuff, realFrequency, loop);
                    }
                }
                break;

            // Channel 3 Sound on/off
            case 0xFF1A:
                if((soundEnabled & 0b10000000) != 0)
                {
                    channel3_soundOnOff = value | 0b01111111;

                    if((channel3_soundOnOff & 0b10000000) == 0)
                        stopChannel(2);
                    else
                        playOnChannel(2);
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
                    channel3_volume = value | 0b10011111;
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
                    channel3_frequencyHi = value | 0b00111000;

                    if((channel3_frequencyHi & 0b10000000) != 0)
                    {
                        // Sound length & sound wave pattern
                        const float length = (256 - channel3_soundLength) / 256.0f;

                        // Sound frequency
                        const uint tmpFrequency = ((channel3_frequencyHi & 0b00000111) << 8) | channel3_frequencyLo;
                        const uint frequency = 65536 / (2048 - tmpFrequency);
                        const uint realFrequency = frequency * 32; // take into account the wave pattern

                        const bool loop = (channel3_frequencyHi & 0b01000000) == 0;

                        const uint bufferSize = cast(uint)(length * realFrequency);
                        ubyte[] soundBuff = new ubyte[bufferSize];

                        const float volume = [0.0f, 1.0f, 0.5f, 0.25f][(channel3_volume & 0b01100000) >> 5];

                        pragma(msg, "SO1/SO2 not fully supported");
                        const float so1Volume = (((channelControl & 0b01110000) >> 4) * ((soundOutput & 0b00000100) >> 2)) / 7.0f;
                        const float so2Volume = ((channelControl & 0b00000111) * ((soundOutput & 0b01000000) >> 6)) / 7.0f;
                        const float globalVolume = (so1Volume + so2Volume) / 2.0f;

                        foreach(int i ; 0..bufferSize)
                        {
                            const ubyte userValue = ((channel3_wavePatternRam[(i/2)%16]>>(4-(i%2)*4)) & 0b00001111) * 16;
                            const float soundValue = (userValue - 127.0f) * volume * globalVolume + 127.0f;
                            soundBuff[i] = cast(ubyte)fmin(fmax(soundValue, 0.5f), 255.5f);
                        }

                        playNewOnChannel(2, soundBuff, realFrequency, loop);
                    }
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
                    channel4_volumeEnvelope = value;
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
                    channel4_control = value | 0b00111111;

                    if((channel4_control & 0b10000000) != 0)
                    {
                        // Sound length
                        const float length = (64 - (channel4_soundLength & 0b00111111)) / 256.0f;

                        // Sound envelope
                        const float initialVolume = (channel4_volumeEnvelope >> 4) / 15.0f;
                        const bool volumeIncreased = (channel4_volumeEnvelope & 0b00001000) != 0;
                        const float sign = (volumeIncreased) ? 1.0f : -1.0f;
                        const uint sweepCount = channel4_volumeEnvelope & 0b00000111;
                        const float stepLength = sweepCount / 64.0f;

                        // Sound frequency
                        const uint freqShift = min((channel4_polynomialCounter >> 4) + 1, 14);
                        const uint counterBits = (channel4_polynomialCounter & 0b00001000) == 0 ? 15 : 7;
                        const uint counterMask = (1 << counterBits) - 1;
                        const float freqDivider = fmax(channel4_polynomialCounter & 0b00000111, 0.5f);
                        const uint frequency = cast(uint)(524288.0f / freqDivider) >> freqShift;
                        const uint realFrequency = frequency;

                        const bool loop = (channel4_control & 0b01000000) == 0;

                        const uint bufferSize = cast(uint)(length * realFrequency);
                        ubyte[] soundBuff = new ubyte[bufferSize];

                        float volume = initialVolume;

                        // Stereo loud speakers
                        pragma(msg, "SO1/SO2 not fully supported");
                        const float so1Volume = (((channelControl & 0b01110000) >> 4) * ((soundOutput & 0b00001000) >> 3)) / 7.0f;
                        const float so2Volume = ((channelControl & 0b00000111) * ((soundOutput & 0b10000000) >> 7)) / 7.0f;
                        const float globalVolume = (so1Volume + so2Volume) / 2.0f;

                        if(sweepCount > 0)
                        {
                            const uint stepSize = cast(uint)(stepLength * realFrequency);
                            int k = 0;

                            foreach(int i ; 0..bufferSize)
                            {
                                if(++k == stepSize)
                                {
                                    volume = fmin(fmax(volume + sign / 15.0f, 0.0f), 1.0f); // valid step ?
                                    k = 0;
                                }

                                const float soundValue = (randomValues[i & counterMask] - 127.0f) * volume * globalVolume + 127.0f;
                                soundBuff[i] = cast(ubyte)fmin(fmax(soundValue, 0.5f), 255.5f);
                            }
                        }
                        else
                        {
                            foreach(int i ; 0..bufferSize)
                            {
                                const float soundValue = (randomValues[i & counterMask] - 127.0f) * globalVolume + 127.0f;
                                soundBuff[i] = cast(ubyte)fmin(fmax(soundValue, 0.5f), 255.5f);
                            }
                        }

                        playNewOnChannel(3, soundBuff, realFrequency, loop);
                    }
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
                soundEnabled = (soundEnabled | 0b10000000) & (value | 0b01111111);

                if((soundEnabled & 0b10000000) == 0)
                {
                    foreach(uint channelId ; 0..channels.length)
                        if((soundEnabled << channelId) & 0b00000001)
                            stopChannel(channelId);

                    foreach(uint channelId ; 0..channels.length)
                        stopChannel(channelId);

                    resetRegisters();
                }
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

    void tick()
    {
        internalClock++;

        if(internalClock % 8 == 0)
        {
            if((soundEnabled & 0b10000000) != 0)
            {
                foreach(uint channelId ; 0..channelCountdown.length)
                {
                    if(channelCountdown[channelId] >= 8)
                    {
                        channelCountdown[channelId] -= 8;
                    }
                    else
                    {
                        channelCountdown[channelId] = 0;
                        //stopChannel(channelId);
                    }
                }
            }
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



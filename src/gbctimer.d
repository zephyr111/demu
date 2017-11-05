module gbctimer;

import interfaces.timer;
import interfaces.cpu;
import genericgbctimer;


final class GbcTimer : TimerItf
{
    // Divider frequency: 8192 Hz
    // Tima frequencies: 4096 Hz, 262144 Hz, 65536 Hz, 16384 Hz
    static immutable uint cpuFreqShift = 22;
    static immutable uint[] timaBitShifts = [9, 3, 5, 7];
    static immutable uint dividerBitShift = 9;

    ubyte timaMode = 0b11111000;
    ubyte timaValue = 0;
    ubyte timaResetVal = 0;
    ushort internalClock = 0;
    int timaOverflowDelay = -1;
    uint timaShift;
    uint timaMask;
    CpuItf cpu;


    public:

    this()
    {
        timaShift = timaBitShifts[timaMode & 0b00000011];
        timaMask = (timaMode & 0b00000100) >> 2;
    }

    ubyte readDividerCounter()
    {
        return internalClock >> dividerBitShift;
    }

    void writeDividerCounter(ubyte)
    {
        // GB/GBC glitch (cf. notes below)
        if(checkTimaIncrement(internalClock, 0, timaMode, timaMode))
            incrementTima();

        internalClock = 0;
    }

    ubyte readTimaCounter()
    {
        return timaValue;
    }

    void writeTimaCounter(ubyte value)
    {
        // GB/GBC glitch (cf. notes below)
        if(timaOverflowDelay >= 4)
            timaValue = value, timaOverflowDelay = -1;
        else if(timaOverflowDelay >= 0)
            timaValue = timaResetVal;
        else
            timaValue = value;
    }

    ubyte readTimaModulo()
    {
        return timaResetVal;
    }

    void writeTimaModulo(ubyte value)
    {
        // GB/GBC glitch (cf. notes below)
        if(timaOverflowDelay >= 0 && timaOverflowDelay < 4)
            timaValue = value;

        timaResetVal = value;
    }

    ubyte readTimaControl()
    {
        return timaMode;
    }

    void writeTimaControl(ubyte value)
    {
        const uint oldTimaMode = timaMode;
        timaMode = value | 0b11111000;

        // GB/GBC glitch (cf. notes below)
        if(checkTimaIncrement(internalClock, internalClock, oldTimaMode, timaMode))
            incrementTima();

        timaShift = timaBitShifts[timaMode & 0b00000011];
        timaMask = (timaMode & 0b00000100) >> 2;
    }

    void tick()
    {
        const uint oldInternalClock = internalClock;

        if((cpu.doubleSpeedState() & 0b10000000) != 0)
            internalClock = (internalClock+2) & 0xFFFF;
        else
            internalClock = (internalClock+1) & 0xFFFF;

        // Increment TIMA if necessary
        if(checkTimaIncrement(oldInternalClock, internalClock))
            incrementTima();

        // Delay from the previous reset need to implement a GB/GBC glitch (cf. notes below)
        if(timaOverflowDelay >= 0)
        {
            const uint oldTimaOverflowDelay = timaOverflowDelay;

            timaOverflowDelay -= internalClock - oldInternalClock;

            if(oldTimaOverflowDelay >= 4 && timaOverflowDelay < 4)
            {
                timaValue = timaResetVal;
                cpu.addInterruptRequests(0b00000100);
            }
        }
    }

    void connectCpu(CpuItf cpu)
    {
        this.cpu = cpu;
    }


    private:

    // Rules to increment TIMA (include GB/GBC glitches) specified at:
    // http://gbdev.gg8.se/wiki/articles/Timer_Obscure_Behaviour
    bool checkTimaIncrement(uint oldClock, uint newClock, uint oldTimaMode, uint newTimaMode)
    {
        const uint oldBitShift = timaBitShifts[oldTimaMode & 0b00000011];
        const uint newBitShift = timaBitShifts[newTimaMode & 0b00000011];
        const bool oldValue = (oldClock >> oldBitShift) & (oldTimaMode>>2) & 0b00000001;
        const bool newValue = (newClock >> newBitShift) & (newTimaMode>>2) & 0b00000001;
        return oldValue && !newValue;
    }

    // Alternative faster implementation (used when the mode does not change)
    bool checkTimaIncrement(uint oldClock, uint newClock)
    {
        const bool oldValue = cast(bool)((oldClock >> timaShift) & timaMask);
        const bool newValue = cast(bool)((newClock >> timaShift) & timaMask);
        return oldValue && !newValue;
    }

    // Incrementing TIMA introduce a delay due to a GB/GBC glitch as specified at:
    // http://gbdev.gg8.se/wiki/articles/Timer_Obscure_Behaviour
    void incrementTima()
    {
        if(timaValue == 0xFF)
        {
            timaValue = 0x00;
            timaOverflowDelay = 7;
        }
        else
        {
            timaValue++;
        }
    }
};



module gbctimatimer;

import std.stdio;
import interfaces.timatimer;
import interfaces.cpu;
import genericgbctimer;


final class GbcTimaTimer : TimaTimerItf
{
    static immutable frequencies = [4096, 262144, 65536, 16384];
    ubyte mode = 0b11111000;
    ubyte internalValue = 0;
    ubyte resetVal = 0;
    uint freq = 0;
    ulong internalClock = 0;
    bool started;
    CpuItf cpu;


    public:

    this()
    {
        freq = frequencies[mode & 0b00000011];
        started = (mode & 0b00000100) != 0;
    }

    ubyte readCounter()
    {
        return internalValue;
    }

    void writeCounter(ubyte value)
    {
        internalValue = value;
    }

    ubyte readModulo()
    {
        return resetVal;
    }

    void writeModulo(ubyte value)
    {
        resetVal = value;
    }

    ubyte readControl()
    {
        return mode;
    }

    void writeControl(ubyte value)
    {
        pragma(msg, "TODO: Should internalClock be reset ?");
        mode = value | 0b11111000;
        internalClock = 0;
        freq = frequencies[value & 0b00000011];
        started = (value & 0b00000100) != 0;
    }

    void tick()
    {
        static immutable uint cpuFrequency = 4_194_304;

        if(started)
        {
            if((cpu.doubleSpeedState() & 0b10000000) != 0)
                internalClock += 2;
            else
                internalClock++;

            if(internalClock*freq >= cpuFrequency)
            {
                internalClock = 0;

                if(internalValue == 0xFF)
                {
                    internalValue = resetVal;
                    cpu.addInterruptRequests(0b00000100);
                }
                else
                {
                    internalValue++;
                }
            }
        }
    }

    void connectCpu(CpuItf cpu)
    {
        this.cpu = cpu;
    }
};



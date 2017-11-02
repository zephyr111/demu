module gbcdividertimer;

import interfaces.dividertimer;
import interfaces.cpu;
import genericgbctimer;


final class GbcDividerTimer : DividerTimerItf
{
    ubyte value = 0;
    ubyte resetVal = 0;
    uint internalClock = 0;
    CpuItf cpu;


    public:

    this()
    {

    }

    void writeCounter(ubyte)
    {
        value = resetVal;
    }

    ubyte readCounter()
    {
        return value;
    }

    void tick()
    {
        static immutable uint cpuFrequency = 4_194_304;
        static immutable uint freq = 8192;

        if((cpu.doubleSpeedState() & 0b10000000) != 0)
            internalClock += 2;
        else
            internalClock++;

        if(internalClock >= cpuFrequency/freq)
        {
            internalClock = 0;

            if(value == 0xFF)
                value = resetVal;

            else
                value++;
        }
    }

    void connectCpu(CpuItf cpu)
    {
        this.cpu = cpu;
    }
};



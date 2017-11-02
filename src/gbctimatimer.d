module gbctimatimer;

import interfaces.timatimer;
import interfaces.cpu;
import genericgbctimer;


final class GbcTimaTimer : TimaTimerItf
{
    ubyte mode = 0x00;
    static immutable frequencies = [4096, 262144, 65536, 16384];
    GenericGbcTimer timer;
    CpuItf cpu;


    public:

    this()
    {
        timer = new GenericGbcTimer(frequencies[mode & 0x03], (mode & 0x04) != 0);
    }

    ubyte readCounter()
    {
        return timer.clock();
    }

    void writeCounter(ubyte value)
    {
        timer.setClock(value);
    }

    ubyte readModulo()
    {
        return timer.resetValue();
    }

    void writeModulo(ubyte value)
    {
        timer.setResetValue(value);
    }

    ubyte readControl()
    {
        return mode;
    }

    void writeControl(ubyte value)
    {
        mode = value & 0x07;
        timer.setFrequency(frequencies[mode & 0x03]);
        if((value & 0x04) == 0)
            timer.stop();
        else
            timer.start();
    }

    void tick()
    {
        if(timer.clock() == 0xFF)
            cpu.addInterruptRequests(0x04);
        timer.tick();
    }

    void connectCpu(CpuItf cpu)
    {
        this.cpu = cpu;
    }
};



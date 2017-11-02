module gbcdividertimer;

import interfaces.dividertimer;
import genericgbctimer;


final class GbcDividerTimer : DividerTimerItf
{
    GenericGbcTimer timer;


    public:

    this()
    {
        timer = new GenericGbcTimer(16384, true);
    }

    void writeCounter(ubyte)
    {
        timer.reset();
    }

    ubyte readCounter()
    {
        return timer.clock();
    }

    void tick()
    {
        timer.tick();
    }
};



module genericgbctimer;


// Suppose que les fréquences du timer sont des 
// diviseurs de la fréquence du CPU
class GenericGbcTimer
{
    private:

    ubyte value = 0;
    ubyte resetVal = 0;
    uint freq = 0;
    uint internalClock = 0;
    bool started;


    public:

    this(uint frequency, bool started)
    {
        this.freq = frequency;
        this.started = started;
    }

    void reset()
    {
        value = resetVal;
    }

    void setResetValue(ubyte resetValue)
    {
        this.resetVal = resetValue;
    }

    ubyte resetValue()
    {
        return resetVal;
    }

    ubyte clock()
    {
        return value;
    }

    void setClock(ubyte value)
    {
        this.value = value;
    }

    void setFrequency(uint freq)
    {
        this.internalClock = 0;
        this.freq = freq;
    }

    uint frequency()
    {
        return freq;
    }

    void stop()
    {
        started = false;
    }

    void start()
    {
        started = true;
    }

    bool isStarted()
    {
        return started;
    }

    bool tick()
    {
        static immutable uint cpuFrequency = 4_194_304;

        if(started)
        {
            internalClock++;

            if(internalClock*freq >= cpuFrequency)
            {
                internalClock = 0;

                if(value == 0xFF)
                {
                    value = resetVal;
                    return true;
                }
                else
                {
                    value++;
                }
            }
        }

        return false;
    }
};



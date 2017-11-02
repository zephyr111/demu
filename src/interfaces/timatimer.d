module timatimer;


interface TimaTimerItf
{
    public:

    ubyte readCounter();
    void writeCounter(ubyte value);
    ubyte readModulo();
    void writeModulo(ubyte value);
    ubyte readControl();
    void writeControl(ubyte value);
};



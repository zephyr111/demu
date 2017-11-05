module timer;


interface TimerItf
{
    public:

    ubyte readDividerCounter();
    void writeDividerCounter(ubyte value);

    ubyte readTimaCounter();
    void writeTimaCounter(ubyte value);
    ubyte readTimaModulo();
    void writeTimaModulo(ubyte value);
    ubyte readTimaControl();
    void writeTimaControl(ubyte value);
};



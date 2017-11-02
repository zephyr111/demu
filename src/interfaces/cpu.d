module cpu;


interface CpuItf
{
    public:

    void init();

    void addInterruptRequests(ubyte value);
    void setInterruptRequests(ubyte value);
    ubyte requestedInterrupts();
    void enableInterrupts(ubyte value);
    ubyte enabledInterrupts();
};



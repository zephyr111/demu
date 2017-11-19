module interfaces.cpu;


interface CpuItf
{
    public:

    void addInterruptRequests(ubyte value);
    void setInterruptRequests(ubyte value);
    ubyte requestedInterrupts();
    void enableInterrupts(ubyte value);
    ubyte enabledInterrupts();

    ubyte doubleSpeedState();
    void doubleSpeedRequest(ubyte value);
};



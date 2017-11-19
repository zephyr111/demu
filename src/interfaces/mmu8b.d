module interfaces.mmu8b;


interface Mmu8bItf
{
    public:

    ubyte loadByte(ushort address);
    void saveByte(ushort address, ubyte value);
};



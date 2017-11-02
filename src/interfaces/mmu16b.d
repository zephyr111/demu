module mmu16b;


interface Mmu16bItf
{
    public:

    ubyte loadByte(ushort address);
    void saveByte(ushort address, ubyte value);
    ushort loadWord(ushort address);
    void saveWord(ushort address, ushort value);
};



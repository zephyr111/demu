module reference;

import interfaces.mmu16b;


struct Reference
{
    Mmu16bItf mmu;
    const ushort address;


    public:

    this(Mmu16bItf mmu, ushort address)
    {
        this.mmu = mmu;
        this.address = address;
    }

    T opCast(T:ubyte)()
    {
        return mmu.loadByte(address);
    }

    T opCast(T:ushort)()
    {
        return mmu.loadWord(address);
    }

    T opAssign(T:ubyte)(T value)
    {
        mmu.saveByte(address, value);
        return value;
    }

    T opAssign(T:ushort)(T value)
    {
        mmu.saveWord(address, value);
        return value;
    }
}


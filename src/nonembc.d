module nonembc;

import std.stdio;
import interfaces.cartridgedata;
import interfaces.mmu8b;


final class NoneMbc : Mmu8bItf
{
    private:

    CartridgeDataItf cartridge;


    public:

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x7F:
                return cartridge.rawContent[address];

            case 0xA0: .. case 0xBF:
                return cartridge.rawContent[address]; // valid address ?

            default:
                throw new Exception("Execution failure: Out of memory access (read)");
        }
    }

    void saveByte(ushort address, ubyte value)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x7F:
                pragma(msg, "TODO: writting on ROM is ignored ?");
                writeln("WARNING: writting on ROM");
                //throw new Exception("Execution failure: forbidden memory access (read only access)");
                break;

            case 0xA0: .. case 0xBF:
                cartridge.rawContent[address] = value;
                break;

            default:
                throw new Exception("Execution failure: Out of memory access (write)");
        }
    }

    void connectCartridgeData(CartridgeDataItf cartridge)
    {
        this.cartridge = cartridge;
    }

    static CartridgeMmuType type()
    {
        return CartridgeMmuType.NONE;
    }
};



module nonembc;

import std.stdio;
import std.algorithm.searching;
import interfaces.cartridgedata;
import interfaces.mmu8b;


final class NoneMbc : Mmu8bItf
{
    private:

    CartridgeDataItf cartridge;
    ubyte[8*1024] ram = 0xFF;
    bool hasRam = true;


    public:

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x7F:
                return cartridge.rawContent[address];

            case 0xA0: .. case 0xBF:
                if(hasRam)
                    return ram[address - 0xA000];
                return 0xFF;

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
                if(hasRam)
                    ram[address - 0xA000] = value;
                break;

            default:
                throw new Exception("Execution failure: Out of memory access (write)");
        }
    }

    void connectCartridgeData(CartridgeDataItf cartridge)
    {
        static immutable int[] availableRamSizes = [0, 8192];

        this.cartridge = cartridge;

        if(cartridge.romSize() != 32768)
            throw new Exception("Bad GB file: mismatch between the ROM size and the controller");

        if(!availableRamSizes.canFind(cartridge.ramSize()))
            throw new Exception("Bad GB file: mismatch between the RAM size and the controller");

        hasRam = cartridge.ramSize() > 0;
    }

    static CartridgeMmuType type()
    {
        return CartridgeMmuType.NONE;
    }
};



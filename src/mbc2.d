module mbc2;

import std.stdio;
import std.algorithm.comparison;
import std.algorithm.searching;
import std.format;

import interfaces.cartridgedata;
import interfaces.mmu8b;


final class Mbc2 : Mmu8bItf
{
    private:

    CartridgeDataItf cartridge;
    bool ramEnabled = false;
    uint romBank = 1;
    ubyte[512] ram = 0xFF; // Only the lower 4 bits of the bytes are used
    uint romAddressMask = 0x00000000;


    public:

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x3F:
                return cartridge.rawContent[address];

            case 0x40: .. case 0x7F:
                return cartridge.rawContent[((romBank << 14) | (address - 0x4000)) & romAddressMask];

            case 0xA0: .. case 0xA1:
                if(ramEnabled)
                    return ram[address - 0xA000];
                return 0xFF;

            default:
                throw new Exception(format("Execution failure: Out of memory access (read, address: %0.4X)", address));
        }
    }

    void saveByte(ushort address, ubyte value)
    {
        switch(address >> 8)
        {
            // RAM enable/disable
            case 0x00: .. case 0x1F:
                ramEnabled = (address & 0x0100) == 0;
                break;

            // ROM bank number
            case 0x20: .. case 0x3F:
                if((address & 0x0100) != 0)
                    romBank = max(value & 0b00001111, 1);
                break;

            // RAM
            case 0xA0: .. case 0xA1:
                if(ramEnabled)
                    ram[address - 0xA000] = value | 0b11110000;
                break;

            default:
                pragma(msg, "Writting on forbidden memory (reserved area) is ignored");
                writeln("WARNING: forbidden memory write access (reserved area)");
                //throw new Exception(format("Execution failure: Out of memory access (write, address: %0.4X)", address));
                break;
        }
    }

    void connectCartridgeData(CartridgeDataItf cartridge)
    {
        static immutable int[] availableRomSizes = [32768, 65536, 131072, 262144];

        this.cartridge = cartridge;

        if(!availableRomSizes.canFind(cartridge.romSize()))
            throw new Exception("Bad GB file: mismatch between the ROM size and the controller (MBC2)");

        // The amount of RAM is unchecked as it must be set to 0 in the 
        // cartridge header even though the controler actually have a 
        // built-in RAM...

        romAddressMask = cartridge.romSize() - 1;
    }

    static CartridgeMmuType type()
    {
        return CartridgeMmuType.MBC2;
    }
};



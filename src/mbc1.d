module mbc1;

import std.stdio;
import std.algorithm.searching;
import std.algorithm.comparison;
import std.format;

import interfaces.cartridgedata;
import interfaces.mmu8b;


final class Mbc1 : Mmu8bItf
{
    private:

    CartridgeDataItf cartridge;
    bool ramEnabled = false;
    uint romBank = 1;
    uint upperBits = 0;
    uint romModeMaskBank1 = 0x00;
    uint romModeMaskBank2 = 0xFF;
    uint ramModeMask = 0x00;
    ubyte[32*1024] ram = 0xFF;
    uint romAddressMask = 0x00000000;
    uint ramAddressMask = 0x00000000;
    bool hasRam = true;


    public:

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x3F:
                return cartridge.rawContent[(((upperBits & romModeMaskBank1) << 19) | address) & romAddressMask];

            case 0x40: .. case 0x7F:
                return cartridge.rawContent[(((upperBits & romModeMaskBank2) << 19) | (romBank << 14) | (address - 0x4000)) & romAddressMask];

            case 0xA0: .. case 0xBF:
                if(ramEnabled)
                    return ram[(((upperBits & ramModeMask) << 13) | (address - 0xA000)) & ramAddressMask];
                return 0xFF;

            default:
                throw new Exception(format("Execution failure: Out of memory access (read, address: %0.4X)", address));
        }
    }

    void saveByte(ushort address, ubyte value)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x1F:
                ramEnabled = (value & 0b00001111) == 0b00001010 && hasRam;
                break;

            case 0x20: .. case 0x3F:
                romBank = max(value & 0b00011111, 1);
                break;

            case 0x40: .. case 0x5F:
                upperBits = value & 0b00000011;
                break;

            case 0x60: .. case 0x7F:
                if((value & 0b00000001) == 0)
                {
                    romModeMaskBank1 = 0x00;
                    romModeMaskBank2 = 0xFF;
                    ramModeMask = 0x00;
                }
                else
                {
                    romModeMaskBank1 = 0xFF;
                    romModeMaskBank2 = 0xFF;
                    ramModeMask = 0xFF;
                }
                break;

            case 0xA0: .. case 0xBF:
                if(ramEnabled)
                    ram[(((upperBits & ramModeMask) << 13) | (address - 0xA000)) & ramAddressMask] = value;
                break;

            default:
                throw new Exception(format("Execution failure: Out of memory access (write, address: %0.4X)", address));
        }
    }

    void connectCartridgeData(CartridgeDataItf cartridge)
    {
        static immutable int[] availableRomSizes = [32768, 65536, 131072, 262144, 524288, 1048576, 2097152];
        static immutable int[] availableRamSizes = [0, 2048, 8192, 32768];

        this.cartridge = cartridge;

        if(!availableRomSizes.canFind(cartridge.romSize()))
            throw new Exception("Bad GB file: mismatch between the ROM size and the controller (MBC1)");

        if(!availableRamSizes.canFind(cartridge.ramSize()))
            throw new Exception("Bad GB file: mismatch between the RAM size and the controller (MBC1)");

        hasRam = cartridge.ramSize() > 0;
        romAddressMask = cartridge.romSize() - 1;
        ramAddressMask = cartridge.ramSize() - 1;
    }

    static CartridgeMmuType type()
    {
        return CartridgeMmuType.MBC1;
    }
};



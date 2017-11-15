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
    uint romModeMask = 0xFF;
    uint ramModeMask = 0x00;
    ubyte[32*1024] ram = 0xFF;
    uint romAddressMask = 0x00000000;
    uint ramAddressMask = 0x00000000;


    public:

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x3F:
                return cartridge.rawContent[address];

            case 0x40: .. case 0x7F:
                return cartridge.rawContent[(((upperBits & romModeMask) << 19) | (romBank << 14) | (address - 0x4000)) & romAddressMask];

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
                ramEnabled = (value & 0x0F) == 0x0A;
                break;

            case 0x20: .. case 0x3F:
                romBank = max(value & 0x1F, 1);
                break;

            case 0x40: .. case 0x5F:
                upperBits = value & 0b00000011;
                break;

            case 0x60: .. case 0x7F:
                if((value & 0b00000001) == 0)
                {
                    romModeMask = 0xFF;
                    ramModeMask = 0x00;
                }
                else
                {
                    romModeMask = 0x00;
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
        static immutable int[] availableRomSizes = [65536, 131072, 262144, 524288, 1048576, 2097152];
        static immutable int[] availableRamSizes = [2048, 8192, 32768];

        this.cartridge = cartridge;

        if(!availableRomSizes.canFind(cartridge.romSize()))
            throw new Exception("Bad GB file: mismatch between the ROM size and the controller (MBC1)");

        if(!availableRamSizes.canFind(cartridge.ramSize()))
            throw new Exception("Bad GB file: mismatch between the RAM size and the controller (MBC1)");

        romAddressMask = cartridge.romSize() - 1;
        ramAddressMask = cartridge.ramSize() - 1;
    }

    static CartridgeMmuType type()
    {
        return CartridgeMmuType.MBC1;
    }
};



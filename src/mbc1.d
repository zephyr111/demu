module mbc1;

import std.stdio;
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
    ubyte[32*1024] ram = 0xFF;


    public:

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x3F:
                return cartridge.rawContent[address];

            case 0x40: .. case 0x7F:
                return cartridge.rawContent[((upperBits & romModeMask) << 19) | (romBank << 14) | (address - 0x4000)];

            case 0xA0: .. case 0xBF:
                if(ramEnabled)
                    return ram[((upperBits&(~romModeMask)) << 13) | (address - 0xA000)];
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
                romModeMask = cast(ubyte)((value & 0b00000001) + 0xFF);
                break;

            case 0xA0: .. case 0xBF:
                if(ramEnabled)
                    ram[((upperBits&(~romModeMask)) << 13) | (address - 0xA000)] = value;
                break;

            default:
                throw new Exception(format("Execution failure: Out of memory access (write, address: %0.4X)", address));
        }
    }

    void connectCartridgeData(CartridgeDataItf cartridge)
    {
        this.cartridge = cartridge;
    }

    static CartridgeMmuType type()
    {
        return CartridgeMmuType.MBC1;
    }
};



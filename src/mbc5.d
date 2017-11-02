module mbc5;

import std.stdio;
import std.format;

import interfaces.cartridgedata;
import interfaces.mmu8b;


pragma(msg, "TODO: check for RAM usage");
final class Mbc5 : Mmu8bItf
{
    private:

    CartridgeDataItf cartridge;
    bool ramEnabled = false;
    uint romBank = 1;
    uint upperBits = 0;
    ubyte[128*1024] ram = 0xFF;


    public:

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x3F:
                return cartridge.rawContent[address];

            case 0x40: .. case 0x7F:
                return cartridge.rawContent[(romBank << 14) | (address - 0x4000)];

            case 0xA0: .. case 0xBF:
                if(ramEnabled)
                    return ram[(upperBits << 13) | (address - 0xA000)];
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
                ramEnabled = (value & 0b00001111) == 0x0A;
                break;

            case 0x20: .. case 0x2F:
                romBank = (romBank & 0xFF00) | value;
                break;

            case 0x30: .. case 0x3F:
                romBank = ((value & 0b00000001) << 8) | (romBank & 0x00FF);
                break;

            case 0x40: .. case 0x5F:
                upperBits = value & 0b00001111;
                break;

            case 0xA0: .. case 0xBF:
                if(ramEnabled)
                    ram[(upperBits << 13) | (address - 0xA000)] = value;
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
        return CartridgeMmuType.MBC5;
    }
};



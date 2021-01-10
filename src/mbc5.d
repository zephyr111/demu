module mbc5;

import std.stdio;
import std.format;
import std.algorithm.searching;

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
    uint romAddressMask = 0x00000000;
    uint ramAddressMask = 0x00000000;
    bool hasRam = true;


    public:

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x3F:
                return cartridge.rawContent[address];

            case 0x40: .. case 0x7F:
                return cartridge.rawContent[((romBank << 14) | (address - 0x4000)) & romAddressMask];

            case 0xA0: .. case 0xBF:
                if(ramEnabled)
                    return ram[((upperBits << 13) | (address - 0xA000)) & ramAddressMask];
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
                ramEnabled = value == 0x0A && hasRam;
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
                    ram[((upperBits << 13) | (address - 0xA000)) & ramAddressMask] = value;
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
        static immutable int[] availableRomSizes = [32768, 65536, 131072, 262144, 524288, 1048576, 2097152, 4194304, 8388608];
        static immutable int[] availableRamSizes = [0, 8192, 32768, 131072];

        this.cartridge = cartridge;

        if(!availableRomSizes.canFind(cartridge.romSize()))
            throw new Exception("Bad GB file: mismatch between the ROM size and the controller (MBC5)");

        if(!availableRamSizes.canFind(cartridge.ramSize()))
            throw new Exception("Bad GB file: mismatch between the RAM size and the controller (MBC5)");

        hasRam = cartridge.ramSize() > 0;
        romAddressMask = cartridge.romSize() - 1;
        ramAddressMask = cartridge.ramSize() - 1;
    }

    static CartridgeMmuType type()
    {
        return CartridgeMmuType.MBC5;
    }
};



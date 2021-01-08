module gbcfile;

import std.stdio;
import std.file;
import std.algorithm;
import std.range;

import interfaces.cartridgedata;


final class GbcFile : CartridgeDataItf
{
    private:

    struct Header
    {
        align(1):
            ubyte[4] entryPoint;
            ubyte[48] nintendoLogo;
            ubyte[11] title;
            ubyte[4] manufacturerCode;
            ubyte cgbFlag;
            ushort newLicenseeCode;
            ubyte sgbFlag;
            ubyte cartridgeType;
            ubyte romSize;
            ubyte ramSize;
            ubyte destinationCode;
            ubyte oldLicenseeCode;
            ubyte maskRomVersionNumber;
            ubyte headerChecksum;
            ushort globalChecksum;
    };

    Header header;
    ubyte[] rawData;


    public:

    this(string romFilename)
    {
        rawData = cast(ubyte[])read(romFilename);

        if(rawData.length < Header.sizeof+0x100)
            throw new Exception("Bad GB file");

        header = *cast(Header*)(rawData.ptr + 0x100);

        check();
    }

    string title() const
    {
        return cast(string)until!"a == 0"(header.title[]).array;
    }

    string manufacturerCode() const
    {
        return cast(string)until!"a == 0"(header.manufacturerCode[]).array;
    }

    GameboyType requiredGameboy() const
    {
        if(header.cgbFlag == 0xC0)
            return GameboyType.COLOR; // Cgb only compatible

        if(header.cgbFlag == 0x80)
            return GameboyType.COLOR; // Cgb and Sgb compatible

        if(header.sgbFlag == 0x03 && header.oldLicenseeCode == 0x33)
            return GameboyType.SUPER; // Sgb compatible

        return GameboyType.NORMAL;
    }

    ushort licenseCode() const
    {
        if(header.oldLicenseeCode == 0x33)
            return header.newLicenseeCode;

        return header.oldLicenseeCode;
    }

    CartridgeMmuType memoryControlerType() const
    {
        switch(header.cartridgeType)
        {
            case 0x00:
            case 0x08:
            case 0x09:
                return CartridgeMmuType.NONE;

            case 0x01:
            ..
            case 0x03:
                return CartridgeMmuType.MBC1;

            case 0x05:
            ..
            case 0x06:
                return CartridgeMmuType.MBC2;

            case 0x0B:
            ..
            case 0x0D:
                return CartridgeMmuType.MMM0;

            case 0x0F:
            ..
            case 0x13:
                return CartridgeMmuType.MBC3;

            case 0x15:
            ..
            case 0x17:
                return CartridgeMmuType.MBC4;

            case 0x19:
            ..
            case 0x1E:
                return CartridgeMmuType.MBC5;

            case 0xFC:
                return CartridgeMmuType.POCKET_CAMERA;

            case 0xFD:
                return CartridgeMmuType.BANDAI_TAMA5;

            case 0xFE:
                return CartridgeMmuType.HUC3;

            case 0xFF:
                return CartridgeMmuType.HUC1;

            default:
                return CartridgeMmuType.UNKNOWN;
        }
    }

    uint romSize() const
    {
        immutable uint bankSize = 16 * 1024;

        if(header.romSize <= 0x08)
            return (2 << header.romSize) * bankSize;

        return [72, 80, 96][header.romSize - 0x52] * bankSize;
    }

    uint ramSize() const
    {
        if(memoryControlerType() == CartridgeMmuType.MBC2)
        {
            // The MBC2 chip specify that there is no ram, 
            // although it actually includes a built-in RAM of 512 x 4 bits.
            return 256;
        }

        // Note: guess the check is already done
        return [0, 2, 8, 32, 128, 64][header.ramSize] * 1024;
    }

    bool japaneseVersion() const
    {
        return header.destinationCode == 0x00;
    }

    const(ubyte)[] rawContent() const
    {
        return rawData;
    }

    ubyte[] rawContent()
    {
        return rawData;
    }


    private:

    void check() const
    {
        immutable ubyte[48] defaultLogo = [
            0xCE, 0xED, 0x66, 0x66, 0xCC, 0x0D, 0x00, 0x0B, 0x03, 0x73, 0x00, 0x83, 0x00, 0x0C, 0x00, 0x0D,
            0x00, 0x08, 0x11, 0x1F, 0x88, 0x89, 0x00, 0x0E, 0xDC, 0xCC, 0x6E, 0xE6, 0xDD, 0xDD, 0xD9, 0x99,
            0xBB, 0xBB, 0x67, 0x63, 0x6E, 0x0E, 0xEC, 0xCC, 0xDD, 0xDC, 0x99, 0x9F, 0xBB, 0xB9, 0x33, 0x3E
        ];

        // Header checking

        ubyte sum = 0;

        for(int i=0x0134 ; i<=0x014C ; i++)
        {
            sum -= rawData[i];
            sum--;
        }

        if(sum != header.headerChecksum)
            throw new Exception("Bad GB file: invalid checksum");

        // Global checksum not used (Gameboys doesn't verify this checksum)

        // Fields checking

        if(defaultLogo != header.nintendoLogo)
            throw new Exception("Bad GB file (bad nintendo logo)");

        //if(header.cgbFlag != 0x80 && header.cgbFlag != 0xC0)
        //    throw new Exception("Bad GB file: unknown CGB flag");

        if(header.sgbFlag != 0x00 && header.sgbFlag != 0x03)
            throw new Exception("Bad GB file: unknown SGB flag");

        if((header.romSize > 0x08 && header.romSize < 0x52) || header.romSize > 0x54)
            throw new Exception("Bad GB file: unknown ROM size");

        if(header.ramSize > 0x05)
            throw new Exception("Bad GB file: unknown RAM size");

        if(header.destinationCode > 0x01)
            throw new Exception("Bad GB file: unknown destination code");
    }
};



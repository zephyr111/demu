module mbc3;

pragma(msg, "TODO: import useless");
import std.stdio;
import std.algorithm.comparison;
import std.datetime;
import std.format;
import core.time;

import interfaces.cartridgedata;
import interfaces.mmu8b;


pragma(msg, "TODO: RTC must depend on internal clock (eg. virtual time, not real time) ==> add a tick method");
final class Mbc3 : Mmu8bItf
{
    private:

    CartridgeDataItf cartridge;
    bool ramAndRtcEnabled = false;
    uint romBank = 1;
    uint upperBits = 0;
    ubyte[32*1024] ram = 0xFF;
    ubyte lastRtcWrite = 0xFF;
    StopWatch chrono;


    public:

    this()
    {
        //DateTime now = cast(DateTime)Clock.currTime;
        //writeln(beginning.days, " ", beginning.hours, ":", beginning.minutes, ":", beginning.seconds);
        chrono.start();
    }

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            case 0x00: .. case 0x3F:
                return cartridge.rawContent[address];

            case 0x40: .. case 0x7F:
                return cartridge.rawContent[(romBank << 14) | (address - 0x4000)];

            case 0xA0: .. case 0xBF:
                if(ramAndRtcEnabled)
                {
                    if(upperBits >= 0x08 && upperBits <= 0x0C)
                    {
                        switch(upperBits)
                        {
                            case 0x08:
                                return cast(ubyte)dur!"seconds"(chrono.peek.seconds).seconds;

                            case 0x09:
                                return cast(ubyte)dur!"seconds"(chrono.peek.seconds).minutes;

                            case 0x0A:
                                return cast(ubyte)dur!"seconds"(chrono.peek.seconds).hours;

                            case 0x0B:
                                pragma(msg, "TODO: support real time clock with more than 30 days");
                                return cast(ubyte)dur!"seconds"(chrono.peek.seconds).days;

                            case 0x0C:
                                return (chrono.running) ? 0b00111110 : 0b01111110;

                            default:
                                throw new Exception("RTC not implemented");
                        }
                    }
                    else
                    {
                        pragma(msg, "TODO: support RAM access (in read mode)");
                        //writeln("WARNING: reading on cartridge RAM not yet supported");
                        return ram[(upperBits << 13) | (address - 0xA000)];
                    }
                }
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
                ramAndRtcEnabled = (value & 0x0F) == 0x0A;
                break;

            case 0x20: .. case 0x3F:
                romBank = max(value & 0x7F, 1);
                break;

            case 0x40: .. case 0x5F:
                if(value >= 0x08 && value <= 0x0C)
                    upperBits = value;
                else
                    upperBits = value & 0x03;
                break;

            case 0x60: .. case 0x7F:
                if(lastRtcWrite == 0x00 && value == 0x01)
                {
                    if(chrono.running)
                        chrono.stop();
                    else
                        chrono.start();
                }
                lastRtcWrite = value;
                break;

            case 0xA0: .. case 0xBF:
                if(ramAndRtcEnabled)
                {
                    if(value >= 0x08 && value <= 0x0C)
                    {
                        //
                        //throw new Exception("RTC not implemented");
                    }
                    else
                    {
                        pragma(msg, "TODO: support RAM access (in write mode)");
                        //writeln("WARNING: writting on cartridge RAM is not yet supported");
                        ram[(upperBits << 13) | (address - 0xA000)] = value;
                    }
                }
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
        return CartridgeMmuType.MBC3;
    }
};



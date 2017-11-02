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
pragma(msg, "TODO: support RAM saving to a file");
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
                    if(upperBits <= 0x03)
                    {
                        return ram[(upperBits << 13) | (address - 0xA000)];
                    }
                    else if(upperBits >= 0x08 && upperBits <= 0x0C)
                    {
                        auto chronoTime = dur!"seconds"(chrono.peek.seconds).split!("days", "hours", "minutes", "seconds");

                        switch(upperBits)
                        {
                            case 0x08:
                                return cast(ubyte)chronoTime.seconds;

                            case 0x09:
                                return cast(ubyte)chronoTime.minutes;

                            case 0x0A:
                                return cast(ubyte)chronoTime.hours;

                            case 0x0B:
                                return cast(ubyte)chronoTime.days;

                            case 0x0C:
                                const ubyte dayCarryMask = ((chronoTime.days >> 9) > 0) ? 0b11000001 : 0b01000001;
                                const ubyte runningMask = (chrono.running) ? 0b10000001 : 0b11000001;
                                const ubyte dayMsbMask = cast(ubyte)(((chronoTime.days >> 8) & 0b00000001) | 0b11000000);
                                return dayCarryMask & runningMask & dayMsbMask;

                            default:
                                throw new Exception(format("Execution failure: Out of memory access (read, address: %0.4X)", address));
                        }
                    }
                    else
                    {
                        throw new Exception(format("Execution failure: Out of memory access (read, address: %0.4X, upperBits: %0.2X)", address, upperBits));
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
                    if(upperBits <= 0x03)
                    {
                        ram[(upperBits << 13) | (address - 0xA000)] = value;
                    }
                    else if(upperBits >= 0x08 && upperBits <= 0x0C)
                    {
                        auto chronoTime = dur!"seconds"(chrono.peek.seconds).split!("days", "hours", "minutes", "seconds");

                        switch(upperBits)
                        {
                            case 0x08:
                                auto newTime = TickDuration.from!"seconds"(chrono.peek.seconds + (value - chronoTime.seconds));
                                chrono.setMeasured(newTime);
                                break;

                            case 0x09:
                                auto newTime = TickDuration.from!"seconds"(chrono.peek.seconds + (value - chronoTime.minutes) * 60);
                                chrono.setMeasured(newTime);
                                break;

                            case 0x0A:
                                auto newTime = TickDuration.from!"seconds"(chrono.peek.seconds + (value - chronoTime.hours) * 3600);
                                chrono.setMeasured(newTime);
                                break;

                            case 0x0B:
                                auto newTime = TickDuration.from!"seconds"(chrono.peek.seconds + (value - chronoTime.days) * 86400);
                                chrono.setMeasured(newTime);
                                break;

                            case 0x0C://flags
                                pragma(msg, "TODO: RTC flag setting not fully implemented (cf carry)");
                                const ubyte dayCarry = value >> 7;
                                const bool running = cast(bool)(value & 0b01000000);
                                const ubyte dayMsb = value & 0b00000001;
                                auto newTime = TickDuration.from!"seconds"(chrono.peek.seconds + (dayMsb - chronoTime.days/256) * (86400*256));
                                chrono.setMeasured(newTime);
                                if(running)
                                    chrono.start();
                                else
                                    chrono.stop();
                                break;

                            default:
                                throw new Exception(format("Execution failure: Out of memory access (read, address: %0.4X)", address));
                        }
                    }
                    else
                    {
                        throw new Exception(format("Execution failure: Out of memory access (write, address: %0.4X, upperBits: %0.2X)", address, upperBits));
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



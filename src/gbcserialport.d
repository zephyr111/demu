module gbcserialport;

import std.stdio;
import std.string;
import std.algorithm.comparison;
import std.algorithm.iteration;
import std.ascii;
import std.range;

import interfaces.cpu;
import interfaces.mmu8b;


final class GbcSerialPort : Mmu8bItf
{
    pragma(msg, "TODO: undefined value for currStreamValue and transferControl");


    private:

    CpuItf cpu;
    ubyte currInValue = 0xFF; // undefined
    ubyte currOutValue = 0xFF; // undefined
    ubyte[] inStream = [];
    ubyte[] outStream = [];
    int internalClock = 0;
    ubyte transferControl = 0x00; // undefined


    public:

    ubyte loadByte(ushort address)
    {
        assert((address & 0xFF00) == 0xFF00);

        switch(address & 0xFF)
        {
            case 0x01:
                if(inStream.empty)
                    return 0xFF;
                return inStream[0];

            case 0x02:
                return transferControl | 0b01111100;

            default:
                throw new Exception(format("Execution failure: IO Ports access not implemented (port:0x%0.2X, mode:read)", address-0xFF00));
        }
    }

    void saveByte(ushort address, ubyte value)
    {
        assert((address & 0xFF00) == 0xFF00);

        switch(address & 0xFF)
        {
            case 0x01:
                currOutValue = value;
                break;

            case 0x02:
                transferControl = value & 0b10000011;
                break;

            default:
                throw new Exception(format("Execution failure: IO Ports access not implemented (port:0x%0.2X, mode:write)", address-0xFF00));
        }
    }

    void tick()
    {
        if(startTransferFlag)
        {
            internalClock += ((cpu.doubleSpeedState() & 0b10000000) != 0) ? 2 : 1;

            if(internalClock >= 16 && fastClockFlag || internalClock >= 512 && !fastClockFlag)
            {
                internalClock = 0;

                if(!inStream.empty)
                    inStream = inStream[1..$];

                if(outStream.empty && currOutValue != '\n' || !outStream.empty)
                {
                    if(outStream.length == outStream.capacity)
                        outStream.reserve(max(outStream.length*2, 1));
                    outStream ~= currOutValue;
                
                    if(currOutValue == '\n')
                    {
                        const string printedStr = outStream[0..$-1]
                                                    .map!"cast(char)a"
                                                    .map!(a => (a.isGraphical || a.isWhite) ? a : '?')
                                                    .strip.array;
                        writefln("Message from serial port: \"%s\"", printedStr);
                        outStream = [];
                    }
                    else if(outStream.length >= 256)
                    {
                        const string printedStr = outStream[0..$]
                                                    .map!"cast(char)a"
                                                    .map!(a => (a.isGraphical || a.isWhite) ? a : '?')
                                                    .strip.array;
                        writefln("Message from serial port: \"%s\"...", printedStr);
                        outStream = outStream[256..$];
                    }
                }

                startTransferFlagSetting(false);
            }
        }
        else
        {
            internalClock = 0;
        }
    }

    void connectCpu(CpuItf cpu)
    {
        this.cpu = cpu;
    }


    private:

    bool startTransferFlag() const
    {
        immutable ubyte mask = 0b10000000;
        return (transferControl & mask) != 0;
    }

    void startTransferFlagSetting(bool value)
    {
        immutable ubyte mask = 0b10000000;

        if(value)
            transferControl |= mask;
        else
            transferControl &= ~mask;
    }

    bool fastClockFlag() const
    {
        immutable ubyte mask = 0b00000010;
        return (transferControl & mask) != 0;
    }

    void fastClockFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00000010;

        if(value)
            transferControl |= mask;
        else
            transferControl &= ~mask;
    }

    bool internalClockFlag() const
    {
        immutable ubyte mask = 0b00000001;
        return (transferControl & mask) != 0;
    }

    void internalClockFlagSetting(bool value)
    {
        immutable ubyte mask = 0b00000001;

        if(value)
            transferControl |= mask;
        else
            transferControl &= ~mask;
    }
};



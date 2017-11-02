module gbcmmu;

import std.stdio;
import std.string;
import std.conv;

import interfaces.cpu;
import interfaces.gpu;
import interfaces.dividertimer;
import interfaces.timatimer;
import interfaces.joystick;
import interfaces.mmu16b;
import interfaces.mmu8b;


final class GbcMmu : Mmu16bItf
{
    immutable bool useCgb;
    CpuItf cpu;
    Mmu8bItf cartridgeMmu;
    Mmu8bItf gpuMmu;
    Mmu8bItf soundControllerMmu;
    DividerTimerItf dividerTimer;
    TimaTimerItf timaTimer;
    JoystickItf joystick;
    Mmu8bItf serialPort;
    ubyte[0x8000] workingRam; // 32 Ko (note: 8Ko for pre-GBC console)
    ubyte[0x80] highRam; // 128 octets
    ubyte workingRamBank = 1;
    ushort dmaSrcAddr = 0x0000; // undefined
    ushort dmaDstAddr = 0x0000; // undefined


    public:

    this(bool cgbMode)
    {
        useCgb = cgbMode;
    }

    void saveByte(ushort address, ubyte value)
    {
        switch(address >> 8)
        {
            // Cartridge ROM+RAM
            case 0x00: .. case 0x7F:
            case 0xA0: .. case 0xBF:
                cartridgeMmu.saveByte(address, value);
                break;

            // Video RAM
            case 0x80: .. case 0x9F:
                gpuMmu.saveByte(address, value);
                break;

            // Working RAM
            case 0xC0: .. case 0xCF:
                workingRam[address - 0xC000] = value;
                break;

            // Working RAM switchable bank
            case 0xD0: .. case 0xDF:
                workingRam[(workingRamBank << 12) | (address - 0xD000)] = value;
                break;

            // Echo
            case 0xE0: .. case 0xFD:
                saveByte(cast(ushort)(address - (0xE000-0xC000)), value);
                break;

            case 0xFE: .. case 0xFF:
                switch(address)
                {
                    // Sprite Attribute Table
                    case 0xFE00: .. case 0xFE9F:
                        gpuMmu.saveByte(address, value);
                        break;

                    // Forbidden
                    case 0xFEA0: .. case 0xFEFF:
                        pragma(msg, "Writting on forbidden memory (reserved area) is ignored");
                        //throw new Exception("Execution failure: forbidden memory write access (reserved area)");
                        writeln("WARNING: forbidden memory write access (reserved area)");
                        break;

                    // IO Ports
                    case 0xFF00: .. case 0xFF7F:
                        //writefln("DEBUG: WRITE TO %0.4X WITH VALUE %0.2X", address, value);
                        switch(address)
                        {
                            case 0xFF00:
                                joystick.writeState(value);
                                break;

                            case 0xFF01: .. case 0xFF02:
                                serialPort.saveByte(address, value);
                                break;

                            case 0xFF04:
                                dividerTimer.writeCounter(value);
                                break;

                            case 0xFF05:
                                timaTimer.writeCounter(value);
                                break;

                            case 0xFF06:
                                timaTimer.writeModulo(value);
                                break;

                            case 0xFF07:
                                timaTimer.writeControl(value);
                                break;

                            case 0xFF0F:
                                cpu.setInterruptRequests(value);
                                break;

                            case 0xFF10: .. case 0xFF3F:
                                soundControllerMmu.saveByte(address, value);
                                break;

                            case 0xFF40: .. case 0xFF45:
                            case 0xFF47: .. case 0xFF4B:
                            case 0xFF4F:
                            case 0xFF68: .. case 0xFF6B:
                                gpuMmu.saveByte(address, value);
                                break;

                            case 0xFF46:
                                //writeln("WARNING: DMA used (unstable feature) [romAddr:", value<<8, ", gpuAddr: OAM]");
                                pragma(msg, "DMA unstable and timing not yet implemented (TODO)");
                                foreach(int i ; 0x00..0xA0)
                                    gpuMmu.saveByte(cast(ushort)(0xFE00 + i), loadByte(cast(ushort)((value << 8) + i)));
                                break;

                            case 0xFF4D:
                                pragma(msg, "TODO: fully support double speed mode");
                                writeln("WARNING: the game want to use the double speed mode (not fully supported)");
                                cpu.doubleSpeedRequest(value);
                                break;

                            case 0xFF51:
                                if(useCgb)
                                    dmaSrcAddr = (value << 8) | (dmaSrcAddr & 0x00FF);
                                else
                                    writefln("WARNING: writting on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                break;

                            case 0xFF52:
                                if(useCgb)
                                    dmaSrcAddr = (dmaSrcAddr & 0xFF00) | value;
                                else
                                    writefln("WARNING: writting on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                break;

                            case 0xFF53:
                                if(useCgb)
                                    dmaDstAddr = (value << 8) | (dmaDstAddr & 0x00FF);
                                else
                                    writefln("WARNING: writting on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                break;

                            case 0xFF54:
                                if(useCgb)
                                    dmaDstAddr = (dmaDstAddr & 0xFF00) | value;
                                else
                                    writefln("WARNING: writting on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                break;

                            case 0xFF55:
                                if(useCgb)
                                {
                                    //writeln("WARNING: Advanced DMA used (unstable feature) [romAddr:", value<<8, ", gpuAddr: OAM]");
                                    pragma(msg, "Advanced DMA unstable and timing not yet implemented (TODO)");
                                    const bool generalPurposeDma = (value & 0b10000000) == 0;
                                    const uint dataSize = ((value & 0b01111111) + 1) * 16;
                                    foreach(int i ; 0..dataSize)
                                        saveByte(cast(ushort)(dmaDstAddr + i), loadByte(cast(ushort)(dmaSrcAddr + i)));
                                }
                                else
                                    writefln("WARNING: writting on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                break;

                            case 0xFF56:
                                pragma(msg, "Writting on infrared IO Ports is ignored");
                                writeln("WARNING: Infrared used (unimplemented feature)");
                                break;

                            case 0xFF70:
                                if(useCgb)
                                {
                                    workingRamBank = value & 0x07;

                                    if(workingRamBank == 0)
                                        workingRamBank = 1;
                                }
                                else
                                {
                                    writefln("WARNING: writting on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                }
                                break;

                            default:
                                pragma(msg, "Writting on unimplemented IO Ports is ignored");
                                writefln("WARNING: Port 0x%0.2X used in write mode (unimplemented feature)", address-0xFF00);
                                break;//throw new Exception(format("Execution failure: IO Ports access not implemented (port: 0x%0.2X, mode:write)", address-0xFF00));
                        }
                        break;

                    // High RAM
                    case 0xFF80: .. case 0xFFFE:
                        highRam[address - 0xFF80] = value;
                        break;

                    // IE Flag
                    case 0xFFFF:
                        cpu.enableInterrupts(value);
                        break;

                    default:
                        throw new Exception(format("Programming error: bad address (%0.4X)", address));
                }
                break;

            default:
                throw new Exception(format("Programming error: bad address (%0.4X)", address));
        }
    }

    void saveWord(ushort address, ushort value)
    {
        saveByte(address++, value & 0xFF);
        saveByte(address, value >> 8);
    }

    ubyte loadByte(ushort address)
    {
        switch(address >> 8)
        {
            // Cartridge ROM+RAM
            case 0x00: .. case 0x7F:
            case 0xA0: .. case 0xBF:
                return cartridgeMmu.loadByte(address);

            // Video RAM
            case 0x80: .. case 0x9F:
                return gpuMmu.loadByte(address);

            // Working RAM
            case 0xC0: .. case 0xCF:
                return workingRam[address - 0xC000];

            // Working RAM switchable bank
            case 0xD0: .. case 0xDF:
                return workingRam[(workingRamBank << 12) | (address - 0xD000)];

            // Echo
            case 0xE0: .. case 0xFD:
                return loadByte(cast(ushort)(address - (0xE000-0xC000)));

            case 0xFE: .. case 0xFF:
                switch(address)
                {
                    // Sprite Attribute Table
                    case 0xFE00: .. case 0xFE9F:
                        return gpuMmu.loadByte(address);

                    // Forbidden
                    case 0xFEA0: .. case 0xFEFF:
                        pragma(msg, "Reading on forbidden memory (reserved area) is ignored");
                        //throw new Exception("Execution failure: forbidden memory read access (reserved area)");
                        writeln("WARNING: forbidden memory read access (reserved area)");
                        return 0xFF;

                    // IO Ports
                    case 0xFF00: .. case 0xFF7F:
                        //writefln("DEBUG: READ TO %0.4X", address);
                        switch(address)
                        {
                            case 0xFF00:
                                return joystick.readState();

                            case 0xFF01: .. case 0xFF02:
                                return serialPort.loadByte(address);

                            case 0xFF04:
                                return dividerTimer.readCounter();

                            case 0xFF05:
                                return timaTimer.readCounter();

                            case 0xFF06:
                                return timaTimer.readModulo();

                            case 0xFF07:
                                return timaTimer.readControl();

                            case 0xFF0F:
                                return cpu.requestedInterrupts();

                            case 0xFF10: .. case 0xFF3F:
                                return soundControllerMmu.loadByte(address);

                            case 0xFF40: .. case 0xFF45:
                            case 0xFF47: .. case 0xFF4B:
                            case 0xFF4F:
                            case 0xFF68: .. case 0xFF6B:
                                return gpuMmu.loadByte(address);

                            case 0xFF4D:
                                return cpu.doubleSpeedState();

                            pragma(msg, "TODO: check if DMA infos can be read");
                            case 0xFF51:
                                if(useCgb)
                                    return dmaSrcAddr >> 8;
                                writefln("WARNING: reading on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                return 0xFF;

                            pragma(msg, "TODO: check if DMA infos can be read");
                            case 0xFF52:
                                if(useCgb)
                                    return dmaSrcAddr & 0x00FF;
                                writefln("WARNING: reading on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                return 0xFF;

                            pragma(msg, "TODO: check if DMA infos can be read");
                            case 0xFF53:
                                if(useCgb)
                                    return dmaDstAddr >> 8;
                                writefln("WARNING: reading on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                return 0xFF;

                            pragma(msg, "TODO: check if DMA infos can be read");
                            case 0xFF54:
                                if(useCgb)
                                    return dmaDstAddr & 0x00FF;
                                writefln("WARNING: reading on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                                return 0xFF;

                            pragma(msg, "TODO: implement the 0xFF55 port in read mode (GBC DMA status)");
                            //case 0xFF56:
                            //    TODO

                            //case 0xFF56:
                            //    pragma(msg, "Reading on infrared IO Ports is ignored");
                            //    return 0x00;

                            //case 0xFF40: .. case 0xFF6F:
                            //    pragma(msg, "TODO !!!")
                            //    return 0x00;

                            case 0xFF70:
                            if(useCgb)
                                return workingRamBank;
                            writefln("WARNING: reading on a CGB only port (0x%0.2X) using the SGB mode", address-0xFF00);
                            return 0xFF;

                            default:
                                throw new Exception(format("Execution failure: IO Ports access not implemented (port: 0x%0.2X, mode:read)", address-0xFF00));
                        }
                        throw new Exception(format("Programming error: bad address (%0.4X)", address));

                    // High RAM
                    case 0xFF80: .. case 0xFFFE:
                        return highRam[address - 0xFF80];

                    // IE Flag
                    case 0xFFFF:
                        return cpu.enabledInterrupts();

                    default:
                throw new Exception(format("Programming error: bad address (%0.4X)", address));
                }

            default:
                throw new Exception(format("Programming error: bad address (%0.4X)", address));
        }
    }

    ushort loadWord(ushort address)
    {
        return loadByte(address++) | (loadByte(address) << 8);
    }

    void connectCpu(CpuItf cpu)
    {
        this.cpu = cpu;
    }

    void connectGpu(Mmu8bItf gpuMmu)
    {
        this.gpuMmu = gpuMmu;
    }

    void connectSoundController(Mmu8bItf soundControllerMmu)
    {
        this.soundControllerMmu = soundControllerMmu;
    }

    void connectDividerTimer(DividerTimerItf dividerTimer)
    {
        this.dividerTimer = dividerTimer;
    }

    void connectTimaTimer(TimaTimerItf timaTimer)
    {
        this.timaTimer = timaTimer;
    }

    void connectJoystick(JoystickItf joystick)
    {
        this.joystick = joystick;
    }

    void connectSerialPort(Mmu8bItf serialPort)
    {
        this.serialPort = serialPort;
    }

    void connectCartridgeMmu(Mmu8bItf cartridgeMmu)
    {
        this.cartridgeMmu = cartridgeMmu;
    }
};



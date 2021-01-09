module gbc;

import std.stdio;
import std.conv;

import interfaces.cartridgedata;
import interfaces.mmu8b;
import gbcfile;
import gbccpu;
import gbcgpu;
import gbcsoundcontroller;
import gbcmmu;
import gbclcd;
import gbctimer;
import gbcjoystick;
import gbcserialport;
import nonembc;
import mbc1;
import mbc2;
import mbc3;
import mbc5;


// Composite component
final class Gbc
{
    public:

    immutable uint cpuFrequency = 4_194_304;

    GbcFile cartridgeData;
    Mmu8bItf cartridgeMmu;
    GbcCpu cpu;
    GbcGpu gpu;
    GbcMmu mmu;
    GbcSoundController soundController;
    GbcTimer timer;
    GbcLcd renderer;
    GbcJoystick joystick;
    GbcSerialPort serialPort;

    int clock;
    bool running;

    version(time_tracing)
    {
        long[8] t;
        long[t.length-1] tGlobal = 0;
    }


    public:

    this(string filename)
    {
        // Component instantiation

        cartridgeData = new GbcFile(filename);

        switch(cartridgeData.memoryControlerType)
        {
            case CartridgeMmuType.NONE:
                auto mbc = new NoneMbc();
                mbc.connectCartridgeData(cartridgeData);
                cartridgeMmu = mbc;
                break;

            case CartridgeMmuType.MBC1:
                auto mbc = new Mbc1();
                mbc.connectCartridgeData(cartridgeData);
                cartridgeMmu = mbc;
                break;

            case CartridgeMmuType.MBC2:
                auto mbc = new Mbc2();
                mbc.connectCartridgeData(cartridgeData);
                cartridgeMmu = mbc;
                break;

            case CartridgeMmuType.MBC3:
                auto mbc = new Mbc3();
                mbc.connectCartridgeData(cartridgeData);
                cartridgeMmu = mbc;
                break;

            case CartridgeMmuType.MBC5:
                auto mbc = new Mbc5();
                mbc.connectCartridgeData(cartridgeData);
                cartridgeMmu = mbc;
                break;

            default:
                throw new Exception("Unhandled cartridge memory controler type (" ~ to!string(cartridgeData.memoryControlerType) ~ ")");
        }

        immutable bool useCgb = cartridgeData.requiredGameboy == GameboyType.COLOR;
        cpu = new GbcCpu(useCgb);
        gpu = new GbcGpu(useCgb);
        mmu = new GbcMmu(useCgb);
        soundController = new GbcSoundController(useCgb);
        timer = new GbcTimer();
        renderer = new GbcLcd();
        joystick = new GbcJoystick();
        serialPort = new GbcSerialPort();


        // Component connections

        cpu.connectMmu(mmu);
        gpu.connectRenderer(renderer);
        gpu.connectCpu(cpu);
        mmu.connectCpu(cpu);
        mmu.connectCartridgeMmu(cartridgeMmu);
        mmu.connectGpu(gpu);
        mmu.connectSoundController(soundController);
        mmu.connectTimer(timer);
        mmu.connectJoystick(joystick);
        mmu.connectSerialPort(serialPort);
        timer.connectCpu(cpu);
        joystick.connectCpu(cpu);
        serialPort.connectCpu(cpu);

        running = true;
        clock = 0;
    }

    void tick()
    {
        if(running)
        {
            version(time_tracing)
                t[0] = getCount();

            running = cpu.tick();

            version(time_tracing)
                t[1] = getCount();

            gpu.tick();

            version(time_tracing)
                t[2] = getCount();

            mmu.tick();

            version(time_tracing)
                t[3] = getCount();

            timer.tick();

            version(time_tracing)
                t[4] = getCount();

            joystick.tick();

            version(time_tracing)
                t[5] = getCount();

            soundController.tick();

            version(time_tracing)
                t[6] = getCount();

            serialPort.tick();

            clock++;

            version(time_tracing)
            {
                t[6] = getCount();

                for(int i=0 ; i<tGlobal.length ; ++i)
                    tGlobal[i] += t[i+1] - t[i];

                // Every syncFrequency Hz
                if(clock == cpuFrequency)
                {
                    long tSum = 0;

                    for(int i=0 ; i<tGlobal.length ; ++i)
                        tSum += tGlobal[i];

                    writefln("Timings (physical CPU cycles=%d, virtual GB cycles=%d):", tSum, cpuFrequency);
                    for(int i=0 ; i<tGlobal.length ; ++i)
                    {
                        const string tElem = ["cpu", "gpu", "mmu", "timer", "joystick", "soundController", "serialPort"][i];
                        writefln("    %s=%2.0f%% (cycles=%dM)", tElem, tGlobal[i]*100.0/tSum, tGlobal[i]/1000000);
                    }

                    tGlobal[] = 0;
                }
            }

            // Reset counters every seconds
            if(clock == cpuFrequency)
                clock = 0;
        }
    }

    ~this()
    {
        cartridgeData.destroy();
        cpu.destroy();
        gpu.destroy();
        soundController.destroy();
        mmu.destroy();
        timer.destroy();
        renderer.destroy();
        joystick.destroy();
        serialPort.destroy();
        cartridgeMmu.destroy();
    }

    bool isRunning()
    {
        return running;
    }


    private:

    version(time_tracing)
    {
        version(X86)
        {
            static long getCount()
            {
                asm
                {
                    naked;
                    rdtsc;
                    ret;
                }
            }
        }

        version(X86_64)
        {
            static long getCount()
            {
                asm
                {
                    naked;
                    rdtsc;
                    sal RDX, 32;
                    or RAX, RDX;
                    ret;
                }
            }
        }
    }
};



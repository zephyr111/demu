module gbc;

pragma(msg, "TODO: import useless");
import std.stdio;
import core.thread;
import core.time;
import std.concurrency;
import gtk.Main;
import std.datetime;
import std.conv;
import std.math;

import interfaces.cartridgedata;
import interfaces.mmu8b;
import gbcfile;
import gbccpu;
import gbcgpu;
import gbcsoundcontroller;
import gbcmmu;
import gbclcd;
import gbcdividertimer;
import gbctimatimer;
import gbcjoystick;
import gbcserialport;
import nonembc;
import mbc1;
import mbc2;
import mbc3;
import mbc5;
import gui;


// Composite component
final class Gbc
{
    public:

    immutable uint cpuFrequency = 4_194_304;
    immutable uint syncFrequency = 120;

    GbcFile cartridgeData;
    Mmu8bItf cartridgeMmu;
    GbcCpu cpu;
    GbcGpu gpu;
    GbcMmu mmu;
    GbcSoundController soundController;
    GbcDividerTimer dividerTimer;
    GbcTimaTimer timaTimer;
    GbcLcd renderer;
    GbcJoystick joystick;
    GbcSerialPort serialPort;

    Tid frontendTid;
    int clock;
    bool running;
    StopWatch chrono;

    version(time_tracing)
    {
        long t[8];
        long tGlobal[t.length-1] = 0;
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
        dividerTimer = new GbcDividerTimer();
        timaTimer = new GbcTimaTimer();
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
        mmu.connectDividerTimer(dividerTimer);
        mmu.connectTimaTimer(timaTimer);
        mmu.connectJoystick(joystick);
        mmu.connectSerialPort(serialPort);
        timaTimer.connectCpu(cpu);
        dividerTimer.connectCpu(cpu);
        joystick.connectCpu(cpu);
        serialPort.connectCpu(cpu);


        chrono.start();
        running = true;
        clock = 0;
    }

    void tick()
    {
        if(running)
        {
            version(time_tracing)
                t[0] = getCount();

            running = cpu.tick(); // 38%

            version(time_tracing)
                t[1] = getCount();

            gpu.tick(); // 12%

            version(time_tracing)
                t[2] = getCount();

            timaTimer.tick(); // 4%

            version(time_tracing)
                t[3] = getCount();

            dividerTimer.tick(); // 10%

            version(time_tracing)
                t[4] = getCount();

            joystick.tick(); // 4%

            version(time_tracing)
                t[5] = getCount();

            soundController.tick(); // 20% (with clockStep=16)

            version(time_tracing)
                t[6] = getCount();

            serialPort.tick(); // 12%

            clock++;

            version(time_tracing)
            {
                t[7] = getCount();

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
                        const string tElem = ["cpu", "gpu", "timaTimer", "dividerTimer", "joystick", "soundController", "serialPort"][i];
                        writefln("    %s=%2.0f%% (cycles=%dM)", tElem, tGlobal[i]*100.0/tSum, tGlobal[i]/1000000);
                    }

                    tGlobal[] = 0;
                }
            }

            // Every syncFrequency Hz
            if(clock % (cpuFrequency / syncFrequency) == 0)
            {
                // Controls the speed of the emulation (slow down only if necessary)
                long delay = 1_000_000L * clock / cpuFrequency - chrono.peek().usecs;

                if(delay > 0)
                    Thread.sleep(dur!"usecs"(delay));
            }

            // Reset counters every seconds
            if(clock == cpuFrequency)
            {
                writefln("speed: %d%%", cast(int)((100000000000.0/chrono.peek.nsecs)+0.5));

                chrono.stop();
                clock = 0;
                chrono.reset();
                chrono.start();
            }
        }
    }

    ~this()
    {
        delete cartridgeData;
        delete cpu;
        delete gpu;
        delete soundController;
        delete mmu;
        delete dividerTimer;
        delete timaTimer;
        delete renderer;
        delete joystick;
        delete serialPort;
        delete cartridgeMmu;
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



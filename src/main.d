module main;

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
                xor RAX, RAX;
                rdtsc;
                sal RDX, 32;
                or RAX, RDX;
                ret;
            }
        }
    }
}


void usage()
{
    writeln("usage:");
    writeln("    gba romfile");
}


void emuThread(string filename)
{
    register("backend", thisTid);
    while(locate("frontend") == Tid.init)
        Thread.sleep(dur!"msecs"(10));
    Tid frontendTid = locate("frontend");

    try
    {
        immutable uint cpuFrequency = 4_194_304;
        immutable uint syncFrequency = 120;

        auto cartridgeData = new GbcFile(filename);
        Mmu8bItf externalMmu;

        switch(cartridgeData.memoryControlerType)
        {
            case CartridgeMmuType.NONE:
                auto mbc = new NoneMbc();
                mbc.connectCartridgeData(cartridgeData);
                externalMmu = mbc;
                break;

            case CartridgeMmuType.MBC1:
                auto mbc = new Mbc1();
                mbc.connectCartridgeData(cartridgeData);
                externalMmu = mbc;
                break;

            case CartridgeMmuType.MBC2:
                auto mbc = new Mbc2();
                mbc.connectCartridgeData(cartridgeData);
                externalMmu = mbc;
                break;

            case CartridgeMmuType.MBC3:
                auto mbc = new Mbc3();
                mbc.connectCartridgeData(cartridgeData);
                externalMmu = mbc;
                break;

            case CartridgeMmuType.MBC5:
                auto mbc = new Mbc5();
                mbc.connectCartridgeData(cartridgeData);
                externalMmu = mbc;
                break;

            default:
                throw new Exception("Unhandled cartridge memory controler type (" ~ to!string(cartridgeData.memoryControlerType) ~ ")");
        }

        immutable bool useCgb = cartridgeData.requiredGameboy == GameboyType.COLOR;
        auto cpu = new GbcCpu(useCgb);
        auto gpu = new GbcGpu(useCgb);
        auto mmu = new GbcMmu(useCgb);
        auto soundController = new GbcSoundController(useCgb);
        auto dividerTimer = new GbcDividerTimer();
        auto timaTimer = new GbcTimaTimer();
        auto renderer = new GbcLcd();
        auto joystick = new GbcJoystick();
        auto serialPort = new GbcSerialPort();

        cpu.connectMmu(mmu);
        gpu.connectRenderer(renderer);
        gpu.connectCpu(cpu);
        mmu.connectCpu(cpu);
        mmu.connectCartridgeMmu(externalMmu);
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

        // A revoir !
        receive(
            (shared(Gui) gui) {
                Gui localGui = cast(Gui)gui;
                localGui.connectRenderer(renderer);
                localGui.connectJoystick(joystick);
            }
        );
        frontendTid.send("configured");

        int clock = 0;
        bool running = false;

        StopWatch chrono;
        chrono.start();

        version(time_tracing)
        {
            long t[8];
            long tGlobal[t.length-1] = 0;
        }

        do
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
                        writefln("    %s=%2.0f%% (cycles=%d)", tElem, tGlobal[i]*100.0/tSum, tGlobal[i]);
                    }

                    tGlobal[] = 0;
                }
            }

            // Every syncFrequency Hz
            if(clock % (cpuFrequency / syncFrequency) == 0)
            {
                // Interract with the UI
                receiveTimeout(
                    Duration.zero(),
                    (string signal) { if(signal == "quit") running = false; }
                );

                // Controls the speed of the emulation (slow down only if necessary)
                long delay = 1_000_000L * clock / cpuFrequency - chrono.peek().usecs;

                if(delay > 0)
                    Thread.sleep(dur!"usecs"(delay));
            }

            // Reset counters every seconds
            if(clock == cpuFrequency)
            {
                chrono.stop();
                clock = 0;
                chrono.reset();
                chrono.start();
            }
        }
        while(running);

        frontendTid.send("ended");

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
        delete externalMmu;
    }
    catch(shared Exception error)
    {
        writeln(cast(Exception)error);
        frontendTid.send("error");
    }
}


void main(string[] args)
{
    if(args.length-1 != 1)
    {
        usage();
        return;
    }

    Main.init(args);
    auto gui = new Gui("EmuD");

    // A revoir !
    spawn(&emuThread, args[1]);

    register("frontend", thisTid);
    while(locate("backend") == Tid.init)
        Thread.sleep(dur!"msecs"(10));
    Tid backendTid = locate("backend");

    backendTid.send(cast(shared(Gui))gui);
    receive(
        (string state) { assert(state == "configured"); },
    );

    gui.showAll();
    Main.run();

    backendTid.send("quit");
    receive(
        (string state) { assert(state == "ended" || state == "error"); },
    );
}



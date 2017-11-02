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
        joystick.connectCpu(cpu);

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

        cpu.init();

        StopWatch chrono;
        chrono.start();

        do
        {
            running = cpu.tick(); // 30%
            gpu.tick(); // 30%
            timaTimer.tick(); // 16%
            joystick.tick(); // 8%
            soundController.tick(); // 8%
            serialPort.tick(); // 8%
            clock++;

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



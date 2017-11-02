module main;

pragma(msg, "TODO: import useless");
import std.stdio;
import core.thread;
import core.time;
import std.concurrency;
import gtk.Main;
import std.datetime;
import std.conv;
import std.math;

import gui;


void main(string[] args)
{
    Main.init(args);

    auto gui = new Gui("EmuD", args[1..$], 400, 300);
    gui.showAll();

    Main.run();
}



module main;

import std.stdio;
import gtk.Main;

import gui;


void main(string[] args)
{
    Main.init(args);

    auto gui = new Gui("EmuD", args[1..$], 400, 300);
    gui.showAll();

    Main.run();
}



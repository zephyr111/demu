module gui;

pragma(msg, "TODO: import useless");
import std.stdio;
import std.concurrency;
import std.string;
import core.time;
import core.thread;

import gtk.MainWindow;
//import gdk.Pixbuf;
import gdk.Keysyms;
import gdk.Event;
import gtk.Image;
import gtk.Button;
import gtk.VBox;
import gtk.Main;
import gtk.Widget;
import gtk.DrawingArea;
import gtk.MenuBar;
import gtk.Menu;
import gtk.MenuItem;
import gtk.FileChooserDialog;
import gtk.FileChooserIF;
import glib.Timeout;
import cairo.Context;
import cairo.ImageSurface;

import interfaces.renderer;
import interfaces.joystick;
import gbc;


final class Gui : MainWindow
{
    private:

    RendererItf renderer = null;
    JoystickItf joystick = null;
    Timeout frameUpdate = null;
    DrawingArea renderArea;
    ImageSurface image = null;
    int scale;

    // Warning: should have this scope to be tracked by the GC
    // (the GC don't see the use of the buffer inside the GTK calls)
    ubyte[] imageData;


    public:

    this(string name, string appParams[])
    {
        super(name);
        setBorderWidth(5);

        scale = 4;
        imageData = [];

        VBox box = new VBox(false, 3);
        box.setSpacing(5);

        auto menuBar = new MenuBar();
        auto fileMenu = menuBar.append("_File");
        auto openRomItem = new MenuItem("_Open ROM...");
        openRomItem.addOnActivate(s => openFile);
        fileMenu.append(openRomItem);
        auto closeRomItem = new MenuItem("_Close ROM");
        closeRomItem.addOnActivate((s) {
            connectRenderer(null);
            connectJoystick(null);
            locate("backend").send("close");
        });
        fileMenu.append(closeRomItem);
        auto quitItem = new MenuItem("_Quit");
        quitItem.addOnActivate(s => quit);
        fileMenu.append(quitItem);
        box.packStart(menuBar, false, false, 0);

        renderArea = new DrawingArea();
        renderArea.addOnDraw((Scoped!Context ctx, Widget widget) => update(ctx));
        box.packStart(renderArea, true, true, 0);

        add(box);

        addOnKeyPress(&keyPressed);
        addOnKeyRelease(&keyReleased);
        addOnDestroy(s => quit);

        if(appParams.length > 0)
        {
            pragma(msg, "TODO: to be implemented");
        }

        Tid backend = spawnLinked(&emuThread, cast(shared(Gui))this);
        register("backend", backend);
    }

    this(string name, string appParams[], int width, int height)
    {
        this(name, appParams);
        setDefaultSize(width, height);
    }

    void connectRenderer(RendererItf renderer)
    {
        this.renderer = renderer;

        if(renderer)
        {
            const int w = this.renderer.width();
            const int h = this.renderer.height();

            renderArea.setSizeRequest(w*scale, h*scale);

            const int stride = ImageSurface.formatStrideForWidth(CairoFormat.ARGB32, w);
            imageData = new ubyte[stride*h];
            image = ImageSurface.createForData(imageData.ptr, CairoFormat.ARGB32, w, h, stride);

            if(frameUpdate is null)
                frameUpdate = new Timeout(16u, &frameTimeout);
        }
    }

    void connectJoystick(JoystickItf joystick)
    {
        this.joystick = joystick;
    }


    private:

    static void emuThread(shared(Gui) gui)
    {
        try
        {
            bool quit = false;

            while(!quit)
            {
                string filename;

                while(filename == "" && !quit)
                {
                    receive(
                        (string command) {
                            string[] commandElems = command.split("|");
                            if(commandElems[0] == "load")
                                filename = commandElems[1];
                            else if(commandElems[0] == "quit")
                                quit = true;
                        },
                    );
                }

                if(quit)
                    break;

                bool end = false;
                auto gbc = new Gbc(filename);

                Gui localGui = cast(Gui)gui;
                localGui.connectRenderer(gbc.renderer);
                localGui.connectJoystick(gbc.joystick);

                while(gbc.isRunning() && !end)
                {
                    for(int i=0 ; i<4096 ; ++i)
                    {
                        gbc.tick();
                        if(!gbc.isRunning())
                            break;
                    }

                    receiveTimeout(
                        Duration.zero(),
                        (string command) {
                            string[] commandElems = command.split("|");
                            if(commandElems[0] == "close")
                                end = true;
                            if(commandElems[0] == "quit")
                                end = quit = true;
                        }
                    );
                }

                delete gbc;
            }
        }
        catch(Throwable err)
        {
            writeln("Emulator thread critical failure: ", err);
        }
    }

    void openFile()
    {
        auto dialog = new FileChooserDialog("Open ROM file", this, GtkFileChooserAction.OPEN);

        if(dialog.run() == GtkResponseType.OK)
        {
            string filename = dialog.getFilename();

            Tid backendTid = locate("backend");
            backendTid.send("close");
            backendTid.send("load|" ~ filename);
        }

        dialog.close();
    }

    bool update(Context ctx)
    {
        if(this.renderer !is null)
        {
            const int w = this.renderer.width();
            const int h = this.renderer.height();
            const(ubyte)[] srcData = this.renderer.frontBuffer();
            uint[] dstData = cast(uint[])imageData[];
            const int stride = image.getStride;

            foreach(int y ; 0..h)
            {
                foreach(int x ; 0..w)
                {
                    //foreach(int c ; 0..3)
                    //    imageData[y*stride+x*4+2-c] = srcData[(y*w+x)*3+c];

                    const uint srcOffset = (y*w+x)*3;
                    const uint dstOffset = y*stride/4 + x;
                    dstData[dstOffset] = 0xFF000000 | (srcData[srcOffset+0]<<16) | (srcData[srcOffset+1]<<8) | srcData[srcOffset+2];
                }
            }

            ctx.scale(scale, scale);
            ctx.setSourceSurface(image, 0, 0);
            ctx.getSource.setFilter(CairoFilter.NEAREST);
            ctx.paint();
        }

        return false;
    }

    bool frameTimeout()
    {
        renderArea.queueDraw();

        return renderer !is null;
    }

    void quit()
    {
        locate("backend").send("quit");
        receiveOnly!LinkTerminated();
        Main.quit();
    }

    bool keyPressed(Event event, Widget sender)
    {
        if(joystick !is null)
        {
            switch(event.key.keyval)
            {
                case GdkKeysyms.GDK_Left: joystick.setLeft(true); return true;
                case GdkKeysyms.GDK_Right: joystick.setRight(true); return true;
                case GdkKeysyms.GDK_Up: joystick.setUp(true); return true;
                case GdkKeysyms.GDK_Down: joystick.setDown(true); return true;
                case GdkKeysyms.GDK_w: case GdkKeysyms.GDK_W: joystick.setA(true); return true;
                case GdkKeysyms.GDK_x: case GdkKeysyms.GDK_X: joystick.setB(true); return true;
                case GdkKeysyms.GDK_Return: joystick.setStart(true); return true;
                case GdkKeysyms.GDK_space: joystick.setSelect(true); return true;

                default:
                    break;
            }
        }

        return false;
    }

    bool keyReleased(Event event, Widget sender)
    {
        if(joystick !is null)
        {
            switch(event.key.keyval)
            {
                case GdkKeysyms.GDK_Left: joystick.setLeft(false); return true;
                case GdkKeysyms.GDK_Right: joystick.setRight(false); return true;
                case GdkKeysyms.GDK_Up: joystick.setUp(false); return true;
                case GdkKeysyms.GDK_Down: joystick.setDown(false); return true;
                case GdkKeysyms.GDK_w: case GdkKeysyms.GDK_W: joystick.setA(false); return true;
                case GdkKeysyms.GDK_x: case GdkKeysyms.GDK_X: joystick.setB(false); return true;
                case GdkKeysyms.GDK_Return: joystick.setStart(false); return true;
                case GdkKeysyms.GDK_space: joystick.setSelect(false); return true;

                default:
                    break;
            }
        }

        if(event.key.keyval == GdkKeysyms.GDK_Escape)
        {
            quit();
            return true;
        }

        return false;
    }
};



module gui;

import std.stdio;
import std.algorithm.comparison;
import std.algorithm.searching;
import std.datetime;
import std.file;
import std.uri;
import core.time;

import gtk.MainWindow;
import gdk.Keysyms;
import gdk.Event;
import gtk.Image;
import gtk.VBox;
import gtk.Main;
import gtk.Widget;
import gtk.DrawingArea;
import gtk.MenuBar;
import gtk.Menu;
import gtk.MenuItem;
import gtk.FileChooserDialog;
import gtk.TargetEntry;
import gtk.TargetList;
import gtk.MessageDialog;
import glib.URI;
import glib.Timeout;
import cairo.Context;
import cairo.ImageSurface;

import interfaces.renderer;
import interfaces.joystick;
import gbc;


final class Gui : MainWindow
{
    private:

    static immutable uint drawFrequency = 120;
    static immutable uint coreFrequency = 200;
    static immutable uint emuStepCount = 16;
    RendererItf renderer = null;
    JoystickItf joystick = null;
    Timeout frameUpdate = null;
    DrawingArea renderArea;
    ImageSurface image = null;
    int scale;
    Gbc gbc = null;
    Timeout gbcTickUpdate = null;
    CairoFilter interpolationMode = CairoFilter.NEAREST;
    StopWatch chrono;
    bool maxSpeed = false;

    // Probing variables to evaluate the emulation speed
    uint callCount = 0;
    uint clockSum = 0;
    StopWatch probeChrono;
    float emulationSpeed = 1.0;

    // Warning: should have this scope to be tracked by the GC
    // (the GC don't see the use of the buffer inside the GTK calls)
    ubyte[] imageData;


    public:

    this(string name, string[] appParams)
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
        closeRomItem.addOnActivate((s) { if(gbc !is null) stopGbc(); });
        fileMenu.append(closeRomItem);
        auto quitItem = new MenuItem("_Quit");
        quitItem.addOnActivate(s => quit);
        fileMenu.append(quitItem);
        auto viewMenu = menuBar.append("_View");
        auto zoomMenuItem = viewMenu.appendSubmenu("Set _zoom");
        auto zoomX1Item = new MenuItem("_100%");
        zoomX1Item.addOnActivate(delegate(s) {scale = 1; connectRenderer(renderer);});
        zoomMenuItem.append(zoomX1Item);
        auto zoomX2Item = new MenuItem("_200%");
        zoomX2Item.addOnActivate(delegate(s) {scale = 2; connectRenderer(renderer);});
        zoomMenuItem.append(zoomX2Item);
        auto zoomX3Item = new MenuItem("_300%");
        zoomX3Item.addOnActivate(delegate(s) {scale = 3; connectRenderer(renderer);});
        zoomMenuItem.append(zoomX3Item);
        auto zoomX4Item = new MenuItem("_400%");
        zoomX4Item.addOnActivate(delegate(s) {scale = 4; connectRenderer(renderer);});
        zoomMenuItem.append(zoomX4Item);
        auto zoomX6Item = new MenuItem("_600%");
        zoomX6Item.addOnActivate(delegate(s) {scale = 6; connectRenderer(renderer);});
        zoomMenuItem.append(zoomX6Item);
        auto zoomX8Item = new MenuItem("_800%");
        zoomX8Item.addOnActivate(delegate(s) {scale = 8; connectRenderer(renderer);});
        zoomMenuItem.append(zoomX8Item);
        auto interpolationMenuItem = viewMenu.appendSubmenu("Set _interpolation");
        auto nearestInterpItem = new MenuItem("Nearest (fastest)");
        nearestInterpItem.addOnActivate(delegate(s) {interpolationMode = CairoFilter.NEAREST; connectRenderer(renderer);});
        interpolationMenuItem.append(nearestInterpItem);
        auto bilinearInterpItem = new MenuItem("Bilinear (slower)");
        bilinearInterpItem.addOnActivate(delegate(s) {interpolationMode = CairoFilter.BILINEAR; connectRenderer(renderer);});
        interpolationMenuItem.append(bilinearInterpItem);
        box.packStart(menuBar, false, false, 0);

        renderArea = new DrawingArea();
        renderArea.addOnDraw((Scoped!Context ctx, Widget widget) => update(ctx));
        box.packStart(renderArea, true, true, 0);

        add(box);

        // Drag and drop of ROMs
        TargetEntry[] acceptedTypes = [new TargetEntry("text/uri-list", GtkTargetFlags.OTHER_APP, 0)];
        renderArea.dragDestSet(GtkDestDefaults.ALL, acceptedTypes, GdkDragAction.COPY);

        renderArea.addOnDragDataReceived((context, x, y, selectionData, info, time, widget)
        {
            string[] uriList = selectionData.getUris();

            if(uriList.length != 1)
            {
                printError("Too many file to open");
                return;
            }

            string hostname;
            const string uri = uriList[0].decode;
            const string filename = URI.filenameFromUri(uriList[0], hostname);

            // Check the URI to filename conversion worked
            if(!filename.exists())
            {
                printError(format!"File \"%s\" not found"(filename));
                return;
            }

            if(gbc !is null)
                stopGbc();

            startGbc(filename);
        });

        addOnKeyPress(&keyPressed);
        addOnKeyRelease(&keyReleased);
        addOnDestroy(s => quit);

        if(appParams.length > 0)
            startGbc(appParams[0]);
    }

    this(string name, string[] appParams, int width, int height)
    {
        this(name, appParams);
        setDefaultSize(width, height);
    }

    void connectRenderer(RendererItf newRenderer)
    {
        renderer = newRenderer;

        if(renderer)
        {
            const int w = renderer.width();
            const int h = renderer.height();

            renderArea.setSizeRequest(w*scale, h*scale);

            const int stride = ImageSurface.formatStrideForWidth(CairoFormat.ARGB32, w);
            imageData = new ubyte[stride*h];
            image = ImageSurface.createForData(imageData.ptr, CairoFormat.ARGB32, w, h, stride);

            if(frameUpdate is null)
            {
                immutable uint drawDelay = max(1, 1000/drawFrequency);
                frameUpdate = new Timeout(drawDelay, &frameTimeout, GPriority.LOW);
            }
        }
    }

    void connectJoystick(JoystickItf newJoystick)
    {
        joystick = newJoystick;
    }


    private:

    bool startGbc(string filename)
    {
        assert(gbc is null);

        try
        {
            gbc = new Gbc(filename);
        }
        catch(Exception err)
        {
            printError(format!"Unable to start the ROM \"%s\":\n%s"(filename, err.msg));
            return false;
        }

        connectRenderer(gbc.renderer);
        connectJoystick(gbc.joystick);

        chrono.reset();
        chrono.start();
        probeChrono.reset();
        probeChrono.start();

        immutable uint coreDelay = max(1, 1000/coreFrequency);
        gbcTickUpdate = new Timeout(coreDelay, &gbcTickTimeout, GPriority.LOW);
        return true;
    }

    void stopGbc()
    {
        assert(gbc !is null);

        gbc.destroy();

        if(gbcTickUpdate !is null)
            gbcTickUpdate.stop();

        if(frameUpdate !is null)
            frameUpdate.stop();

        chrono.stop();
        probeChrono.stop();

        gbc = null;
        renderer = null;
        joystick = null;
        gbcTickUpdate = null;
        frameUpdate = null;

        // Refresh the rendered area so it is cleaned
        renderArea.queueDraw();
    }

    void openFile()
    {
        auto dialog = new FileChooserDialog("Open ROM file", this, GtkFileChooserAction.OPEN);

        if(dialog.run() == GtkResponseType.OK)
        {
            string filename = dialog.getFilename();

            if(gbc !is null)
                stopGbc();

            startGbc(filename);
        }

        dialog.close();
    }

    bool update(Context ctx)
    {
        ctx.setSourceRgb(0.0, 0.0, 0.0);
        ctx.paint();

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

            const int gw = renderArea.getAllocatedWidth();
            const int gh = renderArea.getAllocatedHeight();
            ctx.scale(scale, scale);
            ctx.setSourceSurface(image, (gw/scale-w)/2, (gh/scale-h)/2);
            ctx.getSource.setFilter(interpolationMode);
            ctx.paint();
        }

        return false;
    }

    bool frameTimeout()
    {
        renderArea.queueDraw();

        return renderer !is null;
    }

    bool gbcTickTimeout()
    {
        if(gbc is null)
            return false;

        // Controls the speed of the emulation
        // Prevent the computation of the emulation to be too slow (no more than x5 the default time)
        const uint elapsedTime = min(cast(uint)chrono.peek().usecs, 5*1_000_000/coreFrequency);
        uint maxClock = cast(uint)(elapsedTime * 1e-6 * gbc.cpuFrequency);

        emulationSpeed = (clockSum*1.0/gbc.cpuFrequency) / (probeChrono.peek().usecs*1e-6);

        chrono.reset();

        writefln("Speed: %.0f%%", emulationSpeed*100);

        if(callCount >= coreFrequency)
        {
            clockSum = 0;
            callCount = 0;
            probeChrono.stop();
            probeChrono.reset();
            probeChrono.start();
        }
        else
        {
            callCount++;
        }

        if(maxSpeed)
            maxClock *= emuStepCount;

        for(int it=0 ; it<emuStepCount ; ++it)
        {
            const uint localMaxClock = min((maxClock/emuStepCount)*(it+1), maxClock) - (maxClock/emuStepCount)*it;

            for(int clock=0 ; clock<localMaxClock ; ++clock)
                gbc.tick();

            clockSum += localMaxClock;

            // Cut the emulation if it is too slow
            if(chrono.peek().usecs > 1_000_000 / coreFrequency)
                break;
        }

        const bool running = gbc.isRunning();

        if(!running)
            stopGbc();

        return running;
    }

    void quit()
    {
        gbc.destroy();
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
                case GdkKeysyms.GDK_BackSpace: joystick.setSelect(true); return true;
                case GdkKeysyms.GDK_space: maxSpeed = true; return true;

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

    bool keyReleased(Event event, Widget sender)
    {
        //if(this.isSensitive)
        //    return false;

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
                case GdkKeysyms.GDK_BackSpace: joystick.setSelect(false); return true;
                case GdkKeysyms.GDK_space: maxSpeed = false; return true;

                default:
                    break;
            }
        }

        return false;
    }

    void printError(const string msg)
    {
        // Widgets must be manually disabled since GTK dialog popups are not fully modal...
        this.setSensitive(false);

        auto msgBox = new MessageDialog(this, GtkDialogFlags.DESTROY_WITH_PARENT, GtkMessageType.ERROR, GtkButtonsType.CLOSE, msg);
        msgBox.run();
        msgBox.destroy();

        this.setSensitive(true);
    }
};



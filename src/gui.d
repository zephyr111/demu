module gui;

pragma(msg, "TODO: import useless");
import std.stdio;

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
import glib.Timeout;
import cairo.Context;
import cairo.ImageSurface;

import interfaces.renderer;
import interfaces.joystick;


final class Gui : MainWindow
{
    private:

    RendererItf renderer = null;
    JoystickItf joystick = null;
    Timeout frameUpdate = null;
    DrawingArea renderArea;
    ImageSurface image = null;
    int scale;

    // Warning: sould have this scope to be tracked by the GC
    // (the GC don't see the use of the buffer inside the GTK calls)
    ubyte[] imageData;


    public:

    this(string name)
    {
        super(name);
        setBorderWidth(5);

        scale = 4;
        imageData = [];

        VBox box = new VBox(false, 3);
        box.setSpacing(5);

        renderArea = new DrawingArea();
        renderArea.addOnDraw((Scoped!Context ctx, Widget widget) => update(ctx));
        box.packStart(renderArea, true, true, 0);
/*
        Button updateButton = new Button();
        updateButton.setLabel("Update");
        updateButton.addOnClicked(s => update);
        box.packStart(updateButton, false, false, 0);

        Button exitButton = new Button();
        exitButton.setLabel("Exit");
        exitButton.addOnClicked(s => Main.quit);
        box.packStart(exitButton, false, false, 0);
*/
        add(box);

        addOnKeyPress(&keyPressed);
        addOnKeyRelease(&keyReleased);
    }

    this(string name, int width, int height)
    {
        this(name);
        setDefaultSize(width, height);
    }

    void connectRenderer(RendererItf renderer)
    {
        this.renderer = renderer;

        const int w = this.renderer.width();
        const int h = this.renderer.height();

        renderArea.setSizeRequest(w*scale, h*scale);

        const int stride = ImageSurface.formatStrideForWidth(CairoFormat.ARGB32, w);
        imageData = new ubyte[stride*h];
        image = ImageSurface.createForData(imageData.ptr, CairoFormat.ARGB32, w, h, stride);

        if(frameUpdate is null)
            frameUpdate = new Timeout(16u, &frameTimeout);
    }

    void connectJoystick(JoystickItf joystick)
    {
        this.joystick = joystick;
    }


    private:

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
            Main.quit();
            return true;
        }

        return false;
    }
};



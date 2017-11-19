module gbclcd;

import interfaces.renderer;


final class GbcLcd : RendererItf
{
    private:

    ubyte[160*144*3] buff1 = 0x80;
    ubyte[160*144*3] buff2 = 0x80;
    ubyte[] frontBuff;
    ubyte[] backBuff;


    public:

    this()
    {
        frontBuff = buff1;
        backBuff = buff2;
    }

    int width() const
    {
        return 160;
    }

    int height() const
    {
        return 144;
    }

    Color pixel(int x, int y) const
    {
        assert(x >= 0 && x < 160);
        assert(y >= 0 && y < 144);

        const int offset = (x + 160*y) * 3;
        return Color(backBuff[offset], backBuff[offset+1], backBuff[offset+2]);
    }

    void setPixel(int x, int y, Color color)
    {
        assert(x >= 0 && x < 160);
        assert(y >= 0 && y < 144);

        const int offset = (x + 160*y) * 3;
        backBuff[offset+0] = color.r;
        backBuff[offset+1] = color.g;
        backBuff[offset+2] = color.b;
    }

    const(Color)[] scanLine(int y) const
    {
        assert(y >= 0 && y < 144);

        const int offset = y*160*3;
        Color[] res = new Color[160];

        foreach(uint x ; 0..160)
        {
            res[x].r = backBuff[offset+x*3+0];
            res[x].g = backBuff[offset+x*3+1];
            res[x].b = backBuff[offset+x*3+2];
        }

        return res;
    }

    void setScanLine(int y, in Color[] scanline)
    {
        assert(y >= 0 && y < 144);
        assert(scanline.length == 160);

        const int offset = y*160*3;

        static if(Color.sizeof == 3*ubyte.sizeof)
        {
            ubyte* src = cast(ubyte*)scanline.ptr;
            backBuff[offset..offset+160*3] = src[0..160*3];
        }
        else
        {
            foreach(uint x ; 0..160)
            {
                backBuff[offset+x*3+0] = scanline[x].r;
                backBuff[offset+x*3+1] = scanline[x].g;
                backBuff[offset+x*3+2] = scanline[x].b;
            }
        }
    }

    void swapBuffers()
    {
        /*
        ubyte[] tmp = backBuff;
        backBuff = frontBuff;
        frontBuff = tmp;
        */

        // Data have to be copied because the next back buffer should contains 
        // the content of the current back buffer (for incremental drawing)
        frontBuff[] = backBuff[];
    }

    const(ubyte)[] backBuffer() const
    {
        return backBuff;
    }

    const(ubyte)[] frontBuffer() const
    {
        return frontBuff;
    }
};


